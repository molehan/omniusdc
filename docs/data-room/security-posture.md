# Security Posture (Template)

## Principles

- Safety-first launch: conservative parameters, low TVL cap, gradual ramp.
- Minimize trust and privilege: no admin EOA, timelock-admined configs, pause-only guardian.
- Constrained execution: no arbitrary calls in cross-chain finalize or withdrawal execution.
- Defense-in-depth: code review, testing, monitoring, and incident response.

## Threat Model (V1)

- Smart contract bugs (vault, router, strategy integration)
- Strategy protocol failure (loss, withdrawal gating)
- Cross-chain message handling errors (hookData parsing, replay edges)
- Operational risks (key compromise, misconfigurations, relayer issues)
- USDC issuer risk (explicitly out of scope, but monitored)

## Testing Strategy

- Unit tests (Foundry)
- Invariant / property tests (to be added)
- Fork tests (to be added)
- Static analysis (optional early, required before mainnet TVL)

## Audits

- Audit targets: core contracts (USDCVault, StrategyManager, RiskManager, Router, Executor)
- External audits: TBD
- Public audit artifacts: TBD

## Monitoring & Incident Response

- Onchain monitoring for abnormal events and cap violations
- Alerting on fast-mode failures and finalization delays
- Incident runbook: TBD

## Disclosure Policy

See `SECURITY.md`.
