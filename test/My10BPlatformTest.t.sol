// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/My10BToken.sol";
import "../src/My10BInvestmentPlatform.sol";

contract My10BPlatformTest is Test {
    My10BToken public token;
    My10BInvestmentPlatform public platform;
    address public admin;
    address public user1 = address(2);
    address public user2 = address(3);
    address public treasury = address(4);
    
    uint256 adminPrivateKey = 0xABCD;
    uint256 platformFee = 250; // 2.5%
    
    function setUp() public {
        admin = vm.addr(adminPrivateKey);
        vm.startPrank(admin);
        
        // Deploy contracts
        token = new My10BToken();
        platform = new My10BInvestmentPlatform(address(token), treasury);
        
        // Setup roles
        bytes32 withdrawalSignerRole = platform.WITHDRAWAL_SIGNER_ROLE();
        platform.grantRole(withdrawalSignerRole, admin);
        
        // Mint tokens to users for testing
        token.mint(user1, 1000 ether);
        token.mint(user2, 1000 ether);
        
        vm.stopPrank();
    }
    
    function testInvestWithETH() public {
        uint256 investAmount = 1 ether;
        uint256 expectedFee = (investAmount * platformFee) / 10000;
        uint256 expectedNet = investAmount - expectedFee;
        
        uint256 treasuryBalanceBefore = treasury.balance;
        
        vm.deal(user1, investAmount);
        vm.prank(user1);
        platform.investWithETH{value: investAmount}();
        
        assertEq(treasury.balance - treasuryBalanceBefore, expectedFee);
        assertEq(address(platform).balance, expectedNet);
    }
    
    function testInvestWithToken() public {
        uint256 investAmount = 100 ether;
        uint256 expectedFee = (investAmount * platformFee) / 10000;
        uint256 expectedNet = investAmount - expectedFee;
        
        vm.startPrank(user1);
        token.approve(address(platform), investAmount);
        platform.investWithToken(investAmount);
        vm.stopPrank();
        
        assertEq(token.balanceOf(address(platform)), expectedNet);
        assertEq(token.balanceOf(treasury), expectedFee);
        assertEq(token.balanceOf(user1), 1000 ether - investAmount);
    }
    
    function testWithdrawToken() public {
        // First invest with tokens
        uint256 investAmount = 100 ether;
        
        vm.startPrank(user1);
        token.approve(address(platform), investAmount);
        platform.investWithToken(investAmount);
        vm.stopPrank();
        
        // Now withdraw
        uint256 withdrawAmount = 50 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = platform.withdrawalNonce();
        
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Withdraw(address user,uint256 amount,uint256 deadline,uint256 nonce)"),
            user1,
            withdrawAmount,
            deadline,
            nonce
        ));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", platform.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        uint256 userBalanceBefore = token.balanceOf(user1);
        
        vm.prank(user1);
        platform.withdrawToken(withdrawAmount, deadline, signature);
        
        assertEq(token.balanceOf(user1) - userBalanceBefore, withdrawAmount);
    }
    
    function testPauseFunctionality() public {
        vm.prank(admin);
        platform.pause();
        
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        platform.investWithToken(100 ether);
        vm.stopPrank();
        
        vm.prank(admin);
        platform.unpause();
        
        // Should work now
        vm.startPrank(user1);
        token.approve(address(platform), 100 ether);
        platform.investWithToken(100 ether);
        vm.stopPrank();
    }
}