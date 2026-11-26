# Covenant frontend

Run `pnpm install --frozen-lockfile` then `pnpm dev` from this directory. Use Node 24 and pnpm 12. Run `pnpm typecheck`, `pnpm lint`, `pnpm test`, and `pnpm build` for the M7-A checks.

## Application structure

- `app/` contains the public entry point, the dashboard shell, and route loading UI.
- `components/dashboard.tsx` supplies the overview, agreement register and detail, liquidity, collateral, activity, and demonstration views. The agreement creation route describes the future origination flow.
- `components/ui.tsx` contains shared financial and status components. `wallet.tsx` handles injected wallet consent, account updates, and chain identification.
- `lib/data.ts` defines the provider and view-state contracts. `lib/demo.ts` owns the pre-execution scenario and `lib/source.ts` selects the provider at the server boundary. Token values use integer base units.
- `lib/chains.ts` identifies Base Sepolia and Unichain Sepolia for wallet identification and Lasna for read-only monitoring.
- `lib/abis/reads.json` contains read methods and event definitions copied from compiled Foundry artifacts. Run `pnpm generate:abis` after building the relevant contracts from a reviewed revision.

## Configuration

Demonstration mode is the default. Select **View live testnet** to request the isolated live provider. Without a reviewed manifest the page displays **Deployment unconfigured**. A configured manifest produces **Live network data unavailable** until a live provider is implemented. Live mode never substitutes fixture data.

Optionally set the server-only `COVENANT_REVIEWED_MANIFEST` to the JSON contents of a reviewed M4 manifest. Its `networks` objects follow the [M4 template](../deployments/m4.integrated.example.json). The parser checks revision presence, expected chain IDs, and required nonzero addresses. Review provenance, runtime bytecode, deployment receipts, and contract bindings independently before configuring any live integration. The template itself does not enable live data. Keep credentials out of manifests and client environment variables.

M7-A wallet consent requests an account and reads its chain. There are no signing, switching, write, or transaction submission flows. The guided demonstration models a callback request with no confirmed execution. Outstanding principal in that snapshot is zero. The walkthrough describes the expected post-repayment values separately.
