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
    uint24 public constant POOL_FEE_LOW = 500;      // 0.05%
    uint24 public constant POOL_FEE_MEDIUM = 3000;  // 0.3%
    uint24 public constant POOL_FEE_HIGH = 10000;   // 1%
    
    // Slippage constants (in basis points, 1 bp = 0.01%)
    uint256 public constant SLIPPAGE_STABLES = 50;   // 0.5%
    uint256 public constant SLIPPAGE_ETH = 100;      // 1%
    uint256 public constant SLIPPAGE_BTC = 150;      // 1.5%
    
    uint256 public constant MAX_DEADLINE = 3 minutes;
    
    event TokenApproved(address indexed token, address indexed spender, uint256 amount);
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    );

    modifier onlyFactoryOwner() {
        if(msg.sender != factory.owner()) {
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
    * @dev Verifica si un token es una stablecoin
    */
    function _isStableToken(address token) internal view returns (bool) {
        string memory symbol = IERC20Extended(token).symbol();
        bytes32 symbolHash = keccak256(abi.encodePacked(symbol));
        return (
            symbolHash == keccak256(abi.encodePacked("USDT")) ||
            symbolHash == keccak256(abi.encodePacked("USDC")) ||
            symbolHash == keccak256(abi.encodePacked("DAI"))
        );
    }

    /**
     * @notice Aprueba un token para ser gastado por el router de Uniswap
     * @param token Token a aprobar
     * @param amount Cantidad a aprobar
     */
    function approveToken(
        address token,
        uint256 amount
    ) external requireFromEntryPointOrOwner nonReentrant {
        if (amount == 0) revert ChatterPay__ZeroAmount();
        if (!s_whitelistedTokens[token]) revert ChatterPay__TokenNotWhitelisted();

        IERC20(token).safeIncreaseAllowance(address(swapRouter), amount);
        emit TokenApproved(token, address(swapRouter), amount);
    }

    /**
     * @notice Ejecuta un swap a través de Uniswap V3
     * @param tokenIn Token de entrada
     * @param tokenOut Token de salida
     * @param amountIn Cantidad de tokens de entrada
     * @param amountOutMin Cantidad mínima de tokens de salida esperada
     * @param recipient Dirección que recibirá los tokens
     */
    function executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient
    ) external requireFromEntryPointOrOwner nonReentrant {
        // Validaciones
        if (amountIn == 0) revert ChatterPay__ZeroAmount();
        if (!s_whitelistedTokens[tokenIn]) revert ChatterPay__TokenNotWhitelisted();
        
        // Verificar y cobrar fee
        uint256 fee = _calculateFee(tokenIn, s_feeInCents);
        _transferFee(tokenIn, fee);

        // Calcular deadline
        uint256 deadline = block.timestamp + MAX_DEADLINE;
        
        // Verificar slippage basado en el tipo de token
        _validateSlippage(tokenIn, tokenOut, amountIn, amountOutMin);

        // Transferir tokens al contrato
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Parámetros del swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: _getPoolFee(tokenIn, tokenOut),
                recipient: recipient,
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            });

        // Ejecutar swap
        try swapRouter.exactInputSingle(params) returns (uint256 amountOut) {
            emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, recipient);
        } catch {
            revert ChatterPay__SwapFailed();
        }
    }

    /**
     * @notice Permite al owner del factory ejecutar llamadas arbitrarias
     * @dev Solo para uso en emergencias o casos especiales
     */
    function execute(
        address dest,
        uint256 value,
        bytes calldata func
    ) external onlyFactoryOwner nonReentrant {
        (bool success, bytes memory result) = dest.call{value: value}(func);
        if (!success) revert ChatterPay__ExecuteCallFailed(result);
    }

    // FUNCIONES INTERNAS

    /**
     * @dev Valida el slippage basado en el tipo de token
     */
    function _validateSlippage(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal view {
        uint256 expectedOut = _getExpectedOutput(tokenIn, tokenOut, amountIn);
        uint256 maxSlippage = _getMaxSlippage(tokenIn, tokenOut);
        uint256 minAcceptable = (expectedOut * (10000 - maxSlippage)) / 10000;
        
        if (amountOutMin < minAcceptable) revert ChatterPay__InvalidSlippage();
    }

    /**
     * @dev Determina el fee del pool basado en los tokens
     */
    function _getPoolFee(address tokenIn, address tokenOut) internal pure returns (uint24) {
        // Si ambos son stables, usar fee bajo
        if (_isStableToken(tokenIn) && _isStableToken(tokenOut)) {
            return POOL_FEE_LOW;
        }
        // Para otros pares, usar fee medio
        return POOL_FEE_MEDIUM;
    }

    /**
     * @dev Obtiene el slippage máximo permitido para un par de tokens
     */
    function _getMaxSlippage(address tokenIn, address tokenOut) internal pure returns (uint256) {
        if (_isStableToken(tokenIn) && _isStableToken(tokenOut)) {
            return SLIPPAGE_STABLES;
        }
        if (_isBTCToken(tokenIn) || _isBTCToken(tokenOut)) {
            return SLIPPAGE_BTC;
        }
        return SLIPPAGE_ETH;
    }

    /**
     * @dev Verifica si un token es BTC o similar
     */
    function _isBTCToken(address token) internal pure returns (bool) {
        string memory symbol = IERC20Extended(token).symbol();
        bytes32 symbolHash = keccak256(abi.encodePacked(symbol));
        return (
            symbolHash == keccak256(abi.encodePacked("WBTC")) ||
            symbolHash == keccak256(abi.encodePacked("renBTC"))
        );
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
        if (_newFeeInCents > MAX_FEE_IN_CENTS) revert ChatterPay__ExceedsMaxFee();
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
            if (decimals != PRICE_FEED_PRECISION) revert ChatterPay__InvalidPriceFeed();
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
        address priceFeedAddress = s_priceFeeds[token];
        if (priceFeedAddress == address(0)) revert ChatterPay__PriceFeedNotSet();

        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        if (updatedAt == 0 || answeredInRound < roundId) revert ChatterPay__InvalidPrice();
        if (block.timestamp - updatedAt > PRICE_FRESHNESS_THRESHOLD) revert ChatterPay__StalePrice();
        if (price <= 0) revert ChatterPay__InvalidPrice();

        return uint256(price);
    }

    /**
     * @dev Calculates expected output for a swap
     */
    function _getExpectedOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (uint256) {
        uint256 priceIn = _getTokenPrice(tokenIn);
        uint256 priceOut = _getTokenPrice(tokenOut);
        
        return (amountIn * priceIn) / priceOut;
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
    function _calculateFee(
        address token,
        uint256 cents
    ) internal view returns (uint256) {
        uint256 price = _getTokenPrice(token);
        uint256 decimals = IERC20Extended(token).decimals();
        
        // Convert cents to full units with token decimals
        uint256 fee = (cents * 10 ** (decimals - 2)) / price;
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