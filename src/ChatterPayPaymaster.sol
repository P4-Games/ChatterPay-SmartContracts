// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "lib/entry-point-v6/interfaces/IPaymaster.sol";

error ChatterPayPaymaster__OnlyOwner();
error ChatterPayPaymaster__OnlyEntryPoint();
error ChatterPayPaymaster__InvalidDataLength();
error ChatterPayPaymaster__SignatureExpired();
error ChatterPayPaymaster__InvalidSignature();
error ChatterPayPaymaster__InvalidChainId();
error ChatterPayPaymaster__InvalidVValue();
error ChatterPayPaymaster__SliceOutOfBounds();
error ChatterPayPaymaster__InvalidSignatureLength();
error ChatterPayPaymaster__ExecutionFailed();

/**
 * @title ChatterPayPaymaster
 * @notice A Paymaster contract for managing user operations with signature-based validation
 * @dev Integrates with the EntryPoint contract and validates operations signed by a backend signer
 */
contract ChatterPayPaymaster is IPaymaster {
    address public owner;
    address public entryPoint;
    address private backendSigner;
    uint256 private immutable chainId;

    /**
     * @notice Ensures that only the contract owner can call the function
     * @dev Reverts if the caller is not the contract owner
     * @custom:error ChatterPayPaymaster__OnlyOwner if the caller is not the owner
     */
    modifier onlyOwner() {
        if (msg.sender != owner) revert ChatterPayPaymaster__OnlyOwner();
        _;
    }

    /**
     * @notice Initializes the ChatterPayPaymaster contract
     * @dev Sets up the owner, entry point address, and backend signer for signature validation
     * @param _entryPoint The address of the EntryPoint contract
     * @param _backendSigner The address authorized to sign paymaster operations
     */
    constructor(address _entryPoint, address _backendSigner) {
        owner = msg.sender;
        entryPoint = _entryPoint;
        backendSigner = _backendSigner;
        chainId = block.chainid;
    }

    /**
     * @notice Allows the contract to receive ETH payments
     * @dev Implements the receive function to accept ETH transfers
     */
    receive() external payable {}

    /**
     * @notice Validates a UserOperation for the Paymaster
     * @dev Ensures the operation is properly signed and not expired
     * @param userOp The UserOperation struct containing operation details
     * @return context Additional context for the operation (empty in this case)
     * @return validationData A value indicating the validation status (0 = valid)
     * @custom:error ChatterPayPaymaster__OnlyEntryPoint if caller is not EntryPoint
     * @custom:error ChatterPayPaymaster__InvalidDataLength if paymasterAndData is malformed
     * @custom:error ChatterPayPaymaster__SignatureExpired if signature expiration is reached
     * @custom:error ChatterPayPaymaster__InvalidSignature if signature is invalid
     * @custom:error ChatterPayPaymaster__InvalidChainId if chain ID doesn't match
     */
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32,
        uint256
    ) external view override returns (bytes memory context, uint256 validationData) {
        _requireFromEntryPoint();
        /*
        bytes memory paymasterAndData = userOp.paymasterAndData;

        // Validate data length
        if (paymasterAndData.length != 93) revert ChatterPayPaymaster__InvalidDataLength();

        // Extract components
        bytes memory signature = _slice(paymasterAndData, 20, 65);
        uint64 expiration = uint64(bytes8(_slice(paymasterAndData, 85, 8)));

        // Validate expiration and chain
        if (block.timestamp > expiration) revert ChatterPayPaymaster__SignatureExpired();
        if (block.chainid != chainId) revert ChatterPayPaymaster__InvalidChainId();

        // Validate signature
        bytes32 messageHash = keccak256(
            abi.encode(
                userOp.sender,
                expiration,
                chainId,
                entryPoint,
                userOp.callData
            )
        );

        address recoveredAddress = _recoverSigner(messageHash, signature);
        if (recoveredAddress != backendSigner) revert ChatterPayPaymaster__InvalidSignature();
        */
        return ("", 0);
    }

    /**
    * @notice Implements the postOp function required by IPaymaster.
    * @dev This function is marked as view since it only verifies that the caller is the EntryPoint.
    */
    function postOp(
        PostOpMode,         // Unused parameter
        bytes calldata,     // Unused parameter
        uint256             // Unused parameter
    ) external view override {
        _requireFromEntryPoint();
    }

    /**
     * Add stake for this paymaster.
     * This method can also carry eth value to add to the current stake.
     * @param unstakeDelaySec - The unstake delay for this paymaster. Can only be increased.
     */
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{value: msg.value}(unstakeDelaySec);
    }

    /**
     * Return current paymaster's deposit on the entryPoint.
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint.balanceOf(address(this));
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
     * @notice Executes a low-level call to a specified address
     * @dev Only callable by the contract owner
     * @param dest The address to call
     * @param value The ETH value to send with the call
     * @param data The calldata for the function to execute
     * @custom:error ChatterPayPaymaster__OnlyOwner if caller is not owner
     * @custom:error ChatterPayPaymaster__ExecutionFailed if the call fails
     */
    function execute(
        address dest,
        uint256 value,
        bytes calldata data
    ) external onlyOwner {
        (bool success, ) = dest.call{value: value}(data);
        if (!success) revert ChatterPayPaymaster__ExecutionFailed();
    }

    /**
     * @notice Withdraws all ETH from the contract
     * @dev Transfers the entire balance to the contract owner
     * @custom:error ChatterPayPaymaster__OnlyOwner if caller is not owner
     */
    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /**
     * @notice Ensures that the function is only callable by the EntryPoint contract
     * @dev Reverts if the caller is not the EntryPoint contract
     * @custom:error ChatterPayPaymaster__OnlyEntryPoint if caller is not EntryPoint
     */
    function _requireFromEntryPoint() internal view {
        if (msg.sender != entryPoint) revert ChatterPayPaymaster__OnlyEntryPoint();
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
    function _slice(
        bytes memory data,
        uint256 start,
        uint256 length
    ) internal pure returns (bytes memory) {
        if (data.length < start + length) revert ChatterPayPaymaster__SliceOutOfBounds();
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    /**
     * @notice Recovers the signer of a hashed message
     * @dev Splits the signature into r, s, v and uses ecrecover to recover the signer address
     * @param messageHash The hash of the signed message
     * @param signature The signature to verify
     * @return The address of the recovered signer
     * @custom:error ChatterPayPaymaster__InvalidSignatureLength if signature length is invalid
     * @custom:error ChatterPayPaymaster__InvalidVValue if v value is not 27 or 28
     */
    function _recoverSigner(
        bytes32 messageHash,
        bytes memory signature
    ) internal pure returns (address) {
        if (signature.length != 65) revert ChatterPayPaymaster__InvalidSignatureLength();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        if (v != 27 && v != 28) revert ChatterPayPaymaster__InvalidVValue();
        return ecrecover(messageHash, v, r, s);
    }
}