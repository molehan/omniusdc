# Risk Policy (Data Room Template)

## V1 Risk Philosophy

- Target: low-risk USDC yield, not marketing APY.
- Avoid leverage and complex market-neutral structures.

## Hard Rules (V1)

- USDC only
- CCTP V2 only
- No leverage / looping / delta-neutral
- 1 strategy (max 2) + L1 buffer
- Caps: TVL cap + per-strategy cap
- Pause: deposits/allocations can be paused quickly

## Mitigations

- Conservative parameters (TVL cap, buffer target)
- Strategy admission criteria (maturity, audits, withdrawal liquidity)
- Transparent loss handling and disclosure

## Reference

Canonical risk specification lives in `docs/spec/RISK_POLICY.md`.
