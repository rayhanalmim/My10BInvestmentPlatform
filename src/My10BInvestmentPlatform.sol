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
 *         The contract purposefully limits its scope to deposits and custodial withdrawals
 *         (authorised off-chain via signatures) until full decentralisation is introduced.
 * @dev    Security-first architecture: pull-payments, re-entrancy guards, custom errors, role based auth.
 */
contract My10BInvestmentPlatform is EIP712, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               ROLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant WITHDRAWAL_SIGNER_ROLE = keccak256("WITHDRAWAL_SIGNER_ROLE");
    bytes32 public constant TREASURY_ROLE         = keccak256("TREASURY_ROLE");

    /*//////////////////////////////////////////////////////////////
                               STATE
    //////////////////////////////////////////////////////////////*/
    IERC20 public immutable my10bToken;        // ERC-20 accepted for deposits / withdrawals
    address public immutable treasury;         // Fee destination

    uint16 public constant FEE_BPS = 250;      // 2.5 % expressed in basis points (parts per 10_000)

    uint256 public withdrawalNonce;            // Monotonically increasing, prevents signature replay

    /*//////////////////////////////////////////////////////////////
                              CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAmount();
    error DeadlineExpired();
    error InvalidSignature();
    error TransferFailed();

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/
    event InvestETH(address indexed user, uint256 amount, uint256 fee);
    event InvestToken(address indexed user, uint256 amount, uint256 fee);
    event WithdrawToken(address indexed user, uint256 amount, uint256 nonce);
    event TreasuryWithdrawETH(address indexed treasury, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            INITIALISATION
    //////////////////////////////////////////////////////////////*/
    constructor(address _token, address _treasury) EIP712("My10BInvestmentPlatform", "1") {
        require(_token != address(0) && _treasury != address(0), "Zero address");
        my10bToken = IERC20(_token);
        treasury   = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(WITHDRAWAL_SIGNER_ROLE, msg.sender);
        _grantRole(TREASURY_ROLE, _treasury);
    }

    /*//////////////////////////////////////////////////////////////
                        USER-FACING: INVESTMENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit ETH into the platform. A platform fee is siphoned to treasury.
    function investWithETH() external payable nonReentrant whenNotPaused {
        uint256 amount = msg.value;
        if (amount == 0) revert InvalidAmount();

        uint256 fee = (amount * FEE_BPS) / 10_000;
        _forwardETH(treasury, fee);

        emit InvestETH(msg.sender, amount - fee, fee);
        // Remaining ETH kept in contract custody (could be bridged off-chain)
    }

    /// @notice Deposit My10B tokens into the platform. A platform fee is siphoned to treasury.
    /// @param amount The full amount of tokens the user wishes to deposit.
    function investWithToken(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();

        uint256 fee = (amount * FEE_BPS) / 10_000;
        uint256 net = amount - fee;

        // Pull all tokens
        my10bToken.safeTransferFrom(msg.sender, address(this), net);
        if (fee != 0) my10bToken.safeTransferFrom(msg.sender, treasury, fee);

        emit InvestToken(msg.sender, net, fee);
    }

    /*//////////////////////////////////////////////////////////////
                        USER-FACING: WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    /// @notice Withdraw My10B tokens previously deposited. Must be authorised by an off-chain signer.
    /// @param amount   Net token amount user will receive.
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
                           ADMIN / TREASURY
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows the treasury to sweep accumulated ETH fees.
    /// @param amount Amount of ETH to withdraw.
    function treasuryWithdrawETH(uint256 amount) external nonReentrant onlyRole(TREASURY_ROLE) {
        _forwardETH(treasury, amount);
        emit TreasuryWithdrawETH(treasury, amount);
    }

    /// @notice Pause the contract, disabling deposits / withdrawals.
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _forwardETH(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /*//////////////////////////////////////////////////////////////
                               FALLBACKS
    //////////////////////////////////////////////////////////////*/
    receive() external payable {
        // Accept plain ETH transfers (e.g., refunds) without accounting.
    }

    fallback() external payable {}

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}