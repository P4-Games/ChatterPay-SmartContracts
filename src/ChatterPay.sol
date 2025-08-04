// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
// IMPORTS
//////////////////////////////////////////////////////////////*/

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
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

/*//////////////////////////////////////////////////////////////
// ERRORS
//////////////////////////////////////////////////////////////*/

error ChatterPay__NotFromEntryPoint();
error ChatterPay__NotFromEntryPointOrOwner();
error ChatterPay__NotFromChatterPayAdmin();
error ChatterPay__ExecuteCallFailed(bytes);
error ChatterPay__PriceFeedNotSet();
error ChatterPay__InvalidPrice(uint256 price);
error ChatterPay__InvalidPriceRound(uint80 answeredInRound, uint80 roundId);
error ChatterPay__InvalidPriceFreshnessThreshold(uint256 blockTimestamp, uint256 updatedAt, uint256 threshold);
error ChatterPay__InvalidPriceFeed();
error ChatterPay__InvalidSlippage();
error ChatterPay__SwapFailed();
error ChatterPay__TokenNotWhitelisted();
error ChatterPay__ZeroAmount();
error ChatterPay__InvalidRouter();
error ChatterPay__ExceedsMaxFee();
error ChatterPay__ZeroAddress();
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
error ChatterPay__InvalidDecimals();
error ChatterPay__InvalidFeeOverflow();

/*//////////////////////////////////////////////////////////////
// INTERFACES
//////////////////////////////////////////////////////////////*/

interface IERC20Extended is IERC20 {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

/**
 * @title ChatterPay
 * @author ChatterPay Team
 * @notice Smart contract wallet implementation for ChatterPay, supporting ERC-4337 account abstraction
 * @dev This contract implements a smart wallet with Uniswap integration, fee management, and token whitelisting
 */
contract ChatterPay is
    IAccount,
    Initializable,
    ContextUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    EIP712Upgradeable
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
    // CONSTANTS & VARIABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal state struct containing all configurable and runtime parameters for ChatterPay.
     * @dev This struct is stored at a custom storage slot to support upgradeable proxy patterns.
     */
    struct ChatterPayState {
        ISwapRouter swapRouter; // Uniswap V3 router instance
        IChatterPayWalletFactory factory; // Factory contract that deployed the wallet
        IEntryPoint entryPoint; // ERC-4337 EntryPoint contract
        address paymaster; // Paymaster contract address
        uint256 feeInCents; // Fee charged on transactions, in cents
        uint24 uniswapPoolFeeLow; // Pool fee for stable-to-stable swaps
        uint24 uniswapPoolFeeMedium; // Pool fee for other token swaps
        uint24 uniswapPoolFeeHigh; // Reserved for high-volatility pairs
        uint256 slippageMaxBps; // Maximum allowed slippage in basis points
        uint256 maxDeadline; // Maximum time window (in seconds) for swaps
        uint256 maxFeeInCents; // Cap for the fee value in cents
        uint256 priceFreshnessThreshold; // Max age of Chainlink price data in seconds
        uint256 priceFeedPrecision; // Precision multiplier for price conversions
        bool allowEIP191Fallback; // Flag to allow or disable EIP-191 signature fallback
        mapping(address => bool) whitelistedTokens; // Allowed tokens for swap operations
        mapping(address => address) priceFeeds; // Chainlink price feeds for tokens
        mapping(bytes32 => uint24) customPoolFees; // Optional custom pool fee per token pair
        mapping(address => uint256) customSlippage; // Custom slippage setting per token
        mapping(address => bool) stableTokens; // Markers for stablecoins
    }

    /// @notice Internal storage reference for the ChatterPayState struct
    ChatterPayState private s_state;

    /// @notice Storage slot for locating ChatterPay state in upgradeable proxy
    bytes32 internal constant CHATTERPAY_STATE_POSITION = bytes32(uint256(keccak256("chatterpay.proxy.state")) - 1);

    /// @notice Storage slot for the implementation address in proxy pattern
    bytes32 internal constant IMPLEMENTATION_SLOT = bytes32(uint256(keccak256("chatterpay.proxy.implementation")) - 1);

    /// @notice Public version identifier for upgrades
    string public constant VERSION = "2.0.1";

    /**
     * @notice Signature validation failed return code for ERC-4337 simulations.
     * @dev Used to signal a bad signature without reverting in simulation.
     */
    uint256 constant SIG_VALIDATION_FAILED = 1;

    /**
     * @notice Signature validation success return code for ERC-4337 simulations.
     * @dev Used to signal a valid signature during simulation.
     */
    uint256 constant SIG_VALIDATION_SUCCESS = 0;

    /// @notice Precision constant used for price feed normalization (e.g., 8 decimals)
    uint256 public constant PRICE_FEED_PRECISION = 8;

    /// @notice EIP-712 type hash for the UserOperation struct used in signature validation
    bytes32 private constant USER_OP_TYPEHASH = keccak256(
        "UserOperation(address sender,uint256 nonce,bytes initCode,bytes callData,uint256 callGasLimit,uint256 verificationGasLimit,uint256 preVerificationGas,uint256 maxFeePerGas,uint256 maxPriorityFeePerGas,bytes paymasterAndData,uint256 chainId)"
    );

    /*//////////////////////////////////////////////////////////////
    // EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokenApproved(address indexed token, address indexed spender, uint256 amount);
    event SwapExecuted(
        address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, address recipient
    );
    event FeeUpdated(uint256 indexed oldFee, uint256 indexed newFee);
    event FeeTransferred(address indexed from, address indexed to, address indexed token, uint256 amount);
    event TokenWhitelisted(address indexed token, bool indexed status);
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);
    event CustomPoolFeeSet(address indexed tokenA, address indexed tokenB, uint24 fee);
    event CustomSlippageSet(address indexed token, uint256 slippageBps);
    event TokenTransferCalled(address indexed from, address indexed to, address indexed token, uint256 amount);
    event TokenTransferred(address indexed from, address indexed to, address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////
    MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Restricts access to the ChatterPay admin (factory owner).
     * @dev Reverts with ChatterPay__NotFromChatterPayAdmin if caller is not the factory owner.
     */
    modifier onlyChatterPayAdmin() {
        if (msg.sender != _getChatterPayState().factory.owner()) {
            revert ChatterPay__NotFromChatterPayAdmin();
        }
        _;
    }

    /**
     * @notice Allows access only from the EntryPoint contract or the wallet owner.
     * @dev Reverts with ChatterPay__NotFromEntryPointOrOwner if caller is neither EntryPoint nor owner.
     */
    modifier requireFromEntryPointOrOwner() {
        if (msg.sender != address(_getChatterPayState().entryPoint) && msg.sender != owner()) {
            revert ChatterPay__NotFromEntryPointOrOwner();
        }
        _;
    }

    /**
     * @notice Allows access only from the EntryPoint contract.
     * @dev Reverts with ChatterPay__NotFromEntryPoint if caller is not the EntryPoint.
     */
    modifier requireFromEntryPoint() {
        if (msg.sender != address(_getChatterPayState().entryPoint)) {
            revert ChatterPay__NotFromEntryPoint();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
    // INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor for the implementation contract.
     * @dev Disables initializers to prevent misuse of the implementation logic directly.
     * This is a standard safety pattern for upgradeable contracts.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
        __EIP712_init("ChatterPay", VERSION);

        _getChatterPayState().entryPoint = IEntryPoint(_entryPoint);
        _getChatterPayState().paymaster = _paymaster;
        _getChatterPayState().swapRouter = ISwapRouter(_router);
        _getChatterPayState().factory = IChatterPayWalletFactory(_factory);
        _getChatterPayState().feeInCents = 8; // Default fee in cents

        _getChatterPayState().uniswapPoolFeeLow = 500; // 0.05%
        _getChatterPayState().uniswapPoolFeeMedium = 3000; // 0.3%
        _getChatterPayState().uniswapPoolFeeHigh = 10000; // 1%
        _getChatterPayState().slippageMaxBps = 5000;

        _getChatterPayState().maxDeadline = 3 minutes;
        _getChatterPayState().maxFeeInCents = 1000; // $10.00
        _getChatterPayState().priceFreshnessThreshold = 100 hours;
        _getChatterPayState().priceFeedPrecision = 8;
        _getChatterPayState().allowEIP191Fallback = true;

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
            _getChatterPayState().whitelistedTokens[token] = true;
            _getChatterPayState().priceFeeds[token] = priceFeed;
            _getChatterPayState().stableTokens[token] = tokenStableFlag;

            emit PriceFeedUpdated(token, priceFeed);
            emit TokenWhitelisted(token, true);
        }
    }

