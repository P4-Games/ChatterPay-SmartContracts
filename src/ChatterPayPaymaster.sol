// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "lib/account-abstraction/contracts/interfaces/IPaymaster.sol";
import "lib/account-abstraction/contracts/interfaces/UserOperation.sol";

error ChatterPayPaymaster__InvalidDataLength();
error ChatterPayPaymaster__SignatureExpired();
error ChatterPayPaymaster__InvalidSignature();
error ChatterPayPaymaster__InvalidChainId();
error ChatterPayPaymaster__InvalidVValue();

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
     * @custom:reverts ChatterPayPaymaster: only owner can call this function if the caller is not the owner
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "ChatterPay: Only owner");
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
     * @custom:reverts ChatterPayPaymaster__InvalidDataLength if `paymasterAndData` is malformed
     * @custom:reverts ChatterPayPaymaster__SignatureExpired if the signature expiration is reached
     * @custom:reverts ChatterPayPaymaster__InvalidSignature if the signature is invalid
     * @custom:reverts ChatterPayPaymaster__InvalidChainId if the chain ID doesn't match
     */
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32, // userOpHash (unused)
        uint256 // maxCost (unused)
    ) external view returns (bytes memory, uint256) {
        _requireFromEntryPoint();
        bytes memory paymasterAndData = userOp.paymasterAndData;

        // Expected format: paymasterAddress (20 bytes) + signature (65 bytes) + expiration (8 bytes)
        if (paymasterAndData.length != 93) {
            revert ChatterPayPaymaster__InvalidDataLength();
        }

        // Extract components from paymasterAndData
        bytes memory signature = _slice(paymasterAndData, 20, 65);
        uint64 expiration = uint64(bytes8(_slice(paymasterAndData, 85, 8)));

        // Validate expiration and chain
        if (block.timestamp > expiration) {
            revert ChatterPayPaymaster__SignatureExpired();
        }
        if (block.chainid != chainId) {
            revert ChatterPayPaymaster__InvalidChainId();
        }

        // Reconstruct signed message (includes callData)
        bytes32 messageHash = keccak256(
            abi.encode(
                userOp.sender,
                expiration,
                chainId,
                entryPoint,
                userOp.callData
            )
        );

        // Validate signature
        address recoveredAddress = _recoverSigner(messageHash, signature);
        if (recoveredAddress != backendSigner) {
            revert ChatterPayPaymaster__InvalidSignature();
        }

        return ("", 0);
    }

    /**
     * @notice Slices a portion of a byte array
     * @dev Extracts a section of bytes from the input data
     * @param data The source byte array
     * @param start The starting position of the slice
     * @param length The length of the slice
     * @return The sliced byte array
     * @custom:reverts If the slice bounds exceed the data length
     */
    function _slice(
        bytes memory data,
        uint256 start,
        uint256 length
    ) internal pure returns (bytes memory) {
        require(data.length >= start + length, "Slice out of bounds");
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
     * @custom:reverts ChatterPayPaymaster__InvalidSignature if the signature length is invalid
     * @custom:reverts ChatterPayPaymaster__InvalidVValue if the v value is not 27 or 28
     */
    function _recoverSigner(
        bytes32 messageHash,
        bytes memory signature
    ) internal pure returns (address) {
        require(signature.length == 65, "Invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        if (v != 27 && v != 28) {
            revert ChatterPayPaymaster__InvalidVValue();
        }
        return ecrecover(messageHash, v, r, s);
    }

    /**
     * @notice Handles the post-operation logic
     * @dev Currently not implemented but required by the IPaymaster interface
     * @param mode The mode of the post-operation
     * @param context Additional context provided during validation
     * @param actualGasCost The actual gas cost of the operation
     */
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) external override {}

    /**
     * @notice Executes a low-level call to a specified address
     * @dev Only callable by the contract owner
     * @param dest The address to call
     * @param value The ETH value to send with the call
     * @param data The calldata for the function to execute
     * @custom:reverts ChatterPayPaymaster: execution failed if the call fails
     */
    function execute(
        address dest,
        uint256 value,
        bytes calldata data
    ) external onlyOwner {
        (bool success, ) = dest.call{value: value}(data);
        if (!success) {
            revert("ChatterPayPaymaster: execution failed");
        }
    }

    /**
     * @notice Withdraws all ETH from the contract
     * @dev Transfers the entire balance to the contract owner
     * @custom:reverts ChatterPayPaymaster: only owner can call this function if the caller is not the owner
     */
    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /**
     * @notice Ensures that the function is only callable by the EntryPoint contract
     * @dev Reverts if the caller is not the EntryPoint contract
     * @custom:reverts ChatterPayPaymaster: only entry point can call this function if the caller is not EntryPoint
     */
    function _requireFromEntryPoint() internal view {
        if (msg.sender != entryPoint) {
            revert(
                "ChatterPayPaymaster: only entry point can call this function"
            );
        }
    }
}