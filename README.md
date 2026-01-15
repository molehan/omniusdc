# OmniUSDC Monorepo

This repository is a **monorepo** for the OmniUSDC V1 system.

## Structure

- `contracts/` — Solidity smart contracts (Foundry)
- `services/` — Node.js / TypeScript services (relayer, attestation, monitoring)
- `apps/` — Frontend application(s)
- `docs/` — Protocol specifications, risk, and operations
- `.github/workflows/` — CI pipelines (GitHub Actions)

## Quickstart

### Contracts (Foundry)

```bash
cd contracts
forge fmt
forge build
forge test
```

### Services (TypeScript)

```bash
cd services
npm ci
npm run lint
npm run build
```

## Governance & Security

- Governance model: `docs/GOVERNANCE.md`
- Vulnerability disclosure policy: `SECURITY.md`
- Data-room templates: `docs/data-room/`

## CI

GitHub Actions runs on every PR:

- `forge fmt --check`
- `forge build`
- `forge test`
- TypeScript lint/build (if present)

