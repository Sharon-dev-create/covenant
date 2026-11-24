# Product

A borrower arranges a backstop before a DeFi position enters distress. A lender locks inventory against agreed terms. If the market becomes distressed, the facility spends only the USDC required and authorized for a specific repayment. The borrower then owes Covenant the exact amount applied plus agreed interest. Unused commitment creates zero principal.

The intended users are DeFi borrowers who need an emergency repayment window and lenders willing to reserve liquidity for a named facility. The lender can audit available cash, locked inventory and liabilities separately. The borrower can audit the purpose, window and maximum cost before locking collateral.

MVP demonstration uses native test ETH, Circle test USDC and a labelled deterministic lending market. It covers consent, cross-chain lock confirmation, lender reservation, autonomous repayment, Covenant repayment and release. Use one fixed lender, borrower, target, and collateral lot per agreement, with one successful non-revolving draw. Default is observable and keeps collateral locked. Lender recovery is a production gate.

Success requires an independently reproducible lifecycle and measured time from the same risk signal to debt repayment under autonomous and manual execution. A harness result applies to that market model and tested transport only.
