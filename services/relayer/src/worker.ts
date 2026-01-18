import "dotenv/config";
import { ethers } from "ethers";
import { createRequire } from "node:module";
import { setTimeout as sleep } from "node:timers/promises";

import { CFG } from "./config.js";
import {
  L1_EXECUTOR_ABI,
  MESSAGE_TRANSMITTER_V2_ABI,
  L1_WITHDRAW_ROUTER_ABI,
  L2_GATEWAY_ABI,
} from "./abi.js";

type JobKind = "deposit" | "withdraw";
type JobStatus =
  | "seen"
  | "iris_pending"
  | "iris_complete"
  | "relaying"
  | "relayed"
  | "already_processed"
  | "failed_retry"
  | "failed_terminal";

type JobRow = {
  id: number;
  kind: JobKind;
  source_chain: "l1" | "l2";
  source_domain: number;
  source_tx_hash: string;
  source_block: number;
  source_log_index: number;

  status: JobStatus;
  attempts: number;
  next_run_at: number;
  first_seen_at: number;
  updated_at: number;

  iris_event_nonce: string | null;
  iris_message: string | null;
  iris_attestation: string | null;

  dest_chain: "l1" | "l2" | null;
  dest_tx_hash: string | null;

  alerted_attestation: number;
  alerted_relay: number;
  alerted_error: number;

  last_error: string | null;
};

const require = createRequire(import.meta.url);
const BetterSqlite3 = require("better-sqlite3");

function nowMs(): number {
  return Date.now();
}

function isNonceAlreadyUsed(e: any): boolean {
  const msg =
    e?.shortMessage ??
    e?.reason ??
    e?.revert?.args?.[0] ??
    e?.info?.error?.message ??
    e?.message ??
    "";
  return /nonce already used/i.test(String(msg));
}

function isAlreadyProcessedLike(e: any): boolean {
  const msg =
    e?.shortMessage ??
    e?.reason ??
    e?.revert?.args?.[0] ??
    e?.info?.error?.message ??
    e?.message ??
    "";
  return /already processed|already received|nonce already used/i.test(String(msg));
}

async function fetchJson(url: string, timeoutMs = 10_000): Promise<{ status: number; json?: any; text?: string }> {
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: ac.signal });
    if (res.status === 404) return { status: 404 };

    const text = await res.text().catch(() => "");
    if (!res.ok) return { status: res.status, text };

    const json = text ? JSON.parse(text) : {};
    return { status: res.status, json };
  } finally {
    clearTimeout(t);
  }
}

