# Relayer Alerts Runbook (RC)

## 1) Attestation Pending Too Long
**Symptom:** Job stuck in `iris_pending` for more than X minutes.

**Checks:**

 1.   Verify that the burn tx was successful on the Explorer (status=1).
 2.   Manual Check:
        GET `${IRIS_BASE}/v2/messages/{domain}?transactionHash={txHash}`
3.    If it returns 404 for an extended period:
  -      This means Iris has not produced the attestation yet, or there is a service delay.

**Actions:**

-    Wait / Reduce polling frequency.
-    If you have the eventNonce and need to force finality or re-request the attestation:
        POST `${IRIS_BASE}/v2/reattest/{eventNonce}`

---        

## 2) Relay Pending Too Long
**Symptom:** Iris status is complete, but the destination transaction was not sent or confirmed.

**Checks:**

1.    Is RELAY_ENABLED=1 `?
2.    Does the Private Key (PK) have sufficient ETH for gas on the destination network?
3.    Is the RPC rate-limited?
4.    Verify the contract addresses:
-        Deposit => Must call finalize on L1_EXECUTOR.
-        Withdraw => Must call receiveMessage on MessageTransmitterV2 on L2.

**Actions:**

-    Restart the Worker.
-    Execute a manual relay for diagnostic purposes:
        `npm run relay:l2-to-l1 -- <txHash>` `OR npm run relay:l1-to-l2 --` <txHash>`

## 3) finalize Reverted
**Common causes:**

-    destinationCaller mismatch: (Your design requires finalization via the Executor).
-    Wrong Executor address.
-    Message already processed: Returns "Nonce already used" (This can be ignored/considered OK).

## 4) receiveMessage Reverted (NOT already processed)
**Common causes:**

-    Wrong MessageTransmitter address or incorrect chain.
-    Attestation mismatch: Attestation does not match the message.
-    Insufficient gas.