# Demo

Use labelled deterministic market and oracle fixtures. Base vault and market transfer Circle test USDC on live Base if the authorized run has access to that asset. Local tests use a six-decimal test token. The market fixture must actually receive repayment and reduce the bound borrower's recorded liabilities.

1. Register a draft with 1 ETH collateral, $2,000 ETH test mark, a signed 500 USDC cap, 50% LTV and a 200 USDC policy repayment maximum. Borrower locks 1 test ETH on Unichain. Lender supplies 600 test USDC on Base. Independent finalized lock evidence and Live Lasna lock callback cause activation. Show 100 free, 500 reserved, zero principal.
2. Seed harness position with 800 USDC debt and $960 in liquidation-adjusted market collateral, for health 1.20. Publish a distinct market shock setting liquidation-adjusted market collateral to $840, health 1.05, with Covenant collateral mark still $2,000. Manager records risk when health is at most 1.10 and the position is still above the fixture’s liquidation boundary of 1.00.
3. Lasna routes the risk callback; only if conditions still hold, 200 USDC net repayment reduces market debt to 600 and increases health to 1.40. Vault has 400 free, zero reserved. Covenant principal is 200.
4. In the deterministic zero-elapsed unit fixture, repay 75 then 125 USDC. In timed live runs use exact interest-inclusive payoff and show receipt allocation. Base closes and authorizes release. After finality proof and Lasna callback the borrower claims ETH on Unichain.
5. Repeat with forced market revert and a duplicate risk callback. Confirm unchanged principal and balances on failure, then retry once after restoring normal execution. Confirm no second draw on duplicate delivery.

## Latency

Compare autonomous callback and manual execution against equivalent independent positions and the same risk event. Use the same Base executor rules, gas policy, risk levels and submitter region where applicable. Manual flow includes alert receipt, wallet confirmation, and submission by a human. Also record a scripted public executor baseline to isolate human delay. Log UTC wall-clock timestamps from one synchronized observer and chain transaction evidence, with clock resolution and polling interval.

Record risk inclusion, alert/observation, Lasna reaction and callback request, Base repayment inclusion, and Base safe/finalized confirmation. Measure inclusion-to-inclusion, time to finality, and gas cost for each path, plus lock/release finality as separate lifecycle legs. Target at least 20 paired attempts if feasible, report successful count, p50 and p95 for each path, paired time difference and deadline hit rate, and publish failures/timeouts separately. Declare the risk deadline before trials. A meaningful track result is lower median latency and a higher fraction inside the chosen window. M0 has no measured latency or demonstrated savings.
