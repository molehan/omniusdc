import { CFG } from "./config.js";

const nonce = process.argv[2];
if (!nonce) throw new Error("Usage: reattest <eventNonce>");

async function main() {
  const url = `${CFG.IRIS_BASE}/v2/reattest/${nonce}`;
  const res = await fetch(url, { method: "POST" });
  const text = await res.text();
  console.log("HTTP", res.status, text);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
