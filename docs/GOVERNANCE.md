# Governance (V1)

## Summary

OmniUSDC V1 is designed with **no admin EOA** and no privileged path that can arbitrarily withdraw user funds.

Administrative authority is split across:

- **Safe Multisig** (human governance, signer security)
- **Timelock** (onchain delay for sensitive actions)
- **Guardian** (pause-only for emergencies)
- **Strategist** (bounded allocations within RiskManager limits)

V1 ships with **no governance token** and no onchain voting. Changes are executed via multisig + timelock.

## Onchain Entities

### Safe Multisig

The Safe is the ultimate control surface for the protocol.

**Responsibilities**
- Owns and administers the Timelock.
- Adds/removes role holders (Guardian, Strategist) via Timelock.
- Approves strategy onboarding/removal via Timelock.
- Initiates migrations (deploying a new version and pausing old flows) if ever required.

**Key management requirements (baseline)**
- Minimum 3 signers, threshold 2/3 (or stronger).
- Hardware wallets required for all signers.
- Written operational runbooks for signer rotation and incident response.

### Timelock

The Timelock is the **DEFAULT_ADMIN** of sensitive contracts in V1.

**Purpose**
- Enforce a public delay for risk parameter changes, strategy list changes, and role changes.

**V1 default delay**
- 72 hours (configurable via deployment, but must be documented publicly).

### Guardian

**Power:** pause-only.

**Scope**
- Pause deposits.
- Pause new allocations.
- Optionally pause withdrawals if strictly necessary (policy preference is to keep withdrawals enabled where feasible).

**Non-powers**
- Guardian cannot transfer assets or change caps.

### Strategist

**Power:** bounded allocation operations.

**Scope**
- Allocate/deallocate to whitelisted strategies **within RiskManager limits**.

**Non-powers**
- Strategist cannot add strategies, change caps, or move funds outside the vault/strategies.

## Contract Ownership & Roles (Target V1)

| Contract | Admin / Owner | Guardian | Strategist |
|---|---|---|---|
| USDCVault (ERC-4626) | Timelock | pause deposits/withdraws (if enabled) | none |
| StrategyManager | Timelock | pause allocations | allocate/deallocate |
| RiskManager | Timelock | (optional) pause switches | none |
| L1CCTPExecutor | Timelock (params only) | none | none |
| L1WithdrawRouter | Timelock (params only) | none | none |

Notes:
- Router/Executor should have no admin function that can route arbitrary calls.
- All role assignments are performed via Timelock.

## Action Matrix

| Action | Who proposes | Who executes | Timelock? |
|---|---:|---:|---:|
| Pause deposits | Guardian | Guardian | No |
| Pause new allocations | Guardian | Guardian | No |
| Unpause deposits/allocations | Safe (via Timelock) | Timelock | Yes |
| Adjust TVL cap / per-strategy cap / buffer | Safe | Timelock | Yes |
| Add/remove a strategy from whitelist | Safe | Timelock | Yes |
| Allocate/deallocate within caps | Strategist | Strategist | No |
| Replace Guardian / Strategist | Safe | Timelock | Yes |
| Deploy new version + migrate | Safe | Safe + Timelock (as needed) | Yes (for onchain changes) |

## Deployment & Handover Checklist (V1)

Before any public usage:

1. Deploy contracts.
2. Configure RiskManager parameters (conservative defaults).
3. Transfer `DEFAULT_ADMIN` to the Timelock.
4. Set Guardian and Strategist roles (via Timelock).
5. Verify there is **no admin EOA** retaining privileges.
6. Confirm pausing works and does not allow privileged withdrawals.
7. Publish contract addresses and role assignments.

## Emergency Principles

- Prefer **pause deposits and allocations first**.
- Keep withdrawals enabled where feasible.
- If withdrawals must be restricted due to external constraints, disclose immediately and provide a transparent mechanism (e.g., FIFO queue) and status reporting.
