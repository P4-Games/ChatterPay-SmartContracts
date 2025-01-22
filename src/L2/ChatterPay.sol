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

error ChatterPay__NotFromEntryPoint();
error ChatterPay__NotFromEntryPointOrOwner();
error ChatterPay__NotFromFactoryOwner();
error ChatterPay__ExecuteCallFailed(bytes);
error ChatterPay__PriceFeedNotSet();
error ChatterPay__StalePrice();
error ChatterPay__InvalidPrice();
error ChatterPay__InvalidSlippage();
error ChatterPay__SwapFailed();
error ChatterPay__TokenNotWhitelisted();
error ChatterPay__DeadlineExpired();
error ChatterPay__ZeroAmount();
error ChatterPay__InvalidRouter();
error ChatterPay__NotFeeAdmin();
error ChatterPay__ExceedsMaxFee();
error ChatterPay__ZeroAddress();
error ChatterPay__InvalidPriceFeed();
error ChatterPay__AmountTooLow();

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

    ISwapRouter public swapRouter;
    IChatterPayWalletFactory public factory;

    // Uniswap constants
    uint24 public constant POOL_FEE_LOW = 100; // 0.3%
    uint24 public constant POOL_FEE_MEDIUM = 100; // 0.3%
    uint24 public constant POOL_FEE_HIGH = 10000; // 1%

    // Slippage constants (in basis points, 1 bp = 0.01%)
    uint256 public constant SLIPPAGE_STABLES = 300;   // 3%
    uint256 public constant SLIPPAGE_ETH = 500;       // 5%
    uint256 public constant SLIPPAGE_BTC = 1000;      // 10%

    uint256 public constant MAX_DEADLINE = 3 minutes;

    event TokenApproved(
        address indexed token,
        address indexed spender,
        uint256 amount
    );
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    );

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

    /**
     * @dev Verify whether a token is a stablecoin
     */
    function _isStableToken(address token) internal view returns (bool) {
        string memory symbol = IERC20Extended(token).symbol();
        bytes32 symbolHash = keccak256(abi.encodePacked(symbol));
        return (symbolHash == keccak256(abi.encodePacked("USDT")) ||
            symbolHash == keccak256(abi.encodePacked("USDC")) ||
            symbolHash == keccak256(abi.encodePacked("DAI")));
    }

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
        if (!s_whitelistedTokens[tokenIn]) revert ChatterPay__TokenNotWhitelisted();

        // Calculate fee in input token units
        uint256 fee = _calculateFee(tokenIn, s_feeInCents);
        console2.log("Fee (cents):", s_feeInCents);
        console2.log("Fee (tokens):", fee);
        
        // Verify input amount is at least 2x fee
        if (amountIn < fee * 2) revert ChatterPay__AmountTooLow();

        // Charge fee first
        _transferFee(tokenIn, fee);
        uint256 swapAmount = amountIn - fee;
        console2.log("Amount in:", amountIn);
        console2.log("Swap amount:", swapAmount);
        console2.log("Amount min out:", amountOutMin);

        // Swap setup
        uint256 deadline = block.timestamp + MAX_DEADLINE;
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
     */
    function execute(
        address dest,
        uint256 value,
        bytes calldata func
    ) external onlyFactoryOwner nonReentrant {
        (bool success, bytes memory result) = dest.call{value: value}(func);
        if (!success) revert ChatterPay__ExecuteCallFailed(result);
    }

    // INTERNAL FUNCTIONS

    /**
     * @dev Determines the pool fee based on tokens
     */
    function _getPoolFee(
        address tokenIn,
        address tokenOut
    ) internal view returns (uint24) {
        // If both are stable, use low fee
        if (_isStableToken(tokenIn) && _isStableToken(tokenOut)) {
            return POOL_FEE_LOW;
        }
        // For other pairs, use medium fee
        return POOL_FEE_MEDIUM;
    }

    /**
     * @dev Gets the maximum slippage allowed for a pair of tokens
     */
    function _getMaxSlippage(
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256) {
        if (_isStableToken(tokenIn) && _isStableToken(tokenOut)) {
            return SLIPPAGE_STABLES;
        }
        if (_isBTCToken(tokenIn) || _isBTCToken(tokenOut)) {
            return SLIPPAGE_BTC;
        }
        return SLIPPAGE_ETH;
    }

    /**
     * @dev Verify if a token is BTC or similar
     */
    function _isBTCToken(address token) internal view returns (bool) {
        string memory symbol = IERC20Extended(token).symbol();
        bytes32 symbolHash = keccak256(abi.encodePacked(symbol));
        return (symbolHash == keccak256(abi.encodePacked("WBTC")) ||
            symbolHash == keccak256(abi.encodePacked("renBTC")));
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The EntryPoint contract address
    IEntryPoint private s_entryPoint;

    /// @notice The Paymaster contract address
    address public s_paymaster;

    /// @notice Current fee in USD cents
    uint256 public s_feeInCents;

    /// @notice Address authorized to modify fees
    address public s_feeAdmin;

    /// @notice Maximum fee that can be set (in cents)
    uint256 public constant MAX_FEE_IN_CENTS = 1000; // $10.00

    /// @notice Mapping of whitelisted tokens
    mapping(address => bool) public s_whitelistedTokens;

    /// @notice Mapping of token price feeds
    mapping(address => address) public s_priceFeeds;

    /// @notice Maximum time before price is considered stale
    uint256 public constant PRICE_FRESHNESS_THRESHOLD = 1 hours;

    /// @notice Expected decimals for price feed
    uint256 public constant PRICE_FEED_PRECISION = 8;

    /// @notice Version for upgrades
    string public constant VERSION = "2.0.0";

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event FeeUpdated(uint256 indexed oldFee, uint256 indexed newFee);
    event TokenWhitelisted(address indexed token, bool indexed status);
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);
    event FeeAdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    /**
     * @notice Initializes the contract
     * @param _entryPoint The EntryPoint contract address
     * @param _newOwner The owner address
     * @param _paymaster The Paymaster contract address
     * @param _router The Uniswap V3 Router address
     * @param _factory The ChatterPay Factory address
     */
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

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Gets token price from oracle
     */
    function _getTokenPrice(address token) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        
        // Get latest price
        (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        
        console2.log("Price feed data:");
        console2.log("- Round ID:", roundId);
        console2.log("- Price:", uint256(price));
        console2.log("- Updated at:", updatedAt);
        
        require(price > 0, "Invalid price");
        require(updatedAt > 0, "Round not complete");
        require(answeredInRound >= roundId, "Stale price");
        
        return uint256(price);
    }

    /**
     * @dev Transfers fee to paymaster
     */
    function _transferFee(address token, uint256 amount) internal {
        IERC20(token).safeTransfer(s_paymaster, amount);
    }

    /**
     * @dev Calculates fee in token units
     */
    function _calculateFee(address token, uint256 feeInCents) internal view returns (uint256) {
        // Get token price from Chainlink
        uint256 tokenPrice = _getTokenPrice(token);
        console2.log("Token price from oracle:", tokenPrice);  // Should be ~100004202 for USDC
    
        uint256 tokenDecimals = IERC20Extended(token).decimals();
        uint256 fee = (feeInCents * (10 ** tokenDecimals)) / (tokenPrice / 1e8) / 100;
        
        console2.log("Fee calculation:");
        console2.log("- Fee in cents:", feeInCents);
        console2.log("- Token decimals:", IERC20Extended(token).decimals());
        console2.log("- Calculated fee in tokens:", fee);
        
        return fee;
    }

    /**
     * @dev Validates a UserOperation signature
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

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // Gap for future upgrades
    uint256[45] private __gap;
}