    /*//////////////////////////////////////////////////////////////
    // GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the address of the current implementation.
     * @return impl The implementation contract address.
     */
    function implementation() public view returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }

    /**
     * @notice Retrieves the current storage pointer to ChatterPayState.
     * @return state A storage reference to the ChatterPayState struct.
     */
    function _getChatterPayState() internal pure returns (ChatterPayState storage state) {
        bytes32 position = CHATTERPAY_STATE_POSITION;
        assembly {
            state.slot := position
        }
    }

    /**
     * @notice Returns the owner of the ChatterPay wallet.
     * @return The address of the ChatterPay wallet owner.
     */
    function getChatterPayOwner() public view returns (address) {
        return _getChatterPayState().factory.owner();
    }

    /**
     * @notice Returns the fee configured for token operations.
     * @return The fee in cents.
     */
    function getFeeInCents() public view returns (uint256) {
        return _getChatterPayState().feeInCents;
    }

    /**
     * @notice Checks if a token is whitelisted for swaps.
     * @param token The address of the token.
     * @return True if the token is whitelisted, false otherwise.
     */
    function isTokenWhitelisted(address token) public view returns (bool) {
        return _getChatterPayState().whitelistedTokens[token];
    }

    /**
     * @notice Returns the price feed address for a given token.
     * @param token The address of the token.
     * @return The Chainlink price feed address.
     */
    function getPriceFeed(address token) public view returns (address) {
        return _getChatterPayState().priceFeeds[token];
    }

    /**
     * @notice Returns a custom Uniswap pool fee set for a specific token pair.
     * @param pairHash The hash identifying the token pair.
     * @return The custom pool fee in basis points.
     */
    function getCustomPoolFee(bytes32 pairHash) public view returns (uint24) {
        return _getChatterPayState().customPoolFees[pairHash];
    }

    /**
     * @notice Returns the custom slippage value set for a given token.
     * @param token The token address.
     * @return The slippage value in basis points.
     */
    function getCustomSlippage(address token) public view returns (uint256) {
        return _getChatterPayState().customSlippage[token];
    }

    /**
     * @notice Returns the current Uniswap router configured.
     * @return The ISwapRouter instance.
     */
    function getSwapRouter() public view returns (ISwapRouter) {
        return _getChatterPayState().swapRouter;
    }

    /**
     * @notice Returns the address of the EntryPoint used by this wallet.
     * @return The EntryPoint contract address.
     */
    function getEntryPoint() external view returns (address) {
        return address(_getChatterPayState().entryPoint);
    }

    /**
     * @notice Checks if a token is marked as stable.
     * @param token The address of the token.
     * @return True if the token is stable, false otherwise.
     */
    function isStableToken(address token) public view returns (bool) {
        return _getChatterPayState().stableTokens[token];
    }

    /**
     * @notice Returns the configured pool fees (low, medium, high).
     * @return low The low tier fee.
     * @return medium The medium tier fee.
     * @return high The high tier fee.
     */
    function getPoolFees() external view returns (uint24 low, uint24 medium, uint24 high) {
        return (
            _getChatterPayState().uniswapPoolFeeLow,
            _getChatterPayState().uniswapPoolFeeMedium,
            _getChatterPayState().uniswapPoolFeeHigh
        );
    }

    /**
     * @notice Returns the maximum allowed slippage in basis points.
     * @return The slippage value.
     */
    function getSlippageMaxBps() external view returns (uint256) {
        return _getChatterPayState().slippageMaxBps;
    }

    /**
     * @notice Returns the maximum allowed deadline for a swap.
     * @return The deadline in seconds.
     */
    function getMaxDeadline() external view returns (uint256) {
        return _getChatterPayState().maxDeadline;
    }

    /**
     * @notice Returns the maximum fee allowed in cents.
     * @return The maximum fee.
     */
    function getMaxFeeInCents() external view returns (uint256) {
        return _getChatterPayState().maxFeeInCents;
    }

    /**
     * @notice Returns the price freshness threshold used to validate Chainlink feeds.
     * @return The threshold in seconds.
     */
    function getPriceFreshnessThreshold() external view returns (uint256) {
        return _getChatterPayState().priceFreshnessThreshold;
    }

    /**
     * @notice Returns the precision factor used when calculating prices.
     * @return The precision scalar.
     */
    function getPriceFeedPrecision() external view returns (uint256) {
        return _getChatterPayState().priceFeedPrecision;
    }

    /**
     * @notice Returns whether EIP-191 fallback is allowed for signature validation.
     * @return True if EIP-191 fallback is enabled, false otherwise.
     */
    function isEIP191FallbackAllowed() external view returns (bool) {
        return _getChatterPayState().allowEIP191Fallback;
    }

    /**
     * @notice Returns the fee amount in token units for a given token,
     *         using the global feeInCents value from contract state.
     * @param token The token address
     * @return The calculated fee in token units
     * @dev Reverts if the token is not whitelisted
     */
    function getTokenFee(address token) external view returns (uint256) {
        if (!_getChatterPayState().whitelistedTokens[token]) {
            revert ChatterPay__TokenNotWhitelisted();
        }
        return _calculateFee(token, _getChatterPayState().feeInCents);
    }

    /*//////////////////////////////////////////////////////////////
    // MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Approves a token to be spent by the Uniswap Router
     * @param token Token to approve
     * @param amount Amount to approve
     */
    function approveToken(address token, uint256 amount) external requireFromEntryPointOrOwner nonReentrant {
        if (amount == 0) revert ChatterPay__ZeroAmount();
        if (!_getChatterPayState().whitelistedTokens[token]) {
            revert ChatterPay__TokenNotWhitelisted();
        }

        IERC20(token).safeIncreaseAllowance(address(_getChatterPayState().swapRouter), amount);
        emit TokenApproved(token, address(_getChatterPayState().swapRouter), amount);
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
        if (!_getChatterPayState().whitelistedTokens[token]) revert ChatterPay__TokenNotWhitelisted();

        uint256 balance = IERC20(token).balanceOf(address((this)));
        if (balance < amount) revert ChatterPay__InsufficientBalance();

        uint256 fee = _calculateFee(token, _getChatterPayState().feeInCents);
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
            if (!_getChatterPayState().whitelistedTokens[token]) revert ChatterPay__TokenNotWhitelisted();

            // Check balance
            if (IERC20(token).balanceOf(address(this)) < amount) {
                revert ChatterPay__InsufficientBalance();
            }

            // Calculate fee
            uint256 fee = _calculateFee(token, _getChatterPayState().feeInCents);
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
        if (!_getChatterPayState().whitelistedTokens[tokenIn] || !_getChatterPayState().whitelistedTokens[tokenOut]) {
            revert ChatterPay__TokenNotWhitelisted();
        }

        // Check balance
        if (IERC20(tokenIn).balanceOf(address(this)) < amountIn) {
            revert ChatterPay__InsufficientBalance();
        }

        // Calculate fee
        uint256 fee = _calculateFee(tokenIn, _getChatterPayState().feeInCents);
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

        try _getChatterPayState().swapRouter.exactInputSingle(params) returns (uint256 amountOut) {
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
    // ADMIN FUNCTIONS
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
        if (_newFeeInCents > _getChatterPayState().maxFeeInCents) {
            revert ChatterPay__ExceedsMaxFee();
        }
        uint256 oldFee = _getChatterPayState().feeInCents;
        _getChatterPayState().feeInCents = _newFeeInCents;
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

        _getChatterPayState().whitelistedTokens[token] = status;
        if (status) {
            _getChatterPayState().priceFeeds[token] = priceFeed;
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

        delete _getChatterPayState().whitelistedTokens[token];
        delete _getChatterPayState().priceFeeds[token];

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
        if (_getChatterPayState().stableTokens[token]) revert ChatterPay__AlreadyStableToken();
        _getChatterPayState().stableTokens[token] = true;
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
        if (!_getChatterPayState().stableTokens[token]) revert ChatterPay__NotStableToken();
        delete _getChatterPayState().stableTokens[token];
    }

    /**
     * @notice Sets a custom pool fee for a specific token pair
     * @param tokenA First token in pair
     * @param tokenB Second token in pair
     * @param fee Custom fee to use
     */
    function setCustomPoolFee(address tokenA, address tokenB, uint24 fee) external onlyOwner {
        if (fee > _getChatterPayState().uniswapPoolFeeHigh) revert ChatterPay__InvalidPoolFee();

        bytes32 pairHash = _getPairHash(tokenA, tokenB);
        _getChatterPayState().customPoolFees[pairHash] = fee;
        emit CustomPoolFeeSet(tokenA, tokenB, fee);
    }

    /**
     * @notice Sets custom slippage for a token
     * @param token Token address
     * @param slippageBps Slippage in basis points
     */
    function setCustomSlippage(address token, uint256 slippageBps) external onlyOwner {
        if (slippageBps > _getChatterPayState().slippageMaxBps) revert ChatterPay__InvalidSlippage();
        _getChatterPayState().customSlippage[token] = slippageBps;
        emit CustomSlippageSet(token, slippageBps);
    }

    /**
     * @notice Updates the Uniswap pool fee tiers used for swaps.
     * @dev Only callable by the contract owner.
     * @param low Pool fee for stable-to-stable token swaps.
     * @param medium Pool fee for regular token swaps.
     * @param high Pool fee reserved for high-volatility pairs.
     */
    function updateUniswapPoolFees(uint24 low, uint24 medium, uint24 high) external onlyOwner {
        _getChatterPayState().uniswapPoolFeeLow = low;
        _getChatterPayState().uniswapPoolFeeMedium = medium;
        _getChatterPayState().uniswapPoolFeeHigh = high;
    }

    /**
     * @notice Updates the maximum allowed slippage for swaps.
     * @dev Only callable by the contract owner.
     * @param slippageMaxBps New slippage limit in basis points.
     */
    function updateSlippageMaxBps(uint256 slippageMaxBps) external onlyOwner {
        _getChatterPayState().slippageMaxBps = slippageMaxBps;
    }

    /**
     * @notice Updates the configuration for Chainlink price feeds.
     * @dev Only callable by the contract owner.
     * @param freshness New freshness threshold in seconds.
     * @param precision New precision factor for price normalization.
     */
    function updatePriceConfig(uint256 freshness, uint256 precision) external onlyOwner {
        _getChatterPayState().priceFreshnessThreshold = freshness;
        _getChatterPayState().priceFeedPrecision = precision;
    }

    /**
     * @notice Updates swap operation limits.
     * @dev Only callable by the contract owner.
     * @param deadline New maximum deadline in seconds for swap execution.
     * @param maxFeeCents New maximum fee in cents allowed for a transaction.
     */
    function updateLimits(uint256 deadline, uint256 maxFeeCents) external onlyOwner {
        _getChatterPayState().maxDeadline = deadline;
        _getChatterPayState().maxFeeInCents = maxFeeCents;
    }

    /**
     * @notice Enables or disables the fallback to EIP-191 for signature validation.
     * @dev Only callable by the contract owner.
     * @param allowed Pass true to enable fallback to EIP-191, or false to disable it.
     */
    function setEIP191FallbackAllowed(bool allowed) external onlyOwner {
        _getChatterPayState().allowEIP191Fallback = allowed;
    }

    /*//////////////////////////////////////////////////////////////
    // INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Verify whether a token is a stablecoin
     * @param token Token address to check
     * @return bool True if token is a stablecoin
     */
    function _isStableToken(address token) internal view returns (bool) {
        if (token == address(0)) revert ChatterPay__ZeroAddress();
        return _getChatterPayState().stableTokens[token];
    }

    /**
     * @notice Retrieves the latest token price from the Chainlink oracle.
     * @dev Verifies that the price is positive, fresh (not stale), and comes from a completed round.
     *      Reverts if the price data is invalid, stale, or incomplete.
     * @param token The address of the token to fetch the price for.
     * @return The latest token price with 8 decimals of precision.
     */
    function _getTokenPrice(address token) internal view returns (uint256) {
        address priceFeedAddr = _getChatterPayState().priceFeeds[token];
        if (priceFeedAddr == address(0)) revert ChatterPay__PriceFeedNotSet();

        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddr);

        (uint80 roundId, int256 price,, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

        if (price <= 0) revert ChatterPay__InvalidPrice(uint256(price));
        if (answeredInRound < roundId) revert ChatterPay__InvalidPriceRound(answeredInRound, roundId);

        if (block.timestamp - updatedAt > _getChatterPayState().priceFreshnessThreshold) {
            revert ChatterPay__InvalidPriceFreshnessThreshold(
                block.timestamp, updatedAt, _getChatterPayState().priceFreshnessThreshold
            );
        }

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
        uint24 customFee = _getChatterPayState().customPoolFees[pairHash];
        if (customFee != 0) return customFee;

        if (_isStableToken(tokenIn) && _isStableToken(tokenOut)) {
            return _getChatterPayState().uniswapPoolFeeLow;
        }
        return _getChatterPayState().uniswapPoolFeeMedium;
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
     * @dev Transfers fee to chatterPay owner
     * @param token Token address to transfer
     * @param amount Amount to transfer
     */
    function _transferFee(address token, uint256 amount) internal {
        address chatterPayOwner = getChatterPayOwner();
        IERC20(token).safeTransfer(chatterPayOwner, amount);
        emit FeeTransferred(address(this), chatterPayOwner, token, amount);
    }

    /**
     * @dev Calculates fee in token units
     * @param token Token address to calculate fee for
     * @param feeInCents Fee amount in cents
     * @return uint256 Fee amount in token units
     */
    function _calculateFee(address token, uint256 feeInCents) internal view returns (uint256) {
        uint256 tokenPrice = _getTokenPrice(token); // Price has 8 decimals from Chainlink
        if (tokenPrice == 0) revert ChatterPay__InvalidPrice(tokenPrice);

        uint256 tokenDecimals = IERC20Extended(token).decimals();
        if (tokenDecimals > 77) revert ChatterPay__InvalidDecimals();

        if (feeInCents >= type(uint256).max / 1e8 / 1e18) revert ChatterPay__InvalidFeeOverflow();

        uint256 numerator = feeInCents * (10 ** tokenDecimals) * 1e8;
        uint256 denominator = tokenPrice * 100;

        return numerator / denominator;
    }

    /**
     * @notice Validates the signature of a UserOperation according to ERC-4337.
     * @dev Tries to recover the signer using EIP-712 (typed data hash). If it fails and
     *      `allowEIP191Fallback` is true, it falls back to EIP-191 recovery using `eth_sign`.
     *      - EIP-712 is preferred as it provides strong domain separation (chainId, contract address).
     *      - EIP-191 is a legacy mechanism and should only be used for backward compatibility.
     *
     * @param userOp The UserOperation to validate.
     * @param userOpHash The userOp hash provided by EntryPoint (used only in fallback).
     * @return validationData 0 if signature is valid, 1 if invalid.
     */
    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256 validationData)
    {
        address signer;

        // Preferred path: EIP-712
        bytes32 digest = _hashUserOp(userOp);
        signer = ECDSA.recover(digest, userOp.signature);
        if (signer == owner()) {
            return SIG_VALIDATION_SUCCESS;
        }

        // Optional fallback: EIP-191
        if (_getChatterPayState().allowEIP191Fallback) {
            bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
            signer = ECDSA.recover(ethSignedMessageHash, userOp.signature);
            // owner: Returns the user's wallet (executed via the EntryPoint!).
            // If requested from the command line, it will return the owner who deployed the
            // contract (backend signer).
            // signer: The person who signed the userOperation, which must be the wallet owner.
            if (signer == owner()) {
                return SIG_VALIDATION_SUCCESS;
            }
        }

        return SIG_VALIDATION_FAILED;
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
     * @notice Computes the EIP-712 digest for a UserOperation
     * @param userOp The UserOperation struct
     * @return The EIP-712 typed data hash to be signed
     */
    function _hashUserOp(UserOperation calldata userOp) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    USER_OP_TYPEHASH,
                    userOp.sender,
                    userOp.nonce,
                    keccak256(userOp.initCode),
                    keccak256(userOp.callData),
                    userOp.callGasLimit,
                    userOp.verificationGasLimit,
                    userOp.preVerificationGas,
                    userOp.maxFeePerGas,
                    userOp.maxPriorityFeePerGas,
                    keccak256(userOp.paymasterAndData),
                    block.chainid
                )
            )
        );
    }

    /**
     * @dev Function that authorizes an upgrade to a new implementation
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyChatterPayAdmin {}

    /**
     * @notice Allows the contract to receive native ETH transfers.
     * @dev This function is called when ETH is sent without calldata.
     */
    receive() external payable {}
}
