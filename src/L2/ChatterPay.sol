// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IAccount, UserOperation} from "lib/entry-point-v6/interfaces/IAccount.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IEntryPoint} from "lib/entry-point-v6/interfaces/IEntryPoint.sol";
import {ITokensPriceFeeds} from "../Ethereum/TokensPriceFeeds.sol";

error ChatterPay__NotFromEntryPoint();
error ChatterPay__NotFromEntryPointOrOwner();
error ChatterPay__ExecuteCallFailed(bytes);
error ChatterPay__UnsopportedTokenDecimals();
error ChatterPay__API3Failed();
error ChatterPay__UnsopportedToken();
error ChatterPay__InvalidAmountOfTokens();
error ChatterPay__InvalidTokenReceiver();
error ChatterPay__NoTokenBalance(address);
error ChatterPay__BalanceTxFailed();

interface IERC20 {
    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);
}

contract ChatterPay is IAccount, UUPSUpgradeable, OwnableUpgradeable {
    IEntryPoint private s_entryPoint;
    address public s_paymaster;
    address public s_api3PriceFeed;
    string[1] public s_supportedStableTokens;
    string[2] public s_supportedNotStableTokens;

    uint256 public constant FEE_IN_CENTS = 50; // 50 cents

    event Execution(
        address indexed wallet,
        address indexed dest,
        uint256 indexed value,
        bytes functionData
    );
    event TokenTransfer(
        address indexed wallet,
        address indexed dest,
        uint256 indexed fee,
        bytes functionData
    );
    event EntryPointSet(address indexed entryPoint);
    event WithdrawBalance(address[] indexed, address indexed to);

    modifier requireFromEntryPoint() {
        if (msg.sender != address(s_entryPoint)) {
            revert ChatterPay__NotFromEntryPoint();
        }
        _;
    }

    modifier requireFromEntryPointOrOwner() {
        if (msg.sender != address(s_entryPoint) && msg.sender != owner()) {
            revert ChatterPay__NotFromEntryPointOrOwner();
        }
        _;
    }

    /**
     * @notice Initializes the ChatterPay contract.
     * @dev Sets up the owner, entry point, and paymaster, and initializes supported tokens.
     * @param _entryPoint The address of the entry point contract.
     * @param _newOwner The address of the contract owner.
     * @param _paymaster The address of the paymaster contract.
     */
    function initialize(
        address _entryPoint,
        address _newOwner,
        address _paymaster
    ) public initializer {
        __Ownable_init(_newOwner);
        __UUPSUpgradeable_init();
        s_entryPoint = IEntryPoint(_entryPoint);
        s_paymaster = _paymaster;
        s_supportedStableTokens = ["USDT"];
        s_supportedNotStableTokens = ["WETH", "WBTC"];
    }

    receive() external payable {}

    /**
     * @notice Executes a generic transaction.
     * @dev Allows the contract to call an external contract with the provided data.
     * @param dest The destination address of the transaction.
     * @param value The amount of ETH to send with the transaction.
     * @param functionData The calldata for the function to be executed.
     * @custom:events Emits an `Execution` event on success.
     * @custom:reverts ChatterPay__ExecuteCallFailed if the transaction fails.
     */
    function execute(
        address dest,
        uint256 value,
        bytes calldata functionData
    ) external requireFromEntryPointOrOwner {
        (bool success, bytes memory result) = dest.call{value: value}(
            functionData
        );
        if (!success) {
            revert ChatterPay__ExecuteCallFailed(result);
        }
        emit Execution(address(this), dest, value, functionData);
    }

    /**
     * @notice Executes a token transfer with an additional fee.
     * @dev Transfers the token and pays the specified fee to the paymaster.
     * @param dest The destination address of the token transfer.
     * @param fee The fee in tokens to be paid to the paymaster.
     * @param functionData The calldata for the token transfer function.
     * @custom:events Emits a `TokenTransfer` event on success.
     * @custom:reverts ChatterPay__ExecuteCallFailed if the fee or transfer fails.
     */
    function executeTokenTransfer(
        address dest,
        uint256 fee,
        bytes calldata functionData
    ) external requireFromEntryPointOrOwner {
        if (fee != _calculateFee(dest, FEE_IN_CENTS))
            revert ChatterPay__ExecuteCallFailed("Incorrect fee");

        (bool feeTxSuccess, bytes memory feeTxResult) = dest.call(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                s_paymaster,
                fee
            )
        );
        if (!feeTxSuccess) {
            revert ChatterPay__ExecuteCallFailed(feeTxResult);
        }

        (bool executeSuccess, bytes memory executeResult) = dest.call(
            functionData
        );
        if (!executeSuccess) {
            revert ChatterPay__ExecuteCallFailed(executeResult);
        }
        emit TokenTransfer(address(this), dest, fee, functionData);
    }

    /**
     * @notice Validates a user operation.
     * @dev Validates the signature and ensures sufficient funds for the operation.
     * @param userOp The user operation being validated.
     * @param userOpHash The hash of the user operation.
     * @param missingAccountFunds The amount of funds required to cover the operation.
     * @return validationData A value indicating the validation status of the user operation.
     */
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external requireFromEntryPoint returns (uint256 validationData) {
        validationData = _validateSignature(userOp, userOpHash);
        // _validateNonce()
        _payPrefund(missingAccountFunds);
    }

    /**
     * @notice Withdraws token and ETH balances from the contract to a specified address.
     * @dev Allows the contract owner to withdraw all balances of specified tokens and ETH.
     * @param tokenAddresses The addresses of the tokens to withdraw.
     * @param to The address to send the balances to.
     * @return A boolean indicating whether the withdrawal was successful.
     * @custom:events Emits a `WithdrawBalance` event on success.
     * @custom:reverts ChatterPay__InvalidAmountOfTokens if the number of tokens exceeds the supported count.
     * @custom:reverts ChatterPay__InvalidTokenReceiver if the recipient address is invalid.
     * @custom:reverts ChatterPay__NoTokenBalance if a token has no balance.
     * @custom:reverts ChatterPay__BalanceTxFailed if a token transfer or ETH transfer fails.
     */
    function withdrawBalance(
        address[] memory tokenAddresses,
        address to
    ) external onlyOwner returns (bool) {
        if (
            tokenAddresses.length >
            s_supportedNotStableTokens.length + s_supportedStableTokens.length
        ) {
            revert ChatterPay__InvalidAmountOfTokens();
        }
        if (to == address(0) || to.code.length > 0)
            revert ChatterPay__InvalidTokenReceiver();

        for (uint256 i; i < tokenAddresses.length; i++) {
            if (tokenAddresses[i] == address(0)) {
                (bool success, ) = payable(to).call{
                    value: address(this).balance
                }("");
                if (!success) revert ChatterPay__BalanceTxFailed();
            } else {
                IERC20 token = IERC20(tokenAddresses[i]);
                uint256 balance = token.balanceOf(address(this));
                if (balance == 0)
                    revert ChatterPay__NoTokenBalance(tokenAddresses[i]);
                bool success = token.transfer(to, balance);
                if (!success) revert ChatterPay__BalanceTxFailed();
            }
        }

        emit WithdrawBalance(tokenAddresses, to);
        return true;
    }

    /**
     * @notice Sets the entry point address.
     * @dev Only callable by the contract owner.
     * @param _entryPoint The new entry point address.
     * @custom:events Emits an `EntryPointSet` event on success.
     */
    function setEntryPoint(address _entryPoint) external onlyOwner {
        s_entryPoint = IEntryPoint(_entryPoint);
        emit EntryPointSet(_entryPoint);
    }

    /**
     * @notice Sets the API3 price feed address.
     * @dev Only callable by the contract owner.
     * @param _priceFeed The address of the API3 price feed contract.
     */
    function setPriceFeedAddress(address _priceFeed) public onlyOwner {
        s_api3PriceFeed = _priceFeed;
    }

    /**
     * @notice Validates the signature of a user operation.
     * @dev Recovers the signer from the operation hash and checks if it matches the contract owner.
     * @param userOp The user operation containing the signature.
     * @param userOpHash The hash of the user operation.
     * @return validationData A value indicating whether the signature is valid (0 = valid, 1 = invalid).
     */
    function _validateSignature(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) internal view returns (uint256 validationData) {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            userOpHash
        );
        address signer = ECDSA.recover(ethSignedMessageHash, userOp.signature);
        if (signer != owner()) return 1;
        return 0;
    }

    /**
     * @notice Pays the missing funds required for a user operation.
     * @dev Sends the required funds to the entry point to cover operation costs.
     * @param missingAccountFunds The amount of funds required to cover the operation.
     */
    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds != 0) {
            (bool success, ) = payable(msg.sender).call{
                value: missingAccountFunds,
                gas: type(uint256).max
            }("");
            (success);
        }
    }

    /**
     * @notice Calculates the fee for a transaction in token units.
     * @dev Uses the token's symbol, decimals, and price (if not stable) to compute the fee.
     * @param _token The address of the token for which the fee is calculated.
     * @param _cents The fee amount in cents (USD).
     * @return The calculated fee in token units.
     * @custom:reverts ChatterPay__UnsopportedTokenDecimals if the token decimals are unsupported.
     * @custom:reverts ChatterPay__UnsopportedToken if the token is not supported.
     */
    function _calculateFee(
        address _token,
        uint256 _cents
    ) internal view returns (uint256) {
        string memory symbol = _getTokenSymbol(_token);
        bool isStable = _isStableToken(symbol);
        uint256 decimals = _getTokenDecimals(_token);
        uint256 oraclePrice;
        uint256 fee;
        if (!isStable) {
            oraclePrice = _getAPI3OraclePrice(symbol);
            fee = _calculateFeeNotStable(oraclePrice, _cents);
        } else {
            fee = _calculateFeeStable(decimals, _cents);
        }
        return fee;
    }

    /**
     * @notice Checks whether a token is a stable token.
     * @dev Compares the token symbol with the supported stable tokens list.
     * @param _symbol The symbol of the token to check.
     * @return A boolean indicating whether the token is stable (true = stable).
     * @custom:reverts ChatterPay__UnsopportedToken if the token symbol is not recognized.
     */
    function _isStableToken(
        string memory _symbol
    ) internal view returns (bool) {
        string[1] memory m_supportedStableTokens = s_supportedStableTokens;
        string[2]
            memory m_supportedNotStableTokens = s_supportedNotStableTokens;
        for (uint256 i; i < m_supportedStableTokens.length; i++) {
            if (
                keccak256(abi.encodePacked(_symbol)) ==
                keccak256(abi.encodePacked(m_supportedStableTokens[i]))
            ) {
                return true;
            }
        }
        for (uint256 i; i < m_supportedNotStableTokens.length; i++) {
            if (
                keccak256(abi.encodePacked(_symbol)) ==
                keccak256(abi.encodePacked(m_supportedNotStableTokens[i]))
            ) {
                return false;
            }
        }
        revert ChatterPay__UnsopportedToken();
    }

    /**
     * @notice Calculates the fee for a stable token based on its decimals.
     * @dev Multiplies the fee in cents by a factor determined by the token's decimals.
     * @param _decimals The number of decimals for the stable token.
     * @param _cents The fee amount in cents (USD).
     * @return The calculated fee in token units.
     * @custom:reverts ChatterPay__UnsopportedTokenDecimals if the token decimals are unsupported.
     */
    function _calculateFeeStable(
        uint256 _decimals,
        uint256 _cents
    ) internal pure returns (uint256) {
        uint256 fee;
        if (_decimals == 6) {
            fee = _cents * 1e4;
        } else if (_decimals == 18) {
            fee = _cents * 1e16;
        } else {
            revert ChatterPay__UnsopportedTokenDecimals();
        }
        return fee;
    }

    /**
     * @notice Calculates the fee for a non-stable token using an oracle price.
     * @dev Uses the oracle price to determine the equivalent token fee for the specified cents.
     * @param oraclePrice The price of the token from the oracle in USD (18 decimals).
     * @param cents The fee amount in cents (USD).
     * @return The calculated fee in token units.
     */
    function _calculateFeeNotStable(
        uint256 oraclePrice,
        uint256 cents
    ) internal pure returns (uint256) {
        uint256 dollarsIn18Decimals = (cents * 10 ** 16);
        uint256 fee = (dollarsIn18Decimals * 10 ** 18) / oraclePrice;
        return fee;
    }

    /**
     * @notice Authorizes an upgrade to a new implementation.
     * @dev Only callable by the contract owner.
     * @param newImplementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /**
     * @notice Gets the current entry point address.
     * @return The address of the entry point.
     */
    function getEntryPoint() external view returns (address) {
        return address(s_entryPoint);
    }

    /**
     * @notice Gets the price of a token from the API3 oracle.
     * @dev Queries the API3 oracle for the price of a token.
     * @param _token The symbol of the token to query.
     * @return The price of the token in USD.
     * @custom:reverts ChatterPay__API3Failed if the API3 oracle call fails.
     */
    function _getAPI3OraclePrice(
        string memory _token
    ) internal view returns (uint256) {
        if (s_api3PriceFeed == address(0)) revert ChatterPay__API3Failed();
        // Call API3 Oracle
        uint256 price;
        uint256 ts;
        address token;
        if (
            keccak256(abi.encodePacked(_token)) ==
            keccak256(abi.encodePacked("ETH"))
        ) {
            token = ITokensPriceFeeds(s_api3PriceFeed).ETH_USD_Proxy();
        } else if (
            keccak256(abi.encodePacked(_token)) ==
            keccak256(abi.encodePacked("BTC"))
        ) {
            token = ITokensPriceFeeds(s_api3PriceFeed).BTC_USD_Proxy();
        } else {
            revert ChatterPay__API3Failed();
        }
        (price, ts) = ITokensPriceFeeds(s_api3PriceFeed).readDataFeed(token);
        return price;
    }

    /**
     * @notice Gets the number of decimals for a token.
     * @param token The address of the token.
     * @return The number of decimals for the token.
     */
    function _getTokenDecimals(address token) internal view returns (uint8) {
        return IERC20(token).decimals();
    }

    /**
     * @notice Gets the symbol of a token.
     * @param token The address of the token.
     * @return The symbol of the token.
     */
    function _getTokenSymbol(
        address token
    ) internal view returns (string memory) {
        return IERC20(token).symbol();
    }

    uint256[50] private __gap;
}