async function sendAlert(title: string, body: string): Promise<void> {
  if (!CFG.ALERT_WEBHOOK_URL) return;

  const payload =
    CFG.ALERT_WEBHOOK_KIND === "generic"
      ? { title, body, ts: new Date().toISOString() }
      : { text: `*${title}*\n${body}` }; // Slack incoming webhook friendly

  try {
    await fetch(CFG.ALERT_WEBHOOK_URL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    console.error("Alert webhook failed:", e);
  }
}

function initDb(db: any) {
  db.pragma("journal_mode = WAL");

  db.exec(`
    CREATE TABLE IF NOT EXISTS meta (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS jobs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,

      kind TEXT NOT NULL,
      source_chain TEXT NOT NULL,
      source_domain INTEGER NOT NULL,
      source_tx_hash TEXT NOT NULL,
      source_block INTEGER NOT NULL,
      source_log_index INTEGER NOT NULL,

      status TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      next_run_at INTEGER NOT NULL DEFAULT 0,
      first_seen_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,

      iris_event_nonce TEXT,
      iris_message TEXT,
      iris_attestation TEXT,

      dest_chain TEXT,
      dest_tx_hash TEXT,

      alerted_attestation INTEGER NOT NULL DEFAULT 0,
      alerted_relay INTEGER NOT NULL DEFAULT 0,
      alerted_error INTEGER NOT NULL DEFAULT 0,

      last_error TEXT,

      UNIQUE(kind, source_tx_hash, source_log_index)
    );

    CREATE INDEX IF NOT EXISTS idx_jobs_due
      ON jobs(status, next_run_at);

    CREATE INDEX IF NOT EXISTS idx_jobs_source
      ON jobs(kind, source_tx_hash);
  `);
}

function metaGet(db: any, key: string): string | null {
  const row = db.prepare(`SELECT value FROM meta WHERE key = ?`).get(key);
  return row?.value ?? null;
}

function metaSet(db: any, key: string, value: string): void {
  db.prepare(`INSERT INTO meta(key, value) VALUES (?, ?)
              ON CONFLICT(key) DO UPDATE SET value=excluded.value`).run(key, value);
}

function jobInsertIfMissing(db: any, j: {
  kind: JobKind;
  source_chain: "l1" | "l2";
  source_domain: number;
  source_tx_hash: string;
  source_block: number;
  source_log_index: number;
}) {
  const t = nowMs();
  db.prepare(`
    INSERT OR IGNORE INTO jobs(
      kind, source_chain, source_domain, source_tx_hash, source_block, source_log_index,
      status, attempts, next_run_at, first_seen_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?)
  `).run(
    j.kind, j.source_chain, j.source_domain, j.source_tx_hash, j.source_block, j.source_log_index,
    "seen", t, t, t
  );
}

function jobUpdate(db: any, id: number, patch: Partial<JobRow>) {
  const keys = Object.keys(patch);
  if (!keys.length) return;

  const cols = keys.map((k) => `${k} = ?`).join(", ");
  const vals = keys.map((k) => (patch as any)[k]);

  db.prepare(`UPDATE jobs SET ${cols} WHERE id = ?`).run(...vals, id);
}

function jobGetDue(db: any, limit: number): JobRow[] {
  const t = nowMs();
  return db.prepare(`
    SELECT * FROM jobs
    WHERE status IN ('seen','iris_pending','iris_complete','relaying','failed_retry')
      AND next_run_at <= ?
    ORDER BY next_run_at ASC
    LIMIT ?
  `).all(t, limit) as JobRow[];
}

async function scanEvents(params: {
  db: any;
  provider: ethers.JsonRpcProvider;
  contract: ethers.Contract;
  kind: JobKind;
  source_chain: "l1" | "l2";
  source_domain: number;
  metaKeyLastBlock: string;
  confirmations: number;
}) {
  const { db, provider, contract, kind, source_chain, source_domain, metaKeyLastBlock, confirmations } = params;

  const latest = await provider.getBlockNumber();
  const safeTo = Math.max(0, latest - confirmations);

  const lastStr = metaGet(db, metaKeyLastBlock);
  let last = lastStr ? Number(lastStr) : safeTo; // أول تشغيل: ابدأ من safeTo (لا backfill)
  if (!Number.isFinite(last)) last = safeTo;

  // لا تتقدم إذا لا يوجد جديد
  if (last >= safeTo) return;

  const from = last + 1;
  const to = Math.min(from + CFG.BLOCK_BATCH - 1, safeTo);

  // queryFilter
  const filter =
    kind === "deposit"
      ? (contract as any).filters.DepositInitiated()
      : (contract as any).filters.WithdrawExecuted();

  const logs = await contract.queryFilter(filter, from, to);

  for (const ev of logs as any[]) {
    jobInsertIfMissing(db, {
      kind,
      source_chain,
      source_domain,
      source_tx_hash: ev.transactionHash,
      source_block: ev.blockNumber,
      source_log_index: ev.index ?? ev.logIndex ?? 0,
    });
  }

  metaSet(db, metaKeyLastBlock, String(to));
}

async function irisPollByTxHash(sourceDomain: number, txHash: string) {
  const url = `${CFG.IRIS_BASE}/v2/messages/${sourceDomain}?transactionHash=${txHash}`;
  const r = await fetchJson(url, 10_000);

  if (r.status === 404) return { state: "pending" as const };
  if (r.status === 429) return { state: "rate_limited" as const };
  if (r.status !== 200) return { state: "error" as const, error: `Iris HTTP ${r.status}: ${r.text ?? ""}` };

  const msgs = (r.json?.messages ?? []) as any[];
  const complete = msgs.find((m) => m?.status === "complete" && m?.attestation && m?.message);

  if (!complete) return { state: "pending" as const };

  return {
    state: "complete" as const,
    message: complete.message as string,
    attestation: complete.attestation as string,
    eventNonce: String(complete.eventNonce ?? ""),
  };
}

async function main() {
  // DB
  const db = new BetterSqlite3(CFG.DB_PATH);
  initDb(db);

  // Providers
  const pL1 = new ethers.JsonRpcProvider(CFG.RPC_L1);
  const pL2 = new ethers.JsonRpcProvider(CFG.RPC_L2);

  // Contracts (read-only for event scans)
  const l2gw = new ethers.Contract(CFG.L2_GATEWAY, L2_GATEWAY_ABI, pL2);
  const l1router = new ethers.Contract(CFG.L1_WITHDRAW_ROUTER, L1_WITHDRAW_ROUTER_ABI, pL1);

  // Contracts (write for relaying)
  const wL1 = new ethers.Wallet(CFG.PK_L1, pL1);
  const wL2 = new ethers.Wallet(CFG.PK_L2, pL2);

  const exec = new ethers.Contract(CFG.L1_EXECUTOR, L1_EXECUTOR_ABI, wL1);
  const mt = new ethers.Contract(CFG.CCTP_MESSAGE_TRANSMITTER_V2, MESSAGE_TRANSMITTER_V2_ABI, wL2);

  const attnPendingMs = CFG.ALERT_ATTESTATION_PENDING_MIN * 60_000;
  const relayPendingMs = CFG.ALERT_RELAY_PENDING_MIN * 60_000;

  console.log("Relayer worker started");
  console.log("DB:", CFG.DB_PATH);
  console.log("RELAY_ENABLED:", CFG.RELAY_ENABLED);

  let lastScanAt = 0;

  while (true) {
    const loopStart = nowMs();

    try {
      // 1) Scan events periodically
      if (loopStart - lastScanAt >= CFG.SCAN_INTERVAL_MS) {
        await scanEvents({
          db,
          provider: pL2,
          contract: l2gw,
          kind: "deposit",
          source_chain: "l2",
          source_domain: CFG.DOMAIN_L2,
          metaKeyLastBlock: "l2_last_block",
          confirmations: CFG.L2_CONFIRMATIONS,
        });

        await scanEvents({
          db,
          provider: pL1,
          contract: l1router,
          kind: "withdraw",
          source_chain: "l1",
          source_domain: CFG.DOMAIN_L1,
          metaKeyLastBlock: "l1_last_block",
          confirmations: CFG.L1_CONFIRMATIONS,
        });

        lastScanAt = loopStart;
      }

      // 2) Process due jobs
      const jobs = jobGetDue(db, 25);

      for (const job of jobs) {
        const t = nowMs();

        // Terminal guard
        if (job.attempts >= CFG.MAX_RETRIES && job.status !== "failed_terminal") {
          jobUpdate(db, job.id, { status: "failed_terminal", updated_at: t });
          continue;
        }

        // Step A: fetch Iris (if missing message/attestation)
        if (!job.iris_message || !job.iris_attestation) {
          const age = t - job.first_seen_at;

          const r = await irisPollByTxHash(job.source_domain, job.source_tx_hash);

          if (r.state === "rate_limited") {
            jobUpdate(db, job.id, {
              status: "iris_pending",
              next_run_at: t + Math.max(10_000, CFG.IRIS_POLL_MS),
              updated_at: t,
            });
            continue;
          }

          if (r.state === "error") {
            const attempts = job.attempts + 1;
            jobUpdate(db, job.id, {
              status: attempts >= CFG.MAX_RETRIES ? "failed_terminal" : "failed_retry",
              attempts,
              last_error: r.error ?? "Iris error",
              next_run_at: t + Math.min(600_000, 10_000 * Math.pow(2, Math.min(attempts, 6))),
              updated_at: t,
            });

            if (!job.alerted_error) {
              await sendAlert(
                `Iris error (${job.kind})`,
                `tx=${job.source_tx_hash}\nerror=${r.error}`
              );
              jobUpdate(db, job.id, { alerted_error: 1, updated_at: nowMs() });
            }
            continue;
          }

          if (r.state === "pending") {
            // Alert if attestation pending too long
            if (age > attnPendingMs && !job.alerted_attestation) {
              await sendAlert(
                `Attestation pending too long (${job.kind})`,
                `tx=${job.source_tx_hash}\nageMinutes=${Math.floor(age / 60_000)}`
              );
              jobUpdate(db, job.id, { alerted_attestation: 1, updated_at: nowMs() });
            }

            jobUpdate(db, job.id, {
              status: "iris_pending",
              next_run_at: t + CFG.IRIS_POLL_MS,
              updated_at: t,
            });
            continue;
          }

          // complete
          jobUpdate(db, job.id, {
            status: "iris_complete",
            iris_message: r.message!,
            iris_attestation: r.attestation!,
            iris_event_nonce: r.eventNonce ?? null,
            next_run_at: t,
            updated_at: t,
          });
          continue;
        }

        // Step B: if relay disabled, only monitor + alert relay-pending
        if (!CFG.RELAY_ENABLED) {
          const ageFromSeen = t - job.first_seen_at;
          if (ageFromSeen > relayPendingMs && !job.alerted_relay) {
            await sendAlert(
              `Relay disabled / pending (${job.kind})`,
              `tx=${job.source_tx_hash}\nstatus=${job.status}\nageMinutes=${Math.floor(ageFromSeen / 60_000)}`
            );
            jobUpdate(db, job.id, { alerted_relay: 1, updated_at: nowMs() });
          }

          jobUpdate(db, job.id, { next_run_at: t + 30_000, updated_at: t });
          continue;
        }

        // Step C: submit destination tx if not submitted
        if (!job.dest_tx_hash && job.status === "iris_complete") {
          try {
            if (job.kind === "deposit") {
              const tx = await exec.finalize(job.iris_message, job.iris_attestation);
              jobUpdate(db, job.id, {
                status: "relaying",
                dest_chain: "l1",
                dest_tx_hash: tx.hash,
                next_run_at: t + CFG.RECEIPT_POLL_MS,
                updated_at: t,
              });
              console.log(`[deposit] finalize submitted: ${tx.hash} (src ${job.source_tx_hash})`);
            } else {
              const tx = await mt.receiveMessage(job.iris_message, job.iris_attestation);
              jobUpdate(db, job.id, {
                status: "relaying",
                dest_chain: "l2",
                dest_tx_hash: tx.hash,
                next_run_at: t + CFG.RECEIPT_POLL_MS,
                updated_at: t,
              });
              console.log(`[withdraw] receiveMessage submitted: ${tx.hash} (src ${job.source_tx_hash})`);
            }
          } catch (e: any) {
            if (isAlreadyProcessedLike(e)) {
              jobUpdate(db, job.id, {
                status: "already_processed",
                updated_at: nowMs(),
                last_error: String(e?.shortMessage ?? e?.message ?? e),
              });
              console.log(`[${job.kind}] already processed (ok): ${job.source_tx_hash}`);
              continue;
            }

            const attempts = job.attempts + 1;
            const errMsg = String(e?.shortMessage ?? e?.message ?? e);

            jobUpdate(db, job.id, {
              status: attempts >= CFG.MAX_RETRIES ? "failed_terminal" : "failed_retry",
              attempts,
              last_error: errMsg,
              next_run_at: t + Math.min(600_000, 10_000 * Math.pow(2, Math.min(attempts, 6))),
              updated_at: t,
            });

            if (!job.alerted_error) {
              await sendAlert(
                `Relay submit failed (${job.kind})`,
                `tx=${job.source_tx_hash}\nerror=${errMsg}`
              );
              jobUpdate(db, job.id, { alerted_error: 1, updated_at: nowMs() });
            }
          }

          continue;
        }

        // Step D: check destination receipt if submitted
        if (job.dest_tx_hash && job.status === "relaying") {
          const provider = job.dest_chain === "l1" ? pL1 : pL2;
          const rcpt = await provider.getTransactionReceipt(job.dest_tx_hash);

          if (!rcpt) {
            // pending receipt -> alert if too long
            const ageFromSeen = t - job.first_seen_at;
            if (ageFromSeen > relayPendingMs && !job.alerted_relay) {
              await sendAlert(
                `Relay pending too long (${job.kind})`,
                `srcTx=${job.source_tx_hash}\ndestTx=${job.dest_tx_hash}\nageMinutes=${Math.floor(ageFromSeen / 60_000)}`
              );
              jobUpdate(db, job.id, { alerted_relay: 1, updated_at: nowMs() });
            }

            jobUpdate(db, job.id, { next_run_at: t + CFG.RECEIPT_POLL_MS, updated_at: t });
            continue;
          }

          if (rcpt.status === 1) {
            jobUpdate(db, job.id, { status: "relayed", updated_at: t });
            console.log(`[${job.kind}] relayed OK: src=${job.source_tx_hash} dest=${job.dest_tx_hash}`);
            continue;
          }

          // status==0 => reverted on-chain
          const attempts = job.attempts + 1;
          jobUpdate(db, job.id, {
            status: attempts >= CFG.MAX_RETRIES ? "failed_terminal" : "failed_retry",
            attempts,
            last_error: `Dest tx reverted: ${job.dest_tx_hash}`,
            next_run_at: t + Math.min(600_000, 10_000 * Math.pow(2, Math.min(attempts, 6))),
            updated_at: t,
          });

          if (!job.alerted_error) {
            await sendAlert(
              `Destination tx reverted (${job.kind})`,
              `srcTx=${job.source_tx_hash}\ndestTx=${job.dest_tx_hash}`
            );
            jobUpdate(db, job.id, { alerted_error: 1, updated_at: nowMs() });
          }

          continue;
        }

        // Default: schedule next tick
        jobUpdate(db, job.id, { next_run_at: t + 10_000, updated_at: t });
      }
    } catch (e) {
      console.error("Worker loop error:", e);
    }

    // sleep small (avoid tight loop)
    const elapsed = nowMs() - loopStart;
    const nap = Math.max(500, 1500 - elapsed);
    await sleep(nap);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
