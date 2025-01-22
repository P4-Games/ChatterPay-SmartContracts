// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccount, UserOperation} from "lib/entry-point-v6/interfaces/IAccount.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IEntryPoint} from "lib/entry-point-v6/interfaces/IEntryPoint.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {IChatterPayWalletFactory} from "./ChatterPayWalletFactory.sol";
import "forge-std/console2.sol";

/**
 * @title ChatterPay
 * @author ChatterPay Team
 * @notice Smart contract wallet implementation for ChatterPay, supporting ERC-4337 account abstraction
 * @dev This contract implements a smart wallet with Uniswap integration, fee management, and token whitelisting
 */

error ChatterPay__NotFromEntryPoint();
error ChatterPay__NotFromEntryPointOrOwner();
error ChatterPay__NotFromFactoryOwner();
error ChatterPay__ExecuteCallFailed(bytes);
error ChatterPay__PriceFeedNotSet();
error ChatterPay__InvalidPrice();
error ChatterPay__InvalidSlippage();
error ChatterPay__SwapFailed();
error ChatterPay__TokenNotWhitelisted();
error ChatterPay__ZeroAmount();
error ChatterPay__InvalidRouter();
error ChatterPay__NotFeeAdmin();
error ChatterPay__ExceedsMaxFee();
error ChatterPay__ZeroAddress();
error ChatterPay__InvalidPriceFeed();
error ChatterPay__AmountTooLow();
error ChatterPay__InvalidTarget();
error ChatterPay__InsufficientBalance();

interface IERC20Extended is IERC20 {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

contract ChatterPay is
    IAccount,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    ISwapRouter public swapRouter;
    IChatterPayWalletFactory public factory;

    /// @notice The EntryPoint contract address
    IEntryPoint private s_entryPoint;

    /// @notice The Paymaster contract address
    address public s_paymaster;

    /// @notice Current fee in USD cents
    uint256 public s_feeInCents;

    /// @notice Address authorized to modify fees
    address public s_feeAdmin;

    /// @notice Mapping of whitelisted tokens
    mapping(address => bool) public s_whitelistedTokens;

    /// @notice Mapping of token price feeds
    mapping(address => address) public s_priceFeeds;

    /// @notice Mapping of custom pool fees for specific token pairs
    mapping(bytes32 => uint24) public s_customPoolFees;
    
    /// @notice Mapping of custom slippage values for tokens
    mapping(address => uint256) public s_customSlippage;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // Uniswap pool fees
    uint24 public constant POOL_FEE_LOW = 3000; // 0.3%
    uint24 public constant POOL_FEE_MEDIUM = 3000; // 0.3%
    uint24 public constant POOL_FEE_HIGH = 10000; // 1%

    // Default slippage values (in basis points, 1 bp = 0.01%)
    uint256 public constant SLIPPAGE_STABLES = 300;   // 3%
    uint256 public constant SLIPPAGE_ETH = 500;       // 5%
    uint256 public constant SLIPPAGE_BTC = 1000;      // 10%

    uint256 public constant MAX_DEADLINE = 3 minutes;
    uint256 public constant MAX_FEE_IN_CENTS = 1000; // $10.00
    uint256 public constant PRICE_FRESHNESS_THRESHOLD = 1 hours;
    uint256 public constant PRICE_FEED_PRECISION = 8;

