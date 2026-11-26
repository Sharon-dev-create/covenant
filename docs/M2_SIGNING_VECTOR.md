# M2-B local EIP-712 signing vector

The local manager uses EIP-712 domain `EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)` with name `Covenant`, version `2`, runtime chain ID and manager address. The primary type is exactly:

```text
Terms(address borrower,address lender,address collateralVault,uint256 collateralChainId,bytes32 lotId,uint256 collateralAmount,address market,address debtor,bytes32 policy,uint256 cap,uint256 borrowerNonce,uint256 lenderNonce,uint64 consentDeadline,uint64 drawDeadline,uint64 maturity,uint64 grace,uint16 ltvBps)
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
borrowerNonce      = 1
lenderNonce        = 10
consentDeadline    = 11000
drawDeadline       = 12000
maturity           = 13000
grace              = 100
ltvBps             = 5000
typeHash           = 0x6784f511a0eeae862904d845b9ab1a33450659011f64eb82cba153afb8330b7e
termsHash          = 0xbb1a419a9fcdfb61d1d7f9abf47bbd0f65fa181130e8ef2c5b5a7f781385f869
domainSeparator    = 0xaf3a8d5dce6eb6c2eb9dd4e84480a3be3dc3aaa88908202c6bc871a3bb7d1058
digest             = 0xf40598a4bb03e32dcbf429b7f62ea8b07419291ac7953df04df7756a8a2a4816
agreementId        = 0x925075b49285f768cde89aa84ca36bfda08742824def1529a66ef0203c87890a
submitted lotId    = 0x525ed2e15102a7abca4da5ddc72f898a6083baefbc64e5776a3934f42390c3e5
borrower signature = 0xe559c7431e658cd44e5d4c2878f7b42eeac5f3c871c763e65a6de5cda4793ed146f53d068335e0478affde7b84a610f4533bba9e33bf2e1ba0d8e7f2b1b4025e1c
lender signature   = 0xb921c46e49c5401cb1f98eb585adef482a16b476bf8c55e97f128029f373565a4f1290849622e66f54f7281c4e811d5d0314deeef18ce813b40e0ba8e53f8f071c
```

`cast abi-encode` and `cast keccak` independently reproduced the type hash, terms hash, domain separator and digest. `testExternalSigningVector` checks the same constants against the deployed local manager. The fixture uses test timestamps and is not a live agreement.

The contract tracks `usedBorrowerNonce[borrower][borrowerNonce]` and `usedLenderNonce[lender][lenderNonce]` separately. Each signer can invalidate any unused nonce in its own role. Registration consumes both atomically. A single address acting in both roles uses two independent namespaces and may sign once and submit the same valid signature for both roles. Contract and chain domain separation prevent moving signatures to another manager or chain. Contract-wallet signature support remains outside this implementation.

Version 2 is incompatible with the earlier version 1 schema: the single `nonce` field was replaced with `borrowerNonce` and `lenderNonce`, the EIP-712 domain version changed, and agreement and derived lot IDs consequently change. Old signatures and existing off-chain integrations must be regenerated; already deployed immutable contracts are not upgraded by this source change.
