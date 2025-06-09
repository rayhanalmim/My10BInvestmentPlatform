// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {My10BToken} from "./My10BToken.sol";

/**
 * @title My10BInvestmentPlatform
 * @notice Handles user investments and authorised withdrawals for the My10Billion ecosystem.
 *         Users can invest using MY10B tokens without fees and withdraw with proper authorization.
 * @dev    Security-first architecture: pull-payments, re-entrancy guards, custom errors, role based auth.
 */
contract My10BInvestmentPlatform is EIP712, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               ROLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant WITHDRAWAL_SIGNER_ROLE = keccak256("WITHDRAWAL_SIGNER_ROLE");

    /*//////////////////////////////////////////////////////////////
                               STATE
    //////////////////////////////////////////////////////////////*/
    IERC20 public immutable my10bToken;        // ERC-20 accepted for deposits / withdrawals

    uint256 public withdrawalNonce;            // Monotonically increasing, prevents signature replay

    /*//////////////////////////////////////////////////////////////
                              CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAmount();
    error DeadlineExpired();
    error InvalidSignature();

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/
    event InvestToken(address indexed user, uint256 amount);
    event WithdrawToken(address indexed user, uint256 amount, uint256 nonce);

    /*//////////////////////////////////////////////////////////////
                            INITIALISATION
    //////////////////////////////////////////////////////////////*/
    constructor(address _token) EIP712("My10BInvestmentPlatform", "1") {
        require(_token != address(0), "Zero address");
        my10bToken = IERC20(_token);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(WITHDRAWAL_SIGNER_ROLE, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        USER-FACING: INVESTMENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit My10B tokens into the platform without any fees.
    /// @param amount The amount of tokens the user wishes to deposit.
    function investWithToken(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();

        // Transfer tokens from user to platform
        my10bToken.safeTransferFrom(msg.sender, address(this), amount);

        emit InvestToken(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        USER-FACING: WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    /// @notice Withdraw My10B tokens previously deposited. Must be authorised by an off-chain signer.
    /// @param amount   Token amount user will receive.
    /// @param deadline Signature validity deadline (unix timestamp).
    /// @param sig      Off-chain signature from authorised signer.
    function withdrawToken(uint256 amount, uint256 deadline, bytes calldata sig)
        external
        nonReentrant
        whenNotPaused
    {
        if (amount == 0) revert InvalidAmount();
        if (block.timestamp > deadline) revert DeadlineExpired();

        // Consume nonce to protect against replay
        uint256 nonce = withdrawalNonce++;

        // Verify signature
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Withdraw(address user,uint256 amount,uint256 deadline,uint256 nonce)"),
            msg.sender,
            amount,
            deadline,
            nonce
        ));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, sig);
        if (!hasRole(WITHDRAWAL_SIGNER_ROLE, signer)) revert InvalidSignature();

        // Effects
        my10bToken.safeTransfer(msg.sender, amount);

        emit WithdrawToken(msg.sender, amount, nonce);
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @notice Pause the contract, disabling deposits / withdrawals.
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                               UTILITIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the EIP-712 domain separator for off-chain signing.
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Get the current balance of MY10B tokens held by the platform.
    function platformBalance() external view returns (uint256) {
        return my10bToken.balanceOf(address(this));
    }
}