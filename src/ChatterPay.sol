// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ChatterPay
 * @author ChatterPay Team
 * @notice Smart contract wallet implementation for ChatterPay, supporting ERC-4337 account abstraction
 * @dev This contract implements a smart wallet with Uniswap integration, fee management, and token whitelisting
 */
import {IAccount, UserOperation} from "lib/entry-point-v6/interfaces/IAccount.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IEntryPoint} from "lib/entry-point-v6/interfaces/IEntryPoint.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IChatterPayWalletFactory} from "./ChatterPayWalletFactory.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

error ChatterPay__NotFromEntryPoint();
error ChatterPay__NotFromEntryPointOrOwner();
error ChatterPay__NotFromChatterPayAdmin();
error ChatterPay__ExecuteCallFailed(bytes);
error ChatterPay__PriceFeedNotSet();
error ChatterPay__InvalidPrice();
error ChatterPay__InvalidSlippage();
error ChatterPay__SwapFailed();
error ChatterPay__TokenNotWhitelisted();
error ChatterPay__ZeroAmount();
error ChatterPay__InvalidRouter();
error ChatterPay__ExceedsMaxFee();
error ChatterPay__ZeroAddress();
error ChatterPay__InvalidPriceFeed();
error ChatterPay__AmountTooLow();
error ChatterPay__InvalidTarget();
error ChatterPay__InsufficientBalance();
error ChatterPay__InvalidArrayLengths();
error ChatterPay__InvalidPoolFee();
error ChatterPay__ReentrantCall();
error ChatterPay__TransferFailed();
error ChatterPay__ImplementationInitialization();
error ChatterPay__AlreadyStableToken();
error ChatterPay__NotStableToken();

interface IERC20Extended is IERC20 {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

/**
 * @dev Storage layout contract to prevent storage collisions
 */
contract ChatterPayStorage {
    struct ChatterPayState {
        ISwapRouter swapRouter;
        IChatterPayWalletFactory factory;
        IEntryPoint entryPoint;
        address paymaster;
        uint256 feeInCents;
        uint24 uniswapPoolFeeLow;
        uint24 uniswapPoolFeeMedium;
        uint24 uniswapPoolFeeHigh;
        uint256 slippageMaxBps;
        uint256 maxDeadline;
        uint256 maxFeeInCents;
        uint256 priceFreshnessThreshold;
        uint256 priceFeedPrecision;
        mapping(address => bool) whitelistedTokens;
        mapping(address => address) priceFeeds;
        mapping(bytes32 => uint24) customPoolFees;
        mapping(address => uint256) customSlippage;
        mapping(address => bool) stableTokens;
    }
}

contract ChatterPay is
    IAccount,
    Initializable,
    ContextUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    ChatterPayStorage
{
    using SafeERC20 for IERC20;

    // Storage
    bytes32 internal constant IMPLEMENTATION_SLOT = bytes32(uint256(keccak256("chatterpay.proxy.implementation")) - 1);
    ChatterPayState private s_state;

    /*
    * For simulation purposes, validateUserOp (and validatePaymasterUserOp)
    * must return this value in case of signature failure, instead of revert.
    */
    uint256 constant SIG_VALIDATION_FAILED = 1;

    /*
    * For simulation purposes, validateUserOp (and validatePaymasterUserOp)
    * return this value on success.
    */
    uint256 constant SIG_VALIDATION_SUCCESS = 0;

    uint256 public constant PRICE_FEED_PRECISION = 8;

    // Increased gap for future upgrades
    uint256[100] private __gap;

    /// @notice Version for upgrades
    string public constant VERSION = "2.0.0";

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokenApproved(address indexed token, address indexed spender, uint256 amount);
    event SwapExecuted(
        address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, address recipient
    );
    event FeeUpdated(uint256 indexed oldFee, uint256 indexed newFee);
    event TokenWhitelisted(address indexed token, bool indexed status);
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);
    event CustomPoolFeeSet(address indexed tokenA, address indexed tokenB, uint24 fee);
    event CustomSlippageSet(address indexed token, uint256 slippageBps);
    event TokenTransferCalled(address indexed from, address indexed to, address indexed token, uint256 amount);
    event TokenTransferred(address indexed from, address indexed to, address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyChatterPayAdmin() {
        if (msg.sender != s_state.factory.owner()) {
            revert ChatterPay__NotFromChatterPayAdmin();
        }
        _;
    }

    modifier requireFromEntryPointOrOwner() {
        if (msg.sender != address(s_state.entryPoint) && msg.sender != owner()) {
            revert ChatterPay__NotFromEntryPointOrOwner();
        }
        _;
    }

    modifier requireFromEntryPoint() {
        if (msg.sender != address(s_state.entryPoint)) {
            revert ChatterPay__NotFromEntryPoint();
        }
        _;
    }

    /**
     * ChatterPay__NotFromChatterPayAdmin
     * @dev Disables initialization for the implementation contract
     */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract
     * @param _entryPoint The EntryPoint contract address
     * @param _owner The owner address
     * @param _paymaster The Paymaster contract address
     * @param _router The Uniswap V3 Router address
     * @param _factory The ChatterPay Factory address
     */
    function initialize(
        address _entryPoint,
        address _owner,
        address _paymaster,
        address _router,
        address _factory,
        address[] calldata _whitelistedTokens,
        address[] calldata _priceFeeds,
        bool[] calldata _tokensStableFlags
    ) public initializer {
        if (address(this) == implementation()) {
            revert ChatterPay__ImplementationInitialization();
        }

        if (_entryPoint == address(0)) revert ChatterPay__ZeroAddress();
        if (_owner == address(0)) revert ChatterPay__ZeroAddress();
        if (_paymaster == address(0)) revert ChatterPay__ZeroAddress();
        if (_router == address(0)) revert ChatterPay__ZeroAddress();
        if (_factory == address(0)) revert ChatterPay__ZeroAddress();

        // Ensure arrays for token whitelisting match in length (tokens with price fees)
        if (_whitelistedTokens.length != _priceFeeds.length) {
            revert ChatterPay__InvalidArrayLengths();
        }

        // Ensure arrays for token whitelisting match in length (tokens with tokens-stables-flag)
        if (_whitelistedTokens.length != _tokensStableFlags.length) {
            revert ChatterPay__InvalidArrayLengths();
        }

        // Initialize all parent contracts in inheritance order
        __Context_init();
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init_unchained();

        s_state.entryPoint = IEntryPoint(_entryPoint);
        s_state.paymaster = _paymaster;
        s_state.swapRouter = ISwapRouter(_router);
        s_state.factory = IChatterPayWalletFactory(_factory);
        s_state.feeInCents = 50; // Default fee in cents

        s_state.uniswapPoolFeeLow = 3000; // 0.3%
        s_state.uniswapPoolFeeMedium = 3000; // 0.3%
        s_state.uniswapPoolFeeHigh = 10000; // 1%
        s_state.slippageMaxBps = 5000;

        s_state.maxDeadline = 3 minutes;
        s_state.maxFeeInCents = 1000; // $10.00
        s_state.priceFreshnessThreshold = 1 hours;
        s_state.priceFeedPrecision = 8;

        // Set initial token whitelist and price feeds
        for (uint256 i = 0; i < _whitelistedTokens.length; i++) {
            address token = _whitelistedTokens[i];
            address priceFeed = _priceFeeds[i];
            bool tokenStableFlag = _tokensStableFlags[i];

            if (token == address(0) || priceFeed == address(0)) {
                revert ChatterPay__ZeroAddress();
            }

            AggregatorV3Interface feed = AggregatorV3Interface(priceFeed);
            try feed.decimals() returns (uint8 decimals) {
                if (decimals != PRICE_FEED_PRECISION) {
                    revert ChatterPay__InvalidPriceFeed();
                }
            } catch {
                revert ChatterPay__InvalidPriceFeed();
            }
            s_state.whitelistedTokens[token] = true;
            s_state.priceFeeds[token] = priceFeed;
            s_state.stableTokens[token] = tokenStableFlag;

            emit PriceFeedUpdated(token, priceFeed);
            emit TokenWhitelisted(token, true);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function implementation() public view returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }

    function getChatterPayOwner() public view returns (address) {
        return s_state.factory.owner();
    }

    function getFeeInCents() public view returns (uint256) {
        return s_state.feeInCents;
    }

    function isTokenWhitelisted(address token) public view returns (bool) {
        return s_state.whitelistedTokens[token];
    }

    function getPriceFeed(address token) public view returns (address) {
        return s_state.priceFeeds[token];
    }

    function getCustomPoolFee(bytes32 pairHash) public view returns (uint24) {
        return s_state.customPoolFees[pairHash];
    }

    function getCustomSlippage(address token) public view returns (uint256) {
        return s_state.customSlippage[token];
    }

    function getSwapRouter() public view returns (ISwapRouter) {
        return s_state.swapRouter;
    }

    function getEntryPoint() external view returns (address) {
        return address(s_state.entryPoint);
    }

    function isStableToken(address token) public view returns (bool) {
        return s_state.stableTokens[token];
    }

    function getPoolFees() external view returns (uint24 low, uint24 medium, uint24 high) {
        return (s_state.uniswapPoolFeeLow, s_state.uniswapPoolFeeMedium, s_state.uniswapPoolFeeHigh);
    }

    function getSlippageMaxBps() external view returns (uint256) {
        return s_state.slippageMaxBps;
    }

    function getMaxDeadline() external view returns (uint256) {
        return s_state.maxDeadline;
    }

    function getMaxFeeInCents() external view returns (uint256) {
        return s_state.maxFeeInCents;
    }

    function getPriceFreshnessThreshold() external view returns (uint256) {
        return s_state.priceFreshnessThreshold;
    }

    function getPriceFeedPrecision() external view returns (uint256) {
        return s_state.priceFeedPrecision;
    }

    /**
     * @notice Returns the fee amount in token units for a given token,
     *         using the global feeInCents value from contract state.
     * @param token The token address
     * @return The calculated fee in token units
     * @dev Reverts if the token is not whitelisted
     */
    function getTokenFee(address token) external view returns (uint256) {
        if (!s_state.whitelistedTokens[token]) {
            revert ChatterPay__TokenNotWhitelisted();
        }
        return _calculateFee(token, s_state.feeInCents);
    }

    /*//////////////////////////////////////////////////////////////
                           MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Approves a token to be spent by the Uniswap Router
     * @param token Token to approve
     * @param amount Amount to approve
     */
    function approveToken(address token, uint256 amount) external requireFromEntryPointOrOwner nonReentrant {
        if (amount == 0) revert ChatterPay__ZeroAmount();
        if (!s_state.whitelistedTokens[token]) {
            revert ChatterPay__TokenNotWhitelisted();
        }

        IERC20(token).safeIncreaseAllowance(address(s_state.swapRouter), amount);
        emit TokenApproved(token, address(s_state.swapRouter), amount);
    }

    /**
     * @notice Executes a token transfer from this contract to a recipient
     * @dev Only callable by the EntryPoint contract and protected against reentrancy
     * @param token The ERC20 token address to transfer
     * @param recipient The address that will receive the tokens
     * @param amount The total amount of tokens to transfer (including fee)
     */
    function executeTokenTransfer(address token, address recipient, uint256 amount)
        external
        requireFromEntryPoint
        nonReentrant
    {
        emit TokenTransferCalled(address(msg.sender), recipient, token, amount);

        if (amount == 0) revert ChatterPay__ZeroAmount();
        if (recipient == address(0)) revert ChatterPay__ZeroAddress();
        if (!s_state.whitelistedTokens[token]) revert ChatterPay__TokenNotWhitelisted();

        uint256 balance = IERC20(token).balanceOf(address((this)));
        if (balance < amount) revert ChatterPay__InsufficientBalance();

        uint256 fee = _calculateFee(token, s_state.feeInCents);
        if (amount < fee * 2) revert ChatterPay__AmountTooLow();

        _transferFee(token, fee);
        uint256 transferAmount = amount - fee;

        IERC20(token).safeTransfer(recipient, transferAmount);

        emit TokenTransferred(address(this), recipient, token, transferAmount);
    }

    /**
     * @notice Executes multiple token transfers with fee deduction
     * @param tokens Array of token addresses to transfer
     * @param recipients Array of addresses that will receive tokens
     * @param amounts Array of token amounts to transfer
     * @dev All arrays must have the same length
     */
    function executeBatchTokenTransfer(
        address[] calldata tokens,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external requireFromEntryPoint nonReentrant {
        // Check array lengths match
        if (tokens.length != recipients.length || tokens.length != amounts.length) {
            revert ChatterPay__InvalidArrayLengths();
        }

        // Process each transfer
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            address recipient = recipients[i];
            uint256 amount = amounts[i];

            // Validate parameters
            if (amount == 0) revert ChatterPay__ZeroAmount();
            if (recipient == address(0)) revert ChatterPay__ZeroAddress();
            if (!s_state.whitelistedTokens[token]) revert ChatterPay__TokenNotWhitelisted();

            // Check balance
            if (IERC20(token).balanceOf(address(this)) < amount) {
                revert ChatterPay__InsufficientBalance();
            }

            // Calculate fee
            uint256 fee = _calculateFee(token, s_state.feeInCents);
            if (amount < fee * 2) revert ChatterPay__AmountTooLow();

            // Transfer fee first
            _transferFee(token, fee);

            // Transfer remaining amount to recipient
            uint256 transferAmount = amount - fee;
            IERC20(token).safeTransfer(recipient, transferAmount);
        }
    }

    /**
     * @notice Executes a swap through Uniswap V3
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Number of input tokens
     * @param amountOutMin Minimum amount of output tokens expected
     * @param recipient Address that will receive tokens
     */
    function executeSwap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin, address recipient)
        external
        requireFromEntryPointOrOwner
        nonReentrant
    {
        if (amountIn == 0) revert ChatterPay__ZeroAmount();
        if (recipient == address(0)) revert ChatterPay__ZeroAddress();
        if (!s_state.whitelistedTokens[tokenIn] || !s_state.whitelistedTokens[tokenOut]) {
            revert ChatterPay__TokenNotWhitelisted();
        }

        // Check balance
        if (IERC20(tokenIn).balanceOf(address(this)) < amountIn) {
            revert ChatterPay__InsufficientBalance();
        }

        // Calculate fee
        uint256 fee = _calculateFee(tokenIn, s_state.feeInCents);
        if (amountIn < fee * 2) revert ChatterPay__AmountTooLow();

        // Charge fee first
        _transferFee(tokenIn, fee);
        uint256 swapAmount = amountIn - fee;

        // Swap setup
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: _getPoolFee(tokenIn, tokenOut),
            recipient: recipient,
            amountIn: swapAmount,
            amountOutMinimum: amountOutMin,
            sqrtPriceLimitX96: 0
        });

