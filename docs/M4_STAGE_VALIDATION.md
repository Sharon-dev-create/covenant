# Stage-aware financial deployment validation

`script/check_m4_manifest.py` is an **offline operational preflight**, not an on-chain guard: neither Forge nor `DeployM4.s.sol` automatically calls it, and it cannot authenticate user approvals or prove that a later RPC state matches a recorded snapshot. The operator must independently verify the authorization, chain, latest/pending nonce, signer balance, code, fee quote and exact command immediately before any send. No secret is needed or permitted in the public manifests.

The existing commands retain their full checks without a stage-specific exception:

```bash
python3 script/check_m4_manifest.py deployments/m4.financial-readiness.proposed.json plan
python3 script/check_m4_manifest.py deployments/m4.financial-readiness.proposed.json wired
```

Both full modes are distinct from Stage 3A and remain gated by approved callback gas, reserves, financial ceilings, complete role/policy evidence, approvals and, for wired mode, actual deployed addresses. The current full manifest must fail at `callback gas not approved`. Stage 3A cannot authorize or mark the full system ready.

The narrowly defined stage command is:

```bash
python3 script/check_m4_manifest.py deployments/m4e2.stage3a.pending.json stage3a
```

This reads the fixed operational, Stage 1 and Stage 2 evidence manifests, the compiled `out/DemoMarket.sol/DemoMarket.json` artifact, and a public unsigned Forge dry-run `deployments/m4e2.stage3a.simulation.json`. It uses the local Foundry `cast` executable to recompute CREATE address and bytecode hash. Checks are defined by the validator, not manifest-provided lists: exact Stage 3A identifier, chain, signer, operator, token, constructor, one zero-value CREATE and exact compiled initcode/arguments, one signer-specific simulation, prior receipt and runtime evidence, matching nonce 15, predicted address and recorded empty code, explicit scoped authorization, 60000000000000 wei limit, estimated execution/data/operator fees, zero other-chain spending/funding and no financial actions. It prints the canonical fixed `DeployM4.deployMarket(address,address)` command; compare it to the actual operator command. It does not check current RPC state, create an on-chain restriction, or enforce L1 fee caps.

Stage 3B requires its own separately designed validation for verified market and source vault, reserved signer nonce sequence, predicted outer/nested/manager/vault identities, verifier and adapter immutable manager pins, full remaining fork simulations, receipt-by-receipt verification, a separately authorized bounded expenditure and explicit recovery procedure for nonce drift. Stage 3B now has explicit preparation and broadcast-readiness modes described below. Full `plan`/`wired` remains necessary for the complete system and activation; no stage pass changes those rules. `DeployM4.s.sol` is not a validator wrapper and can be invoked directly, so this is an operational control, not technical enforcement.


## Stage 3B modes

`python3 script/check_m4_manifest.py deployments/m4e2.stage3b.pending.json stage3b-plan` verifies the fixed three-creation sequence, prerequisite receipts, CREATE predictions, exact constructor arguments, code hashes, recorded fork trace/runtime checks, initial signer nonce, scope and itemized proposed cost envelope. Its pass means preparation only; it does not grant broadcast permission. `stage3b-broadcast` applies the same checks and additionally requires explicit unconsumed sequence approval and approved aggregate and per-transaction caps matching the plan; the present file deliberately fails that check. Neither mode implies full financial readiness. As with Stage 3A, these are offline record checks; the script does not authenticate approvals or independently verify current RPC state, and DeployM4 can be invoked independently. Recheck every network state and receipt before each operator action; stop on nonce drift after a manager pin. Stage mode acceptance is not an on-chain enforcement mechanism.
