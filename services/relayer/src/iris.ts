import { setTimeout as sleep } from "node:timers/promises";

export type IrisMessageV2 = {
  message: string;          // 0x...
  attestation?: string;     // 0x...
  eventNonce?: string;      // "9682" ...
  status: string;           // "complete" | ...
  cctpVersion?: number;     // 2
  decodedMessage?: unknown;
  decodedMessageBody?: unknown;
};

export async function getMessagesV2ByTxHash(
  irisBase: string,
  sourceDomainId: number,
  txHash: string
): Promise<IrisMessageV2[] | null> {
  const url = `${irisBase}/v2/messages/${sourceDomainId}?transactionHash=${txHash}`;
  const res = await fetch(url);

  // 404 أثناء انتظار الـ attestation أمر طبيعي في تدفقات Circle. :contentReference[oaicite:5]{index=5}
  if (res.status === 404) return null;

  // Rate limit: استخدم Retry-After إن وُجد.
  if (res.status === 429) {
    const ra = res.headers.get("retry-after");
    const waitMs = ra ? Math.max(1000, Number(ra) * 1000) : 5000;
    await sleep(waitMs);
    return null;
  }

  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`Iris HTTP ${res.status}: ${text}`);
  }

  const data = await res.json();
  return (data?.messages ?? []) as IrisMessageV2[];
}

export async function waitForCompleteMessageByTxHash(
  irisBase: string,
  sourceDomainId: number,
  txHash: string,
  { pollMs = 5000, maxAttempts = 240 } = {}
): Promise<IrisMessageV2> {
  for (let i = 0; i < maxAttempts; i++) {
    const msgs = await getMessagesV2ByTxHash(irisBase, sourceDomainId, txHash);

    if (msgs && msgs.length) {
      // API: ordered by ascending log index for a given txHash. :contentReference[oaicite:6]{index=6}
      const m = msgs[0];
      if (m.status === "complete" && m.attestation && m.message) return m;
    }

    await sleep(pollMs);
  }

  throw new Error("Timeout waiting for Iris attestation (status complete).");
}
