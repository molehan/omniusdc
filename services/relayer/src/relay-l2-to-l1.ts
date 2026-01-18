import { ethers } from "ethers";
import { CFG, assertTxHash } from "./config.js";
import { waitForCompleteMessageByTxHash } from "./iris.js";
import { L1_EXECUTOR_ABI } from "./abi.js";

if (!CFG.RPC_L1 || !CFG.PK_L1 || !CFG.L1_EXECUTOR) {
  throw new Error("Missing env. Need RPC_L1, PK_L1, L1_EXECUTOR");
}

const txHash = process.argv[2];
if (!txHash) throw new Error("Usage: relay-l2-to-l1 <L2_txHash>");
assertTxHash(txHash);

async function main() {
  const irisMsg = await waitForCompleteMessageByTxHash(
    CFG.IRIS_BASE,
    CFG.DOMAIN_L2,
    txHash
  );

  console.log("Iris status:", irisMsg.status);
  console.log("eventNonce:", irisMsg.eventNonce);
  console.log("message len (bytes):", (irisMsg.message.length - 2) / 2);

  const providerL1 = new ethers.JsonRpcProvider(CFG.RPC_L1);
  const walletL1 = new ethers.Wallet(CFG.PK_L1, providerL1);

  const exec = new ethers.Contract(CFG.L1_EXECUTOR, L1_EXECUTOR_ABI, walletL1);

  const tx = await exec.finalize(irisMsg.message, irisMsg.attestation);
  console.log("Finalize tx:", tx.hash);

  const rcpt = await tx.wait();
  console.log("Finalize mined. status:", rcpt?.status);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
