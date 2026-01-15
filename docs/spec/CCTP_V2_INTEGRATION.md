# CCTP V2 Integration (V1)

## Policy: V2 Only

- V1 integrates **Circle CCTP V2 only**.
- No integration with legacy CCTP V1.
- Rationale: V2 is canonical, and legacy V1 is expected to enter phase-out beginning **July 31, 2026**.

## Standard vs Fast

### Standard Mode (Default)
- Default `minFinalityThreshold = 2000` for stronger safety.
- Used for all transfers unless Fast is selected and permitted.

### Fast Mode (Optional)
Fast is permitted only when:
- `minFinalityThreshold <= 1000`, and
- within Fast caps (per-tx and per-day), and
- sufficient **global allowance** exists for Fast transfers.

Fast availability is not guaranteed; allowance may be depleted or change.

## Fallback Behavior (V1 Decision)

- If user selects `FAST`:
  - attempt Fast
  - if Fast reverts due to allowance/threshold constraints, **fallback to Standard**
- If user selects `STANDARD`:
  - do not attempt Fast

Implementation preference (V1):
- fallback within the same transaction when possible (e.g., `try/catch` around the Fast attempt).

## Message Expiry and Re-attestation

CCTP messages may be subject to expiry / attestation validity windows.

V1 operational behavior:
- If finalize succeeds with a valid attestation: proceed normally.
- If attestation is expired/invalid:
  - obtain a refreshed attestation (re-attest) and retry finalize.

Finalize remains permissionless; any relayer can perform these steps.

## HookData Encoding (V1)

### ABI Encoding

- `uint8  version = 1`
- `uint8  action`:
  - `1 = DEPOSIT`
- `address ownerL1`
- `uint64  clientNonce` (UI correlation)
- `bytes32 referral` (optional; `0x0` if unused)

Conceptual:
`abi.encode(uint8(1), uint8(1), ownerL1, clientNonce, referral)`

### Parsing Rules
- Reject any `version != 1`
- Reject any action not equal to `DEPOSIT`
- `ownerL1` is the beneficiary for the vault deposit on L1

## Finalization (Permissionless, Constrained)

- `L1CCTPExecutor.finalize(message, attestation)` must be permissionless.
- Internal execution must be constrained:
  - no arbitrary calls
  - only the known path: receiveMessage → parse hookData → vault.deposit

## Safety Requirements

- Use official CCTP V2 contracts per chain.
- Emit and index `messageHash = keccak256(message)` for correlation.
- Do not accept hookData formats that could be abused to route calls elsewhere.
- Maintain clear runbooks for relayers and operators (especially for expiry/reattest scenarios).
