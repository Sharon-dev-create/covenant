# M2-B local EIP-712 signing vector

The local manager uses EIP-712 domain `EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)` with name `Covenant`, version `3`, runtime chain ID and manager address. The primary type is exactly:

```text
Terms(address borrower,address lender,address collateralVault,uint256 collateralChainId,bytes32 lotId,uint256 collateralAmount,address market,address debtor,bytes32 policy,uint256 cap,uint256 autonomousRepayment,uint256 maxHealth,uint256 borrowerNonce,uint256 lenderNonce,uint64 consentDeadline,uint64 drawDeadline,uint64 maturity,uint64 grace,uint16 ltvBps)
```

Before signing, set `lotId` to zero in the typed-data message. Compute `termsHash = keccak256(abi.encode(TERMS_TYPEHASH, normalizedTerms))`, and `agreementId = keccak256(abi.encode("AGREEMENT_V1", chainId, manager, borrower, lender, borrowerNonce, termsHash))`. The submitted terms must contain `lotId = keccak256(abi.encode("LOT_V1", collateralChainId, collateralVault, agreementId))`. The contract recomputes this value before signature verification. Both signatures sign `keccak256(0x1901 || domainSeparator || termsHash)`.

The following deterministic Foundry fixture is reproducible by an independent EIP-712 implementation. Addresses and signatures are public test fixtures. No key from this example should hold assets.

```text
chainId            = 31337
verifyingContract  = 0x5B0091f49210e7B2A57B03dfE1AB9D08289d9294
borrower           = 0xe05fcC23807536bEe418f142D19fa0d21BB0cfF7
lender             = 0x0376AAc07Ad725E01357B1725B5ceC61aE10473c
collateralVault    = 0x0000000000000000000000000000000000000055
collateralChainId  = 1301
signed lotId       = 0x0000000000000000000000000000000000000000000000000000000000000000
collateralAmount   = 1000000000000000000
market             = 0x0000000000000000000000000000000000000042
debtor             = 0xe05fcC23807536bEe418f142D19fa0d21BB0cfF7
policy             = 0x0000000000000000000000000000000000000000000000000000000000000001
cap                = 500000000
autonomousRepayment = 200000000
maxHealth          = 1100000000000000000
borrowerNonce      = 1
lenderNonce        = 10
consentDeadline    = 11000
drawDeadline       = 12000
maturity           = 13000
grace              = 100
ltvBps             = 5000
typeHash           = 0x669c38bed1ae421d32d2b337fb86ee03fb2ce82f79fedaf8c20d96b007d63523
termsHash          = 0x68a098dca601dc92404b99a70d5c8e02dc28048d718c566e111f51c8a4b2f95a
domainSeparator    = 0xa9265b0b47346ed192e431127dbc571b49a5936e0924dca9a7b12c2223fce039
digest             = 0x5f96effdd1145a4f26cb13636e71ec8a15c7455e8c2124b53494d6f476c22f76
agreementId        = 0x9a6feae81eb522ed255e907548fac414b691acb459ec64dd14c01cc0bcab4a79
submitted lotId    = 0x1ed0ed3f7ed90759e91a056a5dd284c0e95bd503ea9478e16fc14a00553a5eba
borrower signature = 0xe859269fb9a75c1b6c9462164e3d29b6b45a1b09a46cf029fae6a04bd045e89c01a5718fd698d682a11f468a3eed9408bef49372082d1998278b92cfefdfa5951c
lender signature   = 0xaccc5a349a152ff1a1253220a2979c69b024ecba15db7830daa2c4415c4e2b2d78e3927707572e3f9b42d8398c461d6197b94dcbf29f5948f6db7cd06157b7281c
```

`cast abi-encode` and `cast keccak` independently reproduced the type hash, terms hash, domain separator and digest. `testExternalSigningVector` checks the same constants against the deployed local manager. The fixture uses test timestamps and is not a live agreement.

The contract tracks `usedBorrowerNonce[borrower][borrowerNonce]` and `usedLenderNonce[lender][lenderNonce]` separately. Each signer can invalidate any unused nonce in its own role. Registration consumes both atomically. A single address acting in both roles uses two independent namespaces and may sign once and submit the same valid signature for both roles. Contract and chain domain separation prevent moving signatures to another manager or chain. Contract-wallet signature support remains outside this implementation.

Version 3 adds signed `autonomousRepayment` and `maxHealth`, and changes the domain version from 2 to 3. It is incompatible with version 2 and version 1 signatures, agreement IDs and lot IDs. Old signatures and signing integrations must be regenerated; already deployed immutable contracts are not upgraded. `autonomousRepayment` is the exact USDC-unit draw and `maxHealth` is the maximum accepted market health in 1e18 units. Local policy `bytes32(uint256(1))` requires both the signed health bound and the bound market's `isDistressed` result. The signed threshold does not make the fixture's risk inputs independent or trustworthy.
