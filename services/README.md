# Services

This folder hosts Node.js/TypeScript services.

Typical components (V1):

- **Relayer**: submits `L1CCTPExecutor.finalize(...)` and `L1WithdrawRouter.execute(...)` transactions.
- **Attestation**: monitors CCTP messages and fetches attestations.
- **Monitoring**: metrics, alerting, and operational dashboards.

For Step 1, this is a minimal scaffold to keep CI green.