    /// @notice Version for upgrades
    string public constant VERSION = "2.0.0";

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokenApproved(address indexed token, address indexed spender, uint256 amount);
    event SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, address recipient);
    event FeeUpdated(uint256 indexed oldFee, uint256 indexed newFee);
    event TokenWhitelisted(address indexed token, bool indexed status);
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);
    event FeeAdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    event CustomPoolFeeSet(address indexed tokenA, address indexed tokenB, uint24 fee);
    event CustomSlippageSet(address indexed token, uint256 slippageBps);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyFactoryOwner() {
        if (msg.sender != factory.owner()) {
            revert ChatterPay__NotFromFactoryOwner();
        }
        _;
    }

    modifier requireFromEntryPointOrOwner() {
        if (msg.sender != address(s_entryPoint) && msg.sender != owner()) {
            revert ChatterPay__NotFromEntryPointOrOwner();
        }
        _;
    }

    modifier onlyFeeAdmin() {
        if (msg.sender != s_feeAdmin) {
            revert ChatterPay__NotFeeAdmin();
        }
        _;
    }

    modifier requireFromEntryPoint() {
        if (msg.sender != address(s_entryPoint)) {
            revert ChatterPay__NotFromEntryPoint();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract
     * @param _entryPoint The EntryPoint contract address
     * @param _newOwner The owner address
     * @param _paymaster The Paymaster contract address
     * @param _router The Uniswap V3 Router address
     * @param _factory The ChatterPay Factory address
     */
    function initialize(
        address _entryPoint,
        address _newOwner,
        address _paymaster,
        address _router,
        address _factory
    ) public initializer {
        if (_entryPoint == address(0)) revert ChatterPay__ZeroAddress();
        if (_newOwner == address(0)) revert ChatterPay__ZeroAddress();
        if (_paymaster == address(0)) revert ChatterPay__ZeroAddress();
        if (_router == address(0)) revert ChatterPay__ZeroAddress();
        if (_factory == address(0)) revert ChatterPay__ZeroAddress();

        __Ownable_init(_newOwner);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        s_entryPoint = IEntryPoint(_entryPoint);
        s_paymaster = _paymaster;
        swapRouter = ISwapRouter(_router);
        factory = IChatterPayWalletFactory(_factory);
        s_feeInCents = 50; // Default 50 cents
        s_feeAdmin = _newOwner;
    }

    /*//////////////////////////////////////////////////////////////
                           MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Approves a token to be spent by the Uniswap Router
     * @param token Token to approve
     * @param amount Amount to approve
     */
    function approveToken(
        address token,
        uint256 amount
    ) external requireFromEntryPointOrOwner nonReentrant {
        if (amount == 0) revert ChatterPay__ZeroAmount();
        if (!s_whitelistedTokens[token])
            revert ChatterPay__TokenNotWhitelisted();

        IERC20(token).safeIncreaseAllowance(address(swapRouter), amount);
        emit TokenApproved(token, address(swapRouter), amount);
    }

    /**
     * @notice Executes a swap through Uniswap V3
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Number of input tokens
     * @param amountOutMin Minimum amount of output tokens expected
     * @param recipient Address that will receive tokens
     */
    function executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient
    ) external requireFromEntryPointOrOwner nonReentrant {
        if (amountIn == 0) revert ChatterPay__ZeroAmount();
        if (recipient == address(0)) revert ChatterPay__ZeroAddress();
        if (!s_whitelistedTokens[tokenIn] || !s_whitelistedTokens[tokenOut]) 
            revert ChatterPay__TokenNotWhitelisted();
        
        // Check balance
        if(IERC20(tokenIn).balanceOf(address(this)) < amountIn) 
            revert ChatterPay__InsufficientBalance();

        // Calculate fee
        uint256 fee = _calculateFee(tokenIn, s_feeInCents);
        if (amountIn < fee * 2) revert ChatterPay__AmountTooLow();

        // Charge fee first
        _transferFee(tokenIn, fee);
        uint256 swapAmount = amountIn - fee;

        // Swap setup
        IERC20(tokenIn).approve(address(swapRouter), swapAmount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: _getPoolFee(tokenIn, tokenOut),
            recipient: recipient,
            amountIn: swapAmount,
            amountOutMinimum: amountOutMin,
            sqrtPriceLimitX96: 0
        });

        try ISwapRouter(swapRouter).exactInputSingle(params) returns (uint256 amountOut) {
            emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, recipient);
        } catch Error(string memory reason) {
            console2.log("Uniswap error reason:", reason);
            revert ChatterPay__SwapFailed();
        } catch (bytes memory errorData) {
            console2.log("Uniswap low-level error:", string(errorData));
            revert ChatterPay__SwapFailed();
        }
    }

    /**
     * @notice Allows the owner of the factory to execute arbitrary calls
     * @dev Only for use in emergencies or special cases
     * @param dest Destination address for the call
     * @param value ETH value to send
     * @param func Function call data
     */
    function execute(
        address dest,
        uint256 value,
        bytes calldata func
    ) external onlyFactoryOwner nonReentrant {
        if(dest == address(this)) revert ChatterPay__InvalidTarget();
        (bool success, bytes memory result) = dest.call{value: value}(func);
        if (!success) revert ChatterPay__ExecuteCallFailed(result);
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the fee amount
     * @param _newFeeInCents New fee in cents
     */
    function updateFee(uint256 _newFeeInCents) external onlyFeeAdmin {
        if (_newFeeInCents > MAX_FEE_IN_CENTS)
            revert ChatterPay__ExceedsMaxFee();
        uint256 oldFee = s_feeInCents;
        s_feeInCents = _newFeeInCents;
        emit FeeUpdated(oldFee, _newFeeInCents);
    }

    /**
     * @notice Updates the fee admin address
     * @param _newAdmin New fee admin address
     */
    function updateFeeAdmin(address _newAdmin) external onlyOwner {
        if (_newAdmin == address(0)) revert ChatterPay__ZeroAddress();
        address oldAdmin = s_feeAdmin;
        s_feeAdmin = _newAdmin;
        emit FeeAdminUpdated(oldAdmin, _newAdmin);
    }

    /**
     * @notice Sets token whitelist and price feed
     * @param token Token address
     * @param status Whitelist status
     * @param priceFeed Oracle price feed address
     */
    function setTokenWhitelistAndPriceFeed(
        address token,
        bool status,
        address priceFeed
    ) external onlyOwner {
        if (token == address(0)) revert ChatterPay__ZeroAddress();
        if (priceFeed == address(0)) revert ChatterPay__ZeroAddress();

        // Validate price feed
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeed);
        try feed.decimals() returns (uint8 decimals) {
            if (decimals != PRICE_FEED_PRECISION)
                revert ChatterPay__InvalidPriceFeed();
        } catch {
            revert ChatterPay__InvalidPriceFeed();
        }

        s_whitelistedTokens[token] = status;
        if (status) {
            s_priceFeeds[token] = priceFeed;
            emit PriceFeedUpdated(token, priceFeed);
        }
        emit TokenWhitelisted(token, status);
    }

    /**
     * @notice Removes a token from whitelist
     * @param token Token to remove
     */
    function removeTokenFromWhitelist(address token) external onlyOwner {
        if (token == address(0)) revert ChatterPay__ZeroAddress();

        delete s_whitelistedTokens[token];
        delete s_priceFeeds[token];

        emit TokenWhitelisted(token, false);
        emit PriceFeedUpdated(token, address(0));
    }

    /**
     * @notice Sets a custom pool fee for a specific token pair
     * @param tokenA First token in pair
     * @param tokenB Second token in pair
     * @param fee Custom fee to use
     */
    function setCustomPoolFee(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external onlyOwner {
        bytes32 pairHash = _getPairHash(tokenA, tokenB);
        s_customPoolFees[pairHash] = fee;
                emit CustomPoolFeeSet(tokenA, tokenB, fee);
    }

    /**
     * @notice Sets custom slippage for a token
     * @param token Token address
     * @param slippageBps Slippage in basis points
     */
    function setCustomSlippage(
        address token,
        uint256 slippageBps
    ) external onlyOwner {
        if(slippageBps > 5000) revert ChatterPay__InvalidSlippage(); // Max 50%
        s_customSlippage[token] = slippageBps;
        emit CustomSlippageSet(token, slippageBps);
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Verify whether a token is a stablecoin
     * @param token Token address to check
     * @return bool True if token is a stablecoin
     */
    function _isStableToken(address token) internal view returns (bool) {
        string memory symbol = IERC20Extended(token).symbol();
        bytes32 symbolHash = keccak256(abi.encodePacked(symbol));
        return (symbolHash == keccak256(abi.encodePacked("USDT")) ||
            symbolHash == keccak256(abi.encodePacked("USDC")) ||
            symbolHash == keccak256(abi.encodePacked("DAI")));
    }

    /**
     * @dev Verify if a token is BTC or similar
     * @param token Token address to check
     * @return bool True if token is a BTC-like token
     */
    function _isBTCToken(address token) internal view returns (bool) {
        string memory symbol = IERC20Extended(token).symbol();
        bytes32 symbolHash = keccak256(abi.encodePacked(symbol));
        return (symbolHash == keccak256(abi.encodePacked("WBTC")) ||
            symbolHash == keccak256(abi.encodePacked("renBTC")));
    }

    /**
     * @dev Gets token price from oracle
     * @param token Token address to get price for
     * @return uint256 Token price with 8 decimals precision
     */
    function _getTokenPrice(address token) internal view returns (uint256) {
        address priceFeedAddr = s_priceFeeds[token];
        if(priceFeedAddr == address(0)) revert ChatterPay__PriceFeedNotSet();
        
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddr);
        
        (
            ,
            int256 price,
            ,
            ,
        ) = priceFeed.latestRoundData();
        
        if(price <= 0) revert ChatterPay__InvalidPrice();
        
        return uint256(price);
    }

    /**
     * @dev Determines the pool fee based on tokens
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @return uint24 Pool fee to use
     */
    function _getPoolFee(
        address tokenIn,
        address tokenOut
    ) internal view returns (uint24) {
        // Check for custom fee first
        bytes32 pairHash = _getPairHash(tokenIn, tokenOut);
        uint24 customFee = s_customPoolFees[pairHash];
        if(customFee != 0) return customFee;

        // Default logic
        if (_isStableToken(tokenIn) && _isStableToken(tokenOut)) {
            return POOL_FEE_LOW;
        }
        return POOL_FEE_MEDIUM;
    }

    /**
     * @dev Generates a unique hash for a token pair
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return bytes32 Unique hash for the token pair
     */
    function _getPairHash(address tokenA, address tokenB) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            tokenA < tokenB ? tokenA : tokenB,
            tokenA < tokenB ? tokenB : tokenA
        ));
    }

    /**
     * @dev Transfers fee to paymaster
     * @param token Token address to transfer
     * @param amount Amount to transfer
     */
    function _transferFee(address token, uint256 amount) internal {
        IERC20(token).safeTransfer(s_paymaster, amount);
    }

    /**
     * @dev Calculates fee in token units
     * @param token Token address to calculate fee for
     * @param feeInCents Fee amount in cents
     * @return uint256 Fee amount in token units
     */
    function _calculateFee(address token, uint256 feeInCents) internal view returns (uint256) {
        uint256 tokenPrice = _getTokenPrice(token);
        uint256 tokenDecimals = IERC20Extended(token).decimals();
        uint256 fee = (feeInCents * (10 ** tokenDecimals)) / (tokenPrice / 1e8) / 100;
        return fee;
    }

    /**
     * @dev Validates a UserOperation signature
     * @param userOp User operation to validate
     * @param userOpHash Hash of the user operation
     * @param missingAccountFunds Missing funds to be paid
     * @return validationData Packed validation data
     */
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external requireFromEntryPoint returns (uint256 validationData) {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            userOpHash
        );
        address signer = ECDSA.recover(ethSignedMessageHash, userOp.signature);
        validationData = signer != owner() ? 1 : 0;
        _payPrefund(missingAccountFunds);
    }

    /**
     * @dev Handles account prefunding
     * @param missingAccountFunds Amount of funds to prefund
     */
    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds != 0) {
            (bool success, ) = payable(msg.sender).call{
                value: missingAccountFunds,
                gas: type(uint256).max
            }("");
            require(success, "ETH transfer failed");
        }
    }

    /**
     * @dev Function that authorizes an upgrade to a new implementation
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // Gap for future upgrades
    uint256[45] private __gap;
}