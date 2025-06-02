// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/My10BToken.sol";
import "../src/My10BInvestmentPlatform.sol";

contract DeployMy10B is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy token
        My10BToken token = new My10BToken();
        console.log("My10BToken deployed at:", address(token));
        
        // Deploy platform
        My10BInvestmentPlatform platform = new My10BInvestmentPlatform(
            address(token),
            treasury
        );
        console.log("My10BInvestmentPlatform deployed at:", address(platform));
        
        // Setup initial roles if needed
        bytes32 withdrawalSignerRole = platform.WITHDRAWAL_SIGNER_ROLE();
        platform.grantRole(withdrawalSignerRole, msg.sender);
        
        // Mint initial tokens to deployer
        token.mint(msg.sender, 1_000_000 * 10**18); // 1 million tokens
        
        vm.stopBroadcast();
    }
}