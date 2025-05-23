// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
// IMPORTS
//////////////////////////////////////////////////////////////*/

import "lib/entry-point-v6/interfaces/IPaymaster.sol";
import {IEntryPoint} from "lib/entry-point-v6/interfaces/IEntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/*//////////////////////////////////////////////////////////////
// ERRORS
//////////////////////////////////////////////////////////////*/

error ChatterPayPaymaster__InvalidAddress();
error ChatterPayPaymaster__OnlyOwner();
error ChatterPayPaymaster__OnlyEntryPoint();
error ChatterPayPaymaster__InvalidDataLength();
error ChatterPayPaymaster__InvalidSignature();
error ChatterPayPaymaster__InvalidChainId();
error ChatterPayPaymaster__InvalidVValue();
error ChatterPayPaymaster__SliceOutOfBounds();
error ChatterPayPaymaster__InvalidSignatureLength();
error ChatterPayPaymaster__ExecutionFailed();
error ChatterPayPaymaster__WithdrawFailed();

/**
 * @title ChatterPayPaymaster
 * @author ChatterPay Team
 * @notice A Paymaster contract for managing user operations with signature-based validation
 * @dev Integrates with the EntryPoint contract and validates operations signed by a backend signer
 */
contract ChatterPayPaymaster is IPaymaster {
    /*//////////////////////////////////////////////////////////////
    // CONSTANTS & VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public owner;
    IEntryPoint public entryPoint;
    address private backendSigner;
    uint256 private immutable chainId;
    uint256 private constant SIGNATURE_OFFSET = 20;
    uint256 private constant EXPIRATION_OFFSET = 85;

    /*//////////////////////////////////////////////////////////////
    // MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Ensures that only the contract owner can call the function
     * @dev Reverts if the caller is not the contract owner
     * @custom:error ChatterPayPaymaster__OnlyOwner if the caller is not the owner
     */
    modifier onlyOwner() {
        if (msg.sender != owner) revert ChatterPayPaymaster__OnlyOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
    // INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the ChatterPayPaymaster contract
     * @dev Sets up the owner, entry point address, and backend signer for signature validation
     * @param _entryPoint The address of the EntryPoint contract
     * @param _backendSigner The address authorized to sign paymaster operations
     */
    constructor(address _entryPoint, address _backendSigner) {
        if (_entryPoint == address(0)) revert ChatterPayPaymaster__InvalidAddress();
        if (_backendSigner == address(0)) revert ChatterPayPaymaster__InvalidAddress();
        owner = msg.sender;
        entryPoint = IEntryPoint(_entryPoint);
        backendSigner = _backendSigner;
        chainId = block.chainid;
    }

    /*//////////////////////////////////////////////////////////////
    // GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * Return current paymaster's deposit on the entryPoint.
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
    // MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows the contract to receive ETH payments
     * @dev Implements the receive function to accept ETH transfers
     */
    receive() external payable {}

    /**
     * @notice Validates a UserOperation for the Paymaster
     * @dev Ensures the operation is properly signed and returns validationData with expiration time
     * @param userOp The UserOperation struct containing operation details
     * @return context Additional context for the operation (empty in this case)
     * @return validationData A packed value containing validation status and expiration time
     * @custom:error ChatterPayPaymaster__OnlyEntryPoint if caller is not EntryPoint
     * @custom:error ChatterPayPaymaster__InvalidDataLength if paymasterAndData is malformed
     * @custom:error ChatterPayPaymaster__InvalidSignature if signature is invalid
     * @custom:error ChatterPayPaymaster__InvalidChainId if chain ID doesn't match
     */
    function validatePaymasterUserOp(UserOperation calldata userOp, bytes32, uint256)
        external
        view
        override
        returns (bytes memory context, uint256 validationData)
    {
        _requireFromEntryPoint();

        bytes memory paymasterAndData = userOp.paymasterAndData;

        // Validate data length - expecting 93 bytes (20 + 65 + 8)
        if (paymasterAndData.length != 93) {
            revert ChatterPayPaymaster__InvalidDataLength();
        }

        // Extract components
        bytes memory signature = _slice(paymasterAndData, SIGNATURE_OFFSET, 65);
        uint64 expiration = uint64(bytes8(_slice(paymasterAndData, EXPIRATION_OFFSET, 8)));

        // Validate chain ID - this is allowed in validation
        if (block.chainid != chainId) {
            revert ChatterPayPaymaster__InvalidChainId();
        }

        // Validate signature - MUST match backend's hash calculation exactly
        bytes32 messageHash =
            keccak256(abi.encode(userOp.sender, expiration, uint256(chainId), address(entryPoint), userOp.callData));

        address recoveredAddress = _recoverSigner(messageHash, signature);
        bool sigFailed = recoveredAddress != backendSigner;

        if (sigFailed) revert ChatterPayPaymaster__InvalidSignature();

        // Pack validation data with expiration time instead of checking block.timestamp
        // validAfter = 0 (can be executed immediately)
        // validUntil = expiration timestamp
        return ("", _packValidationData(false, expiration, 0));
    }

    /**
     * @notice Packs validation data according to EIP-4337 format
     * @dev Combines signature validation, validUntil and validAfter into a single uint256
     * @param sigFailed Whether the signature validation failed
     * @param validUntil The timestamp until which the operation is valid
     * @param validAfter The timestamp after which the operation is valid
     * @return A packed uint256 containing all validation data
     */
    function _packValidationData(bool sigFailed, uint256 validUntil, uint256 validAfter)
        internal
        pure
        returns (uint256)
    {
        return (sigFailed ? 1 : 0) | (validUntil << 160) | (validAfter << 192);
    }

    /**
     * @notice Implements the postOp function required by IPaymaster.
     * @dev This function is marked as view since it only verifies that the caller is the EntryPoint.
     */
    function postOp(
        PostOpMode, // Unused parameter
        bytes calldata, // Unused parameter
        uint256 // Unused parameter
    ) external view override {
        _requireFromEntryPoint();
    }

    /*//////////////////////////////////////////////////////////////
    // ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * Add stake for this paymaster.
     * This method can also carry eth value to add to the current stake.
     * @param unstakeDelaySec - The unstake delay for this paymaster. Can only be increased.
     */
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{value: msg.value}(unstakeDelaySec);
    }

    /**
     * Unlock the stake, in order to withdraw it.
     * The paymaster can't serve requests once unlocked, until it calls addStake again
     */
    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
    }

    /**
     * Withdraw the entire paymaster's stake.
     * stake must be unlocked first (and then wait for the unstakeDelay to be over)
     * @param withdrawAddress - The address to send withdrawn value.
     */
    function withdrawStake(address payable withdrawAddress) external onlyOwner {
        entryPoint.withdrawStake(withdrawAddress);
    }

    /**
     * withdraw from the deposit.
     * @param withdrawAddress the address to send withdrawn value.
     * @param withdrawAmount the amount to withdraw.
     */
    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external onlyOwner {
        entryPoint.withdrawTo(withdrawAddress, withdrawAmount);
    }

    /**
     * @notice Executes a low-level call to a specified address
     * @dev Only callable by the contract owner
     * @param dest The address to call
     * @param value The ETH value to send with the call
     * @param data The calldata for the function to execute
     * @custom:error ChatterPayPaymaster__OnlyOwner if caller is not owner
     * @custom:error ChatterPayPaymaster__ExecutionFailed if the call fails
     */
    function execute(address dest, uint256 value, bytes calldata data) external onlyOwner {
        (bool success,) = dest.call{value: value}(data);
        if (!success) revert ChatterPayPaymaster__ExecutionFailed();
    }

    /**
     * @notice Withdraws all ETH from the contract
     * @dev Transfers the entire balance to the contract owner
     * @custom:error ChatterPayPaymaster__OnlyOwner if caller is not owner
     */
    function withdraw() external onlyOwner {
        (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
        if (!success) {
            revert ChatterPayPaymaster__WithdrawFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
    // INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Ensures that the function is only callable by the EntryPoint contract
     * @dev Reverts if the caller is not the EntryPoint contract
     * @custom:error ChatterPayPaymaster__OnlyEntryPoint if caller is not EntryPoint
     */
    function _requireFromEntryPoint() internal view {
        if (msg.sender != address(entryPoint)) {
            revert ChatterPayPaymaster__OnlyEntryPoint();
        }
    }

    /**
     * @notice Slices a portion of a byte array
     * @dev Extracts a section of bytes from the input data
     * @param data The source byte array
     * @param start The starting position of the slice
     * @param length The length of the slice
     * @return The sliced byte array
     * @custom:error ChatterPayPaymaster__SliceOutOfBounds if slice bounds exceed data length
     */
    function _slice(bytes memory data, uint256 start, uint256 length) internal pure returns (bytes memory) {
        if (data.length < start + length) {
            revert ChatterPayPaymaster__SliceOutOfBounds();
        }
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    /**
     * @notice Recovers the signer of a hashed message using OpenZeppelin's ECDSA.recover
     * @dev Uses ECDSA.recover to extract the signer address from a 65-byte signature.
     * This function assumes the messageHash is already hashed (e.g. via toEthSignedMessageHash if required).
     * @param messageHash The hash of the signed message (should follow Ethereum signed message format if applicable)
     * @param signature The 65-byte signature (r, s, v) to verify
     * @return The address of the recovered signer
     * @custom:error Reverts if the signature is malformed, has an invalid length, or invalid v/s values
     */
    function _recoverSigner(bytes32 messageHash, bytes memory signature) internal pure returns (address) {
        return ECDSA.recover(messageHash, signature);
    }
}
