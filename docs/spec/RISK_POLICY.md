# Risk Policy (V1)

## Risk Philosophy (V1)

V1 targets **low-risk, operationally robust USDC yield**, not “marketing APY.”
The design prioritizes:
- auditability and simplicity
- explicit caps and risk limits
- withdrawal liquidity via buffer
- emergency controls (pause) to reduce blast radius

## Prohibited in V1 (Hard Bans)

- **Leverage / borrowing / looping**
- **Delta-neutral / derivatives (perps/options)**
- **Complex rehypothecation / restaking chains**
- **Strategies requiring complex oracle stacks** (avoid wherever possible)
- **Excessive strategy count** (V1: 1 strategy, maximum 2)

## Risk Controls (Hard Rules)

### 1) L1 Buffer
- Maintain a buffer ratio: `bufferTargetBps` (typically 500–1000 bps).
- Purpose:
  - satisfy withdrawals without immediate strategy unwind
  - reduce the likelihood of withdrawal gating under stress
- Policy:
  - if buffer falls below a minimum threshold, new allocations are halted until buffer is restored.

### 2) TVL Cap
- Start with a conservative `tvlCap`.
- Increase gradually via timelock after operational validation.
- Goal: reduce initial blast radius.

### 3) Per-Strategy Cap
- Each strategy is capped to a maximum share of TVL.
- Goal: limit concentration risk and allow staged de-risking.

### 4) Fast Mode Limits
Fast is an operational optimization, not a guarantee:
- enforce per-tx and per-day limits
- enforce allowed `minFinalityThreshold` bounds
- respect allowance constraints
- allow fallback to Standard when Fast is not available (without changing recipient/amount)

### 5) Emergency Pause
Guardian can:
- pause deposits
- pause new allocations
- keep withdrawals enabled where feasible

If immediate withdrawals become constrained (e.g., illiquid strategy unwind):
- enable a transparent withdrawal queue mechanism:
  - FIFO processing
  - public status/metrics
  - clear communication

## Strategy Admission Criteria (V1)

A strategy must meet a minimum threshold for:

1. protocol maturity, audits, and time-in-production
2. credible withdrawal liquidity / exit path
3. minimal reliance on privileged admin keys (where feasible)
4. clearly documented failure modes
5. observable and monitorable health metrics

## Monitoring & Operations (V1)

Monitor:
- NAV / share price
- buffer ratio
- cap utilization
- CCTP finalization success rates
- withdrawal patterns and stress signals

Alert on:
- cap violations or near-violations
- buffer below critical thresholds
- recurring Fast failures due to allowance
- abnormal strategy losses or deviations

## Loss Handling Policy (V1)

If a strategy loss occurs:

1. immediately halt new allocations to the affected strategy
2. disclose within 24 hours (cause, scope, impact)
3. update NAV/share price reflecting realized/confirmed losses
4. if any compensation plan exists, state it explicitly (no promises in V1)

## Explanation: “No leverage + caps + buffer + pause”

- **No leverage:** avoids liquidation cascades and amplified downside; losses are bounded to strategy performance.
- **Caps:** contain blast radius during launch and reduce the maximum loss from any single failure mode.
- **Buffer:** improves withdrawal liquidity and reduces forced unwind under adverse conditions.
- **Pause:** enables rapid containment during incidents while preserving clarity and control.
