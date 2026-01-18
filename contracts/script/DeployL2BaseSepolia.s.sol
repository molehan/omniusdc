// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import {L2Gateway} from "src/l2/L2Gateway.sol";

contract DeployL2BaseSepolia is Script {
    using stdJson for string;

    function run() external {
        require(block.chainid == 84532, "Not Base Sepolia");

        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        string memory cfg = vm.readFile("configs/networks.testnet.json");
        address usdc = cfg.readAddress(".baseSepolia.usdc");
        address tokenMessengerV2 = cfg.readAddress(".baseSepolia.cctp.tokenMessengerV2");

        address l1Executor = vm.envAddress("L1_EXECUTOR"); // خذه من deployments/testnet.json أو env

        vm.startBroadcast(pk);

        L2Gateway gw = new L2Gateway(
            usdc,
            tokenMessengerV2,
            0,          // destinationDomain = Sepolia domainId
            l1Executor
        );

        vm.stopBroadcast();

        // Write (append/update) deployments
        string memory out = vm.readFile("deployments/testnet.json");
        out = vm.serializeAddress("l2", "l2Gateway", address(gw));
        vm.writeJson(out, "deployments/testnet.json");
    }
}
