# State machines

All table transitions commit state and emit the named event atomically on their chain. Failed guards or external transfers revert all local writes; safely duplicated committed operations return without a second financial effect or transition log. Conflict with the same ID and different payload reverts. Unknown or early cross-chain facts can be staged only where specified, or retried after prerequisites. Authenticate before staging. Each operation uses its domain ID from Architecture, consumed only on success. All chain time comparisons use the authoritative chain's clock, with draw permitted strictly before draw deadline and default allowed at or after maturity plus grace.

## Collateral (Unichain)

| Transition | Caller and guard | Update and event | Callback, replay and retry |
|---|---|---|---|
| Absent → Locked | Borrower, valid signed terms and exact ETH; lot empty and no staged release | Bind lot, amount, owner, and terms. `CollateralLocked` | Lasna routes to Base. Repeated deposit rejects and conveys no ETH. |
| Absent → Release authorized | Proxy and finalized Base release proof, either arrival order, canonical lot fields | Stage terminal tombstone. `ReleaseAuthorized` | Blocks later lock. Same op safely replayable. Missing counterpart leaves only staged fact. |
| Locked → Claimable | Same dual guard, lot and borrower match | Authorize complete lot once. `ReleaseAuthorized` | Exact duplicate harmless. Retry proof/callback independently. |
| Claimable → Released | Borrower, nonzero chosen recipient | Clear claim before ETH transfer. `CollateralReleased` | Transfer failure reverts and borrower can retry with another recipient. Repeated successful claim rejects. |

## Credit agreement (Base)

| Transition | Caller and guard | Update and event | Callback, replay and retry |
|---|---|---|---|
| Absent → Draft | Either consenting party or relayer submits both signatures, unused nonce, valid deadlines and supported terms | Store immutable terms. `AgreementRegistered` | Local. Nonce prevents creation twice. |
| Absent → Closed | Borrower with both valid signatures and unused nonce, registering and closing atomically for recovery, even after draw deadline | Consume nonce, write terminal agreement, emit `AgreementRegistered`, `AgreementClosed` and `ReleaseApproved` | Same release routing and replay rules as unused close. No draw or reservation is possible. |
| Draft → Active | Anyone finalizes after both authenticated lock facts, exact match, fresh valuation, deadline and free cash | Record lot, reserve atomically, `AgreementActivated` | Lasna callback stages its lock fact and may attempt activation. Underfunding leaves staged facts and permits local retry. |
| Draft/Active → Closed | Borrower before draw, or anyone at draw expiry, with zero debt | Invalidate pending epoch, free reserved balance, emit `AgreementClosed` and durable `ReleaseApproved` | Route release to Unichain. Terminal guard prevents future draws. Permissionless reannouncement emits the identical operation. |
| Active → Drawn | Authenticated callback or same guarded local executor, before deadline, successful draw | Create debt, zero remainder reservation, `DrawExecuted` | No synchronous downstream callback. Replay governed by draw ID and one-success flag. |
| Drawn/Defaulted → same | Any payer, positive receipt smaller than full claim, settlement idle | Accrue/apply cash, `DebtRepaid` | Local token pull is atomic; fresh authorized payment may be made against remaining debt. |
| Drawn/Defaulted → Closed | Any payer covers entire claim, settlement idle | Zero debt and emit `DebtRepaid`, `AgreementClosed`, `ReleaseApproved` | Same terminal release routing. Repeated repayment rejects. |
| Drawn → Defaulted | Anyone, maturity plus grace and claim positive | Record default sequence, `AgreementDefaulted` | Local, once per agreement. Cure until settlement starts. Expiration alone never closes funded debt. |

## Reservation (Base)

| Transition | Caller and guard | Update and event | Callback, replay and retry |
|---|---|---|---|
| Absent → Reserved | Manager on activation, unique ID, free cash ≥ cap | Free decreases, reserved increases. `LiquidityReserved` | Same Base transaction as activation, retry only while Draft. |
| Reserved → Consumed | Manager during verified draw | Spend exact applied amount, return remainder to free. `ReservationConsumed` | Same Base transaction as draw. Failed draw keeps bucket intact. |
| Reserved → Returned | Manager on unused close | Move entire remainder to free. `ReservationReturned` | Atomic with terminal close. No second return. |

## Draw operation (Base)

| Transition | Caller and guard | Update and event | Callback, replay and retry |
|---|---|---|---|
| Absent → Pending | Anyone samples live qualifying risk for active agreement with no pending epoch | Store incremented epoch, immutable draw ID and original expiry bounded by draw deadline. `RiskObserved` | Lasna requests Base execution. Duplicate observation while pending does not mint a new epoch. |
| Pending → Executed | Authenticated callback or permissionless `executePending`, epoch current, all live pre/postconditions satisfied | Guard reentrancy, call adapter and verify receipt, consume epoch and book principal atomically. `DrawExecuted` | On failure remains Pending. Retry same ID within expiry. |
| Pending → Invalidated | Manager atomically on close, or anyone after epoch expiry | Permanently invalidate ID. `DrawInvalidated` | Delayed execution rejects or safely no-ops. New risk needs new qualifying observation, fresh epoch and active facility. |

Base transaction ordering serializes cancellation and execution. If execution wins, the close-unused guard fails. If cancellation wins, execution cannot spend. A stale risk or oracle failure never books a draw, and no asynchronous draw has transferred funds while pending.

## Settlement

M1 has only Idle. Default does not start settlement. The following design is gated and requires the settlement policy and verifier before implementation.

| Transition | Caller and guard | Update and event | Callback, replay and retry |
|---|---|---|---|
| Idle → Escrowed | Provider posts exact approved quote and measured Base cash against live default | Bind settlement ID, freeze claim and disable ordinary repayment. `SettlementEscrowed` | Award can route only after finality. Atomic ordering with cure. Quote and ID single-use. |
| Escrowed → Assigned on Unichain | Authorized finalized Base escrow/award via authenticated route, matching lot and no cancellation tombstone | Irrevocable provider ETH claim. `CollateralAssigned` | Replay harmless. Claim uses pull transfer and retries, independent of assignment. |
| Escrowed → Cancelled on Unichain | Authorized finalized Base cancel intent for the quote under signed cancellation terms, only before assignment | Permanent tombstone. `AssignmentCancelled` | Race with award resolved on Unichain; emit winning durable result again if needed. |
| Escrowed → Settled on Base | Verified finalized exact assignment; callable by any proof submitter | Distribute escrow and apply recovery/write-off, emit `SettlementApplied` | Terminal ID consumed; delayed cancellation cannot refund. |
| Escrowed → Refunded on Base | Verified finalized exact cancellation; callable by any proof submitter | Return escrow and reopen default to cure or a new settlement sequence, emit `SettlementRefunded` | Terminal ID consumed; failed transfer rolls back. No elapsed-time shortcut. |

A cancellation intent alone never refunds. An assignment receipt alone never proves lender payment. Out-of-order settlement messages can stage or retry by ID. A disagreement or missing outcome keeps escrow and custody frozen pending canonical evidence.
