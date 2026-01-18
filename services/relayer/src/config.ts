import "dotenv/config";

// دالة للتحقق من وجود المتغيرات الإلزامية
function req(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env var: ${name}`);
  return v;
}

// دالة لتحويل القيم النصية إلى أرقام مع قيمة احتياطية
function asInt(name: string, fallback: number): number {
  const v = process.env[name];
  if (!v) return fallback;
  const n = Number(v);
  if (!Number.isFinite(n)) throw new Error(`Invalid number for ${name}: ${v}`);
  return n;
}

/**
 * دالة التحقق من صحة هاش المعاملة (المفقودة التي تسببت في الخطأ)
 */
export function assertTxHash(hash: string): string {
  if (!hash || !/^0x([A-Fa-f0-9]{64})$/.test(hash)) {
    throw new Error(`Invalid transaction hash: ${hash}`);
  }
  return hash;
}

export const CFG = {
  RPC_L1: req("RPC_L1"),
  RPC_L2: req("RPC_L2"),
  PK_L1: req("PK_L1"),
  PK_L2: req("PK_L2"),

  IRIS_BASE: req("IRIS_BASE"),

  L1_EXECUTOR: req("L1_EXECUTOR"),
  L1_WITHDRAW_ROUTER: req("L1_WITHDRAW_ROUTER"),
  L2_GATEWAY: req("L2_GATEWAY"),

  CCTP_MESSAGE_TRANSMITTER_V2: req("CCTP_MESSAGE_TRANSMITTER_V2"),

  DOMAIN_L1: asInt("DOMAIN_L1", 0),
  DOMAIN_L2: asInt("DOMAIN_L2", 6),

  DB_PATH: process.env.DB_PATH ?? "./relayer.sqlite",

  L1_CONFIRMATIONS: asInt("L1_CONFIRMATIONS", 3),
  L2_CONFIRMATIONS: asInt("L2_CONFIRMATIONS", 3),
  BLOCK_BATCH: asInt("BLOCK_BATCH", 2000),
  SCAN_INTERVAL_MS: asInt("SCAN_INTERVAL_MS", 10000),
  IRIS_POLL_MS: asInt("IRIS_POLL_MS", 5000),
  RECEIPT_POLL_MS: asInt("RECEIPT_POLL_MS", 7000),
  MAX_RETRIES: asInt("MAX_RETRIES", 12),

  ALERT_WEBHOOK_URL: process.env.ALERT_WEBHOOK_URL ?? "",
  ALERT_WEBHOOK_KIND: process.env.ALERT_WEBHOOK_KIND ?? "slack",
  ALERT_ATTESTATION_PENDING_MIN: asInt("ALERT_ATTESTATION_PENDING_MIN", 30),
  ALERT_RELAY_PENDING_MIN: asInt("ALERT_RELAY_PENDING_MIN", 10),

  RELAY_ENABLED: (process.env.RELAY_ENABLED ?? "1") !== "0",
};
