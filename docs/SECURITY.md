# Security Policy

## Reporting a Vulnerability

If you believe you have found a security vulnerability, please report it **privately**.

**Primary channel (recommended):**
- Email: `security@YOUR_DOMAIN` (replace with your project alias)

**Optional (if you have it):**
- Bug bounty platform (e.g., Immunefi) link: `TBD`
- PGP public key: `TBD`

Please include:
- a clear description of the issue and impact
- affected contract(s)/commit hash
- steps to reproduce (PoC if possible)
- suggested remediation (if available)

## Coordinated Disclosure

- **Do not** publicly disclose the issue (including on social media, Discord, or GitHub Issues) before contacting us.
- We will acknowledge receipt within **72 hours**.
- We will provide a severity assessment and a remediation plan/timeline as soon as reasonably possible.

## Response Targets (V1 Defaults)

- Acknowledgement: within 72 hours
- Triage: within 7 days
- Fix development: depends on severity; critical issues are prioritized immediately

## Scope

In scope:
- smart contracts under `contracts/`
- relayer/monitoring services under `services/`
- critical deployment and configuration issues (governance, timelock, role setup)

Out of scope:
- best-practice suggestions without a clear security impact
- issues requiring physical access to a signer’s device

## Safe Harbor

We will not pursue legal action against researchers who:
- act in good faith
- avoid privacy violations and data destruction
- do not exploit the vulnerability beyond proof of concept
- report issues privately and allow a reasonable fix window
