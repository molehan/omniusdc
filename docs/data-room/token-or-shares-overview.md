# Token or Shares Overview (V1)

## Does OmniUSDC Have a Token?

**No.** V1 ships with **no governance token**.

## What Users Hold

Users receive **vault shares** (ERC-4626) on Ethereum Mainnet (L1).

- Shares represent a pro-rata claim on the vault’s USDC assets (buffer + strategy positions).
- Shares are ERC20 and may support EIP-2612 permit for better UX.

## Cross-Chain UX

- Deposits originate on the chosen L2, but the resulting shares are minted on L1 to the user’s specified `ownerL1`.
- Withdrawals are initiated by a user-signed EIP-712 intent and executed on L1, then bridged back to L2 via CCTP V2.

## Why No Token in V1

- Reduces complexity and risk.
- Avoids governance-token attack surfaces and regulatory ambiguity.
- Keeps incentives aligned with a conservative, safety-first launch.

## Future Considerations (Non-Commitment)

Any future token or incentive design (if ever pursued) would be treated as a separate product decision with its own risk and governance process.
