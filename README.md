# Covenant

Covenant is a cross-chain liquidity backstop for the Reactive Omni Buildathon’s Every Second Counts track. Borrowers lock ETH on Unichain Sepolia. Lenders commit USDC on Base Sepolia. Reactive Lasna coordinates activation and can trigger a bounded repayment of a distressed Base position. Base records Covenant debt only after that repayment succeeds.

**M0 CONDITIONALLY APPROVED — BLOCKERS REQUIRE RESOLUTION**
**M1-B LOCAL TRANSPORT READY — DEPLOYMENT AUTHORIZATION REQUIRED**

The deterministic lending harness is the proposed testnet demo target. M1-B adds isolated, non-financial Omni transport probes for Unichain → Base, Base → Unichain and Base → Base through Lasna. Local tests, read-only RPC checks and deployment simulations pass; no transaction has been broadcast. The live Reactive lifecycle, third-party Circle USDC repayment, and lender recovery across chains have separate verification gates. See the [network evidence](docs/NETWORK_VERIFICATION.md), [transport verification](docs/TRANSPORT_VERIFICATION.md) and [roadmap](docs/ROADMAP.md).

| Specification | Documents |
|---|---|
| Scope and design | [Product](docs/PRODUCT.md), [Architecture](docs/ARCHITECTURE.md), [Financial model](docs/FINANCIAL_MODEL.md) |
| Safety and execution | [State machines](docs/STATE_MACHINE.md), [Invariants](docs/INVARIANTS.md), [Threat model](docs/THREAT_MODEL.md), [Reactive integration](docs/REACTIVE_INTEGRATION.md) |
| Validation | [Network verification](docs/NETWORK_VERIFICATION.md), [Transport verification](docs/TRANSPORT_VERIFICATION.md), [Test plan](docs/TEST_PLAN.md), [Demo](docs/DEMO.md), [Roadmap](docs/ROADMAP.md) |

The Foundry scaffold pins Solidity 0.8.29 as the initial Omni-compatible baseline. M1-A adds local collateral and liquidity vaults and tests. M1-B adds isolated transport probes under `src/reactive/transport/`. Use Foundry 1.10.0 and run `forge fmt --check`, `forge build --force` and `forge test -vvv` from the repo root. The collateral vault permanently locks deposits in this version. The contracts are for isolated local tests. Public and real-value deployments are prohibited; live testnet transport requires explicit authorization.
