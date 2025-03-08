// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error ChatterPayVault__CommitmentAlreadySet();
error ChatterPayVault__NoBalanceToRedeem();
error ChatterPayVault__IncorrectPassword();
error ChatterPayVault__NoCommitmentFound();
error ChatterPayVault__UnauthorizedRedeemer();
error ChatterPayVault__InvalidCommitment();
error ChatterPayVault__CommitmentExpired();
error ChatterPayVault__NoBalanceToCancel();
error ChatterPayVault__CannotCancelActiveCommit();
error ChatterPayVault__InvalidId();
error ChatterPayVault__InvalidCommitmentHash();
error ChatterPayVault__UnauthorizedCancel();

/**
 * @title ChatterPayVault
 * @notice A vault contract for reserving, committing, redeeming, and canceling payments with password-protected commitments.
 * @dev Utilizes ERC20 tokens and includes commitment expiration for added security.
 */
contract ChatterPayVault {
    struct Payment {
        address wallet;
        address token;
        uint256 balance;
        bytes32 passwordHash;
        address redeemer;
        bool isReserved;
        bool isCommited;
        bool isRedeemed;
        uint256 commitTimestamp;
    }

    struct Commit {
        bytes32 commitmentHash;
        uint256 timestamp;
        address redeemer;
    }

    uint256 constant COMMIT_TIMEOUT = 1 hours;

    mapping(uint256 id => Payment) public payments;

    event PaymentReserved(
        address indexed payer,
        address indexed token,
        uint256 indexed amount
    );
    event PaymentCommitted(
        address indexed commiter,
        address indexed token,
        uint256 indexed amount
    );
    event PaymentRedeemed(
        address indexed wallet,
        address indexed token,
        address redeemer,
        uint256 amount
    );
    event PaymentCancelled(
        address indexed payer,
        address indexed token,
        uint256 amount
    );

    /**
     * @notice Reserves a payment with a specified ERC20 token, amount, and password hash.
     * @dev Transfers the specified amount of tokens from the payer to the contract.
     * @param _erc20 The address of the ERC20 token to be used.
     * @param _id The unique identifier for the payment.
     * @param _amount The amount of tokens to reserve.
     * @param _passwordHash The keccak256 hash of the password for payment redemption.
     * @custom:events Emits a `PaymentReserved` event on success.
     * @custom:reverts ChatterPayVault__InvalidId if the payment ID is already reserved or redeemed.
     */
    function reservePayment(
        address _erc20,
        uint256 _id,
        uint256 _amount,
        bytes32 _passwordHash
    ) public {
        if (payments[_id].isReserved || payments[_id].isRedeemed)
            revert ChatterPayVault__InvalidId();
        payments[_id] = Payment({
            wallet: msg.sender,
            token: _erc20,
            balance: _amount,
            passwordHash: _passwordHash,
            redeemer: address(0),
            isReserved: true,
            isCommited: false,
            isRedeemed: false,
            commitTimestamp: 0
        });
        IERC20(_erc20).transferFrom(msg.sender, address(this), _amount);
        emit PaymentReserved(msg.sender, _erc20, _amount);
    }

    /**
     * @notice Commits a redeemer for a reserved payment by providing the correct commitment hash.
     * @dev Updates the payment's redeemer and timestamp, locking it for redemption.
     * @param _id The unique identifier for the payment.
     * @param _commitmentHash The keccak256 hash of the password used for commitment verification.
     * @custom:events Emits a `PaymentCommitted` event on success.
     * @custom:reverts ChatterPayVault__InvalidId if the payment is already committed or redeemed.
     * @custom:reverts ChatterPayVault__InvalidCommitmentHash if the commitment hash does not match.
     */
    function commitForPayment(uint256 _id, bytes32 _commitmentHash) public {
        if (payments[_id].isCommited || payments[_id].isRedeemed)
            revert ChatterPayVault__InvalidId();
        if (payments[_id].passwordHash != _commitmentHash)
            revert ChatterPayVault__InvalidCommitmentHash();
        payments[_id].redeemer = msg.sender;
        payments[_id].isCommited = true;
        payments[_id].commitTimestamp = block.timestamp;
        emit PaymentCommitted(
            msg.sender,
            payments[_id].token,
            payments[_id].balance
        );
    }

    /**
     * @notice Redeems a committed payment by providing the correct password.
     * @dev Transfers the payment's balance to the redeemer after verifying the password.
     * @param _id The unique identifier for the payment.
     * @param _password The password corresponding to the payment's password hash.
     * @custom:events Emits a `PaymentRedeemed` event on success.
     * @custom:reverts ChatterPayVault__InvalidId if the payment is not committed or already redeemed.
     * @custom:reverts ChatterPayVault__UnauthorizedRedeemer if the caller is not the redeemer.
     * @custom:reverts ChatterPayVault__NoBalanceToRedeem if the payment balance is zero.
     * @custom:reverts ChatterPayVault__CommitmentExpired if the commitment timeout has elapsed.
     * @custom:reverts ChatterPayVault__IncorrectPassword if the password does not match the hash.
     */
    function redeemPayment(uint256 _id, string memory _password) public {
        Payment storage payment = payments[_id];
        if (payment.isRedeemed || !payment.isCommited)
            revert ChatterPayVault__InvalidId();
        if (payment.redeemer != msg.sender)
            revert ChatterPayVault__UnauthorizedRedeemer();
        if (payment.balance == 0) revert ChatterPayVault__NoBalanceToRedeem();

        if (block.timestamp > payment.commitTimestamp + COMMIT_TIMEOUT) {
            revert ChatterPayVault__CommitmentExpired();
        }

        // Verify password matches the payment's password hash
        if (keccak256(abi.encodePacked(_password)) != payment.passwordHash)
            revert ChatterPayVault__IncorrectPassword();

        // Transfer the funds
        uint256 amount = payment.balance;
        payment.balance = 0;
        payment.isRedeemed = true;
        payment.isReserved = false;
        payment.isCommited = false;
        payment.passwordHash = bytes32(0);
        IERC20(payment.token).transfer(msg.sender, amount);

        emit PaymentRedeemed(payment.wallet, payment.token, msg.sender, amount);
    }

    /**
     * @notice Cancels a reserved payment and returns the funds to the payer.
     * @dev Allows cancellation if no active commitment exists or if the commitment has expired.
     * @param _erc20 The address of the ERC20 token used in the payment.
     * @param _id The unique identifier for the payment.
     * @custom:events Emits a `PaymentCancelled` event on success.
     * @custom:reverts ChatterPayVault__UnauthorizedCancel if the caller is not the payer.
     * @custom:reverts ChatterPayVault__NoBalanceToCancel if the payment balance is zero.
     * @custom:reverts ChatterPayVault__CannotCancelActiveCommit if the commitment has not expired.
     */
    function cancelPayment(address _erc20, uint256 _id) public {
        Payment storage payment = payments[_id];
        if (payment.wallet != msg.sender)
            revert ChatterPayVault__UnauthorizedCancel();
        if (payment.balance == 0) revert ChatterPayVault__NoBalanceToCancel();

        // Verificar si hay un compromiso activo
        if (payment.passwordHash != bytes32(0)) {
            // Si hay un compromiso, verificar si ha expirado
            if (block.timestamp <= payment.commitTimestamp + COMMIT_TIMEOUT) {
                revert ChatterPayVault__CannotCancelActiveCommit();
            }
        }

        // Transferir los fondos de vuelta al pagador
        uint256 amount = payment.balance;
        payment.balance = 0;
        IERC20(_erc20).transfer(msg.sender, amount);
        delete payments[_id];

        emit PaymentCancelled(msg.sender, _erc20, amount);
    }
}
