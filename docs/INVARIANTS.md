# Invariants

For each lender or agreement, all buckets are integer and nonnegative. Across the Base vault, measured managed USDC balance equals sum(free + reserved); unsolicited token surplus is segregated and cannot be counted twice. Adapter balances and market allowances return to baseline after every successful draw. No external callback can interleave state mutation during a draw or repayment.

- Reservation conservation. Summed per-agreement reserved equals summed per-lender reserved. Each reservation has one corresponding active agreement. Only free funds can be withdrawn, with cash delta exactly equal to actual withdrawal.
- Principal conservation. `principal = cumulative verified draws - principal repaid - principal recovered - explicitly written-off principal`. The last two terms stay zero in M1. At most one positive draw per agreement. Reservation alone adds zero principal.
- Draw boundedness. For each successful draw, actual asset spend equals adapter-confirmed applied repayment and newly booked principal. It is positive and within the current LTV headroom, contractual cap, reservation, market debt and purpose cap. Fixed borrower, token, adapter and market are committed in terms. No extra allowances or arbitrary call data.
- Lifecycle. `closed => principal == interest == reserved == 0` in M1. Closed never reopens. If active, the source lot has authenticated finalized lock evidence and matching terms. Expiry cannot erase debt. For each lot, claimable/released implies a matching irreversible Base terminal authorization and finalized proof, with no liquidation award in M1.
- Uniqueness. Each agreement, lot and operation is domain separated. Same ID cannot execute a second economic effect. An invalidated epoch never executes even when followed by a fresh pending epoch.
- Collateral conservation. Managed ETH equals sum of locked and claimable lots plus any future provider claims; unsolicited ETH is isolated. Claim payout is bounded by lot and cumulative paid cannot exceed original ETH. Failed claim leaves full obligation.
- Interest and losses. Debt reductions require exact receipt or a future separately authorized write-off; no timeout reduces balances. Interest is independent of checkpoint frequency under fixed principal and carry. Settlement distributions cannot exceed actual escrow and proceeds. Every uncovered amount is tracked until recovery or recorded loss.
- Cash isolation. Native gas funding is independent of ETH collateral and Base USDC. Callback billing code cannot draw on custodied ETH; use a distinct Unichain callback receiver forwarding validated intent to the vault. Restricted proxy payer and isolated native balance are also used on Base.

## Proposed M2 integration invariants

- A successful draw consumes exactly one reservation and books principal equal to verified market repayment and net vault debit. Any failure restores all local state and approvals.
- Every repayment credit references a consumed reservation, derives its lender from that reservation and increases that lender's free balance and total cash only by the exact tokens pulled from the authorized payer in that transaction. Payment IDs are single-use.
- `balance = totalFree + totalReserved + unsolicitedSurplus`. Interest and principal receivables are excluded from cash. Allocation of each actual payment is interest first, then principal, with any payoff carry rounded once.
- Adapter and manager balances return to their pre-draw baselines and adapter/market allowances are zero after success. Payer allowances cannot be used through an arbitrary-payer manager entry point.
- Financial activation requires both matching authenticated transport and a currently valid independently verified finality assertion. A duplicate cannot repeat an effect, a conflicting payload cannot replace a recorded fact, and a revoked epoch cannot authorize a new activation. No timeout constitutes proof or debt forgiveness.
- Repayment above the accrued claim reverts before transfer. Manager vault binding and vault manager/consumer bindings are immutable and must match factory predictions before local deployment succeeds.

## M1-A verification

For each lender, free plus reserved equals accounted cash belonging to that lender. Summed lender buckets equal vault totals, and the sum of active reservations equals total reserved. The stateful suite maintains independent per-lender cash and reservation records and tracks deposits, withdrawals, consumption, donations, ETH locks and forced ETH. Actual balances reconcile to managed balances plus unsolicited surplus. Terminal reservations carry zero active amount. Duplicate bindings, reservations, releases of reserves and consumption attempts fail. Token callbacks cannot enter a mutator during an external asset interaction. There is no ETH release entry point, so total released stays zero. The full credit and settlement invariants above remain integration acceptance criteria.
