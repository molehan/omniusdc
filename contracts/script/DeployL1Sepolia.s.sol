// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {USDCVault} from "src/vault/USDCVault.sol";
import {RiskManager} from "src/manager/RiskManager.sol";
import {StrategyManager} from "src/manager/StrategyManager.sol";
import {L1WithdrawRouter} from "src/router/L1WithdrawRouter.sol";

 import {L1CCTPExecutor} from "src/cctp/L1CCTPExecutor.sol";

contract DeployL1Sepolia is Script {
    using stdJson for string;

    function run() external {
        require(block.chainid == 11155111, "Not Sepolia");

        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // load config json
        string memory cfg = vm.readFile("configs/networks.testnet.json");
        address usdc = cfg.readAddress(".sepolia.usdc");
        address tokenMessengerV2 = cfg.readAddress(".sepolia.cctp.tokenMessengerV2");
        address messageTransmitterV2 = cfg.readAddress(".sepolia.cctp.messageTransmitterV2");

        // params
        uint256 tvlCap = vm.envUint("TVL_CAP");                 // e.g. 1_000_000e6
        uint16 bufferTargetBps = uint16(vm.envUint("BUFFER_TARGET_BPS")); // e.g. 1000
        uint256 maxMaxFee = vm.envUint("ROUTER_MAX_MAXFEE");    // e.g. 5e6 (5 USDC)
        uint256 maxSharesPerTx = vm.envUint("ROUTER_MAX_SHARES"); // e.g. 10_000e6 (حسب decimals shares)

        address guardian = vm.envOr("GUARDIAN", msg.sender);
        address strategist = vm.envOr("STRATEGIST", msg.sender);

        vm.startBroadcast(pk);

        // 1) Vault
        USDCVault vault = new USDCVault(
            IERC20Metadata(usdc),
            "OmniUSDC Vault Shares",
            "omniUSDC"
        );

        // 2) RiskManager
        RiskManager risk = new RiskManager();
        risk.setTVLCap(tvlCap);
        risk.setBufferTargetBps(bufferTargetBps);

        // 3) StrategyManager
        StrategyManager stratMgr = new StrategyManager(address(vault), usdc);

        // 4) Wire managers
        vault.setManagers(address(stratMgr), address(risk));

        // 5) Roles
        vault.grantRole(vault.GUARDIAN_ROLE(), guardian);
        vault.grantRole(vault.STRATEGIST_ROLE(), strategist);

        // 6) Executor (عدّل حسب constructor الحقيقي عندك)
         L1CCTPExecutor exec = new L1CCTPExecutor(usdc, address(vault), messageTransmitterV2, 0);

        // 7) WithdrawRouter
        L1WithdrawRouter router = new L1WithdrawRouter(address(vault), tokenMessengerV2);
        router.grantRole(router.GUARDIAN_ROLE(), guardian);
        router.setAllowedDestinationDomain(6, true);

        // 8) Router hardening caps
        router.setMaxMaxFee(maxMaxFee);
        router.setMaxSharesPerTx(maxSharesPerTx);

        vm.stopBroadcast();

            // 9) Output deployments
        string memory outObj = "l1_deployments"; // مفتاح داخلي للـ JSON
        vm.serializeAddress(outObj, "vault", address(vault));
        vm.serializeAddress(outObj, "riskManager", address(risk));
        vm.serializeAddress(outObj, "strategyManager", address(stratMgr));
        vm.serializeAddress(outObj, "executor", address(exec)); // أعدت تفعيله
        string memory finalJson = vm.serializeAddress(outObj, "withdrawRouter", address(router));
        
        vm.writeJson(finalJson, "deployments/testnet.json");

}


}