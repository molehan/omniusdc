import { CFG } from "./config.js";

const source = Number(process.argv[2]);
const dest = Number(process.argv[3]);
if (!Number.isFinite(source) || !Number.isFinite(dest)) {
  throw new Error("Usage: quote-fees <sourceDomain> <destDomain>");
}

async function main() {
  const url = `${CFG.IRIS_BASE}/v2/burn/USDC/fees/${source}/${dest}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${await res.text()}`);

  const data = await res.json();
  console.log(JSON.stringify(data, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