        try s_state.swapRouter.exactInputSingle(params) returns (uint256 amountOut) {
            emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, recipient);
        } catch Error(string memory) {
            revert ChatterPay__SwapFailed();
        } catch (bytes memory) {
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
    function execute(address dest, uint256 value, bytes calldata func) external onlyChatterPayAdmin nonReentrant {
        if (dest == address(this)) revert ChatterPay__InvalidTarget();
        (bool success, bytes memory result) = dest.call{value: value}(func);
        if (!success) revert ChatterPay__ExecuteCallFailed(result);
    }

    /**
     * @dev Validates a UserOperation signature
     * @param userOp User operation to validate
     * @param userOpHash Hash of the user operation
     * @param missingAccountFunds Missing funds to be paid
     * @return validationData Packed validation data
     */
    function validateUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        requireFromEntryPoint
        returns (uint256 validationData)
    {
        validationData = _validateSignature(userOp, userOpHash);
        _payPrefund(missingAccountFunds);
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfers ownership of the contract with additional privilege management
     * @dev Overrides the standard transferOwnership to manage fee admin privileges
     * @param newOwner Address of the new contract owner
     */
    function transferOwnership(address newOwner) public override onlyOwner {
        super.transferOwnership(newOwner);
    }

    /**
     * @notice Updates the fee amount
     * @param _newFeeInCents New fee in cents
     */
    function updateFee(uint256 _newFeeInCents) external onlyChatterPayAdmin {
        if (_newFeeInCents > s_state.maxFeeInCents) {
            revert ChatterPay__ExceedsMaxFee();
        }
        uint256 oldFee = s_state.feeInCents;
        s_state.feeInCents = _newFeeInCents;
        emit FeeUpdated(oldFee, _newFeeInCents);
    }

    /**
     * @notice Sets token whitelist and price feed
     * @param token Token address
     * @param status Whitelist status
     * @param priceFeed Oracle price feed address
     */
    function setTokenWhitelistAndPriceFeed(address token, bool status, address priceFeed) external onlyOwner {
        if (token == address(0)) revert ChatterPay__ZeroAddress();
        if (priceFeed == address(0)) revert ChatterPay__ZeroAddress();

        // Validate price feed
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeed);
        try feed.decimals() returns (uint8 decimals) {
            if (decimals != PRICE_FEED_PRECISION) {
                revert ChatterPay__InvalidPriceFeed();
            }
        } catch {
            revert ChatterPay__InvalidPriceFeed();
        }

        s_state.whitelistedTokens[token] = status;
        if (status) {
            s_state.priceFeeds[token] = priceFeed;
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

        delete s_state.whitelistedTokens[token];
        delete s_state.priceFeeds[token];

        emit TokenWhitelisted(token, false);
        emit PriceFeedUpdated(token, address(0));
    }

    /**
     * @notice Adds a token to the list of recognized stablecoins
     * @dev Only callable by the contract owner
     * @param token The address of the token to mark as stable
     * @custom:error ChatterPay__ZeroAddress if the token address is zero
     * @custom:error ChatterPay__AlreadyStableToken if the token is already marked as stable
     */
    function addStableToken(address token) external onlyOwner {
        if (token == address(0)) revert ChatterPay__ZeroAddress();
        if (s_state.stableTokens[token]) revert ChatterPay__AlreadyStableToken();
        s_state.stableTokens[token] = true;
    }

    /**
     * @notice Removes a token from the list of recognized stablecoins
     * @dev Only callable by the contract owner
     * @param token The address of the token to remove from the stable list
     * @custom:error ChatterPay__ZeroAddress if the token address is zero
     * @custom:error ChatterPay__NotStableToken if the token is not marked as stable
     */
    function removeStableToken(address token) external onlyOwner {
        if (token == address(0)) revert ChatterPay__ZeroAddress();
        if (!s_state.stableTokens[token]) revert ChatterPay__NotStableToken();
        delete s_state.stableTokens[token];
    }

    /**
     * @notice Sets a custom pool fee for a specific token pair
     * @param tokenA First token in pair
     * @param tokenB Second token in pair
     * @param fee Custom fee to use
     */
    function setCustomPoolFee(address tokenA, address tokenB, uint24 fee) external onlyOwner {
        if (fee > s_state.uniswapPoolFeeHigh) revert ChatterPay__InvalidPoolFee();

        bytes32 pairHash = _getPairHash(tokenA, tokenB);
        s_state.customPoolFees[pairHash] = fee;
        emit CustomPoolFeeSet(tokenA, tokenB, fee);
    }

    /**
     * @notice Sets custom slippage for a token
     * @param token Token address
     * @param slippageBps Slippage in basis points
     */
    function setCustomSlippage(address token, uint256 slippageBps) external onlyOwner {
        if (slippageBps > s_state.slippageMaxBps) revert ChatterPay__InvalidSlippage();
        s_state.customSlippage[token] = slippageBps;
        emit CustomSlippageSet(token, slippageBps);
    }

    function updateUniswapPoolFees(uint24 low, uint24 medium, uint24 high) external onlyOwner {
        s_state.uniswapPoolFeeLow = low;
        s_state.uniswapPoolFeeMedium = medium;
        s_state.uniswapPoolFeeHigh = high;
    }

    function updateSlippageMaxBps(uint256 slippageMaxBps) external onlyOwner {
        s_state.slippageMaxBps = slippageMaxBps;
    }

    function updatePriceConfig(uint256 freshness, uint256 precision) external onlyOwner {
        s_state.priceFreshnessThreshold = freshness;
        s_state.priceFeedPrecision = precision;
    }

    function updateLimits(uint256 deadline, uint256 maxFeeCents) external onlyOwner {
        s_state.maxDeadline = deadline;
        s_state.maxFeeInCents = maxFeeCents;
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
        if (token == address(0)) revert ChatterPay__ZeroAddress();
        return s_state.stableTokens[token];
    }

    /**
     * @dev Gets token price from oracle
     * @param token Token address to get price for
     * @return uint256 Token price with 8 decimals precision
     */
    function _getTokenPrice(address token) internal view returns (uint256) {
        address priceFeedAddr = s_state.priceFeeds[token];
        if (priceFeedAddr == address(0)) revert ChatterPay__PriceFeedNotSet();

        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddr);

        (, int256 price,,,) = priceFeed.latestRoundData();

        if (price <= 0) revert ChatterPay__InvalidPrice();

        return uint256(price);
    }

    /**
     * @dev Determines the pool fee based on tokens
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @return uint24 Pool fee to use
     */
    function _getPoolFee(address tokenIn, address tokenOut) internal view returns (uint24) {
        // Check for custom fee first
        bytes32 pairHash = _getPairHash(tokenIn, tokenOut);
        uint24 customFee = s_state.customPoolFees[pairHash];
        if (customFee != 0) return customFee;

        // Default logic
        if (_isStableToken(tokenIn) && _isStableToken(tokenOut)) {
            return s_state.uniswapPoolFeeLow;
            // return  POOL_FEE_LOW;
        }
        return s_state.uniswapPoolFeeMedium; //
            // return POOL_FEE_MEDIUM;
    }

    /**
     * @dev Generates a unique hash for a token pair
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return bytes32 Unique hash for the token pair
     */
    function _getPairHash(address tokenA, address tokenB) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenA < tokenB ? tokenA : tokenB, tokenA < tokenB ? tokenB : tokenA));
    }

    /**
     * @dev Transfers fee to owner
     * @param token Token address to transfer
     * @param amount Amount to transfer
     */
    function _transferFee(address token, uint256 amount) internal {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /**
     * @dev Calculates fee in token units
     * @param token Token address to calculate fee for
     * @param feeInCents Fee amount in cents
     * @return uint256 Fee amount in token units
     */
    function _calculateFee(address token, uint256 feeInCents) internal view returns (uint256) {
        uint256 tokenPrice = _getTokenPrice(token); // Price has 8 decimals from Chainlink
        uint256 tokenDecimals = IERC20Extended(token).decimals();
        uint256 fee = (feeInCents * (10 ** tokenDecimals) * 1e8) / (tokenPrice * 100);
        return fee;
    }

    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256 validationData)
    {
        // EIP-191 version of the signed hash
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address signer = ECDSA.recover(ethSignedMessageHash, userOp.signature);

        // owner: Returns the user's wallet (executed via the EntryPoint!).
        // If requested from the command line, it will return the owner who deployed the contract (backend signer).
        // signer: The person who signed the userOperation, which must be the wallet owner.
        if (signer != owner()) {
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }

    /**
     * @dev Handles account prefunding by sending ETH to the EntryPoint (msg.sender).
     * The success of the transfer is intentionally not enforced, as the EntryPoint
     * itself is responsible for validating whether it received sufficient funds.
     * Reverting here could interfere with bundler simulation and ERC-4337 flow,
     * so failures are ignored by design.
     * @param missingAccountFunds The minimum amount of ETH to send to the EntryPoint.
     */
    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds, gas: gasleft()}("");
            // Intentionally ignoring success — EntryPoint validates received funds
            (success);
        }
    }

    /**
     * @dev Function that authorizes an upgrade to a new implementation
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyChatterPayAdmin {}

    receive() external payable {}
}
