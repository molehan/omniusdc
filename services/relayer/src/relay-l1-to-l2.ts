import { ethers } from "ethers";
import { CFG, assertTxHash } from "./config.js";
import { waitForCompleteMessageByTxHash } from "./iris.js";
import { MESSAGE_TRANSMITTER_V2_ABI } from "./abi.js";

if (!CFG.RPC_L2 || !CFG.PK_L2 || !CFG.CCTP_MESSAGE_TRANSMITTER_V2) {
  throw new Error("Missing env. Need RPC_L2, PK_L2, CCTP_MESSAGE_TRANSMITTER_V2");
}

const txHash = process.argv[2];
if (!txHash) throw new Error("Usage: relay-l1-to-l2 <L1_txHash>");
assertTxHash(txHash);

async function main() {
  const irisMsg = await waitForCompleteMessageByTxHash(
    CFG.IRIS_BASE,
    CFG.DOMAIN_L1,
    txHash
  );

  const providerL2 = new ethers.JsonRpcProvider(CFG.RPC_L2);
  const walletL2 = new ethers.Wallet(CFG.PK_L2, providerL2);

  const mt = new ethers.Contract(
    CFG.CCTP_MESSAGE_TRANSMITTER_V2,
    MESSAGE_TRANSMITTER_V2_ABI,
    walletL2
  );

  try {
    const tx = await mt.receiveMessage(irisMsg.message, irisMsg.attestation);
    console.log("receiveMessage tx:", tx.hash);

    const rcpt = await tx.wait();
    console.log("receiveMessage mined. status:", rcpt?.status);
  } catch (e: any) {
    console.error(
      "receiveMessage failed (possibly already processed):",
      e?.shortMessage ?? e?.message ?? e
    );
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
