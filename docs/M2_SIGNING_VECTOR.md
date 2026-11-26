# M2-B local EIP-712 signing vector

The local manager uses EIP-712 domain `EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)` with name `Covenant`, version `1`, runtime chain ID and manager address. The primary type is exactly:

```text
Terms(address borrower,address lender,address collateralVault,uint256 collateralChainId,bytes32 lotId,uint256 collateralAmount,address market,address debtor,bytes32 policy,uint256 cap,uint256 nonce,uint64 consentDeadline,uint64 drawDeadline,uint64 maturity,uint64 grace,uint16 ltvBps)
```

Before signing, set `lotId` to zero in the typed-data message. Compute `termsHash = keccak256(abi.encode(TERMS_TYPEHASH, normalizedTerms))`, and `agreementId = keccak256(abi.encode("AGREEMENT_V1", chainId, manager, borrower, lender, nonce, termsHash))`. The submitted terms must contain `lotId = keccak256(abi.encode("LOT_V1", collateralChainId, collateralVault, agreementId))`. The contract recomputes this value before signature verification. Both signatures sign `keccak256(0x1901 || domainSeparator || termsHash)`.

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
nonce              = 1
consentDeadline    = 11000
drawDeadline       = 12000
maturity           = 13000
grace              = 100
ltvBps             = 5000
typeHash           = 0x2aa632bea9262f2564f73d4a1beafef7b9def4caabf082875275d89bac0cb273
termsHash          = 0x76446e80b51521016838a427da1025b3df01637cb3bcd591c4887656287250a2
domainSeparator    = 0x37e398d660c630bb346cb317714cd7a3c3c014f3f68b8cd93232891adbab0b13
digest             = 0x110a451a1c39a1f969f34d71e2225ce3c248866e2c05aae47ada001878afce27
agreementId        = 0xbb2503b110a84823a069969e183a935145d6e95bdc115ba0967923a54d72e0d5
submitted lotId    = 0x02348dc25c1ab4188cfb2ab6d28bd6a5e98b60c482f11a6c87eb2613945f917c
borrower signature = 0x5d3db45b320088ce8d28f05e76e21c3e2d21e8d81246189af03aa24cfa9f3d0e1bbaab4c89987a5e6dd0a861bb24fc79291d15460249c5bb2f9e202c0ac8c8301b
lender signature   = 0x74e688a95673ee2e7cc42bdad600728d6f0dbea442c1aaa4c4961654523410687f25471a87b1390447ba1ef51dae91916a72b1af6ddedc629cc6a3fea05f39bd1b
```

`cast abi-encode` and `cast keccak` independently reproduced the type hash, terms hash, domain separator and digest. `testExternalSigningVector` checks the same constants against the deployed local manager. The fixture uses test timestamps and is not a live agreement.

The contract tracks `usedNonce[borrower][nonce]`. Both borrower and lender signatures bind the same borrower nonce and full signed terms. There is no separate lender nonce or lender-wide cancellation mechanism. Contract and chain domain separation prevent moving the same signatures to another manager or chain. Contract-wallet signature support remains outside this implementation.
