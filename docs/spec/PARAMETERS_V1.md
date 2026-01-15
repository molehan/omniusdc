# Parameters (V1 Defaults)

These are default values, adjustable later via **Timelock**.

## Fees (V1 Defaults)

- Deposit fee: `0`
- Withdraw fee: `0`
- Performance fee: `0` (V1 default for a clean launch; may be enabled later)
- Management fee: `0`

Any future fees must be explicitly documented and emitted via clear events. No hidden fees.

## Limits (V1 Defaults)

### User Limits
- `minDeposit`: 10 USDC
- `maxDepositPerTx`: 250,000 USDC

### TVL / Exposure
- `tvlCap`: 2,000,000 USDC (initial)
- `perStrategyCapBps`: 7000 (70%) default (may be set lower initially)

### Buffer Policy
- `bufferTargetBps`: 750 (7.5%)
- `bufferMinBps`: 500 (5.0%) — allocations halted below this
- `bufferMaxBps`: 1500 (15.0%) — allocations permitted above target until max is reached

### Optional Withdraw Rate Limit
- `maxDailyWithdraw`: 0 (disabled by default; 0 = disabled)

## CCTP Policy (V1 Defaults)

### Standard
- `standardMinFinalityThreshold`: 2000

### Fast (If Enabled)
- `fastMaxMinFinalityThreshold`: 1000
- `fastWithdrawCapPerTx`: 50,000 USDC
- `fastWithdrawCapPerDay`: 250,000 USDC
- Additional constraint: also limited by available CCTP **global allowance**.

If Fast fails due to allowance/threshold constraints, fallback to Standard is allowed when `mode=FAST`.

## Timelock / Admin Policy

- **Timelock delay (V1 decision):** 72 hours
- Timelock controls:
  - caps/limits/fees (if enabled)
  - strategy whitelist changes
  - role assignment (Guardian/Strategist)
- Guardian:
  - pause only (no fund transfer authority)
- Strategist:
  - allocate/deallocate only within caps and when not paused

## Pausing Defaults

- `pauseDeposits`: false
- `pauseWithdraws`: false
- `pauseAllocations`: false

Emergency preference order:
1) pause deposits
2) pause new allocations
3) keep withdrawals enabled where feasible
