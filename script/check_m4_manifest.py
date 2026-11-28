#!/usr/bin/env python3
"""Offline check of public deployment configuration; never reads keys or connects to RPCs."""
import json
from decimal import Decimal, InvalidOperation
import re
import sys
import subprocess
from pathlib import Path


def fail(message):
    raise ValueError(message)


def address(value, name):
    if not isinstance(value, str) or not re.fullmatch(r"0x[0-9a-fA-F]{40}", value) or int(value, 16) == 0:
        fail(f"{name}: nonzero public address required")
    return value.lower()


def scan(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if any(word in key.lower() for word in ("privatekey", "password", "mnemonic", "secret", "credential")):
                fail(f"sensitive field prohibited: {key}")
            scan(item)
    elif isinstance(value, list):
        for item in value:
            scan(item)



# Stage checks are deliberately fixed in code, never supplied by the manifest.
ROOT = Path(__file__).resolve().parent.parent
SIGNER = "0xb108b6f40e5aefdc8475b053be4248c53ef07b0f"
TOKEN = "0xc8013185d548990956b9b0cf4bee55c3be3df3e9"
VAULT = "0x21ab80a429b48cc4dfbe35308096930472f56954"
ORACLE = "0xebc6b76b9ca1da2934d89e43bd72ef0ba9258680"
MARKET_CODE_HASH = "0x95ed49ab5db7cabfda074896b60ab9dad80c5f66eb321d463770dfffc00bae2b"
STAGE3A_LIMIT = 60_000_000_000_000


def load_public(path):
    with open(path, encoding="utf-8") as stream:
        value = json.load(stream)
    scan(value)
    return value


def cast(*args):
    executable = Path.home() / ".foundry/bin/cast"
    try:
        return subprocess.run([str(executable), *args], check=True, text=True, capture_output=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        fail(f"required Foundry verification failed: {exc}")


def uint(value, name):
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        fail(f"{name}: nonnegative integer required")
    return value


def validate_stage3a(m, operational, stage1, stage2, simulation, artifact):
    if m.get("stageId") != "stage3a" or m.get("status") != "stage3a-authorized-market-preflight-passed-not-broadcast":
        fail("stage3a: incorrect stage or state")
    action = m["validatedAction"]
    if set(action) != {"contract", "signature", "arguments", "valueWei", "count"}:
        fail("stage3a: unsupported action schema")
    if action["contract"] != "DemoMarket" or action["signature"] != "deployMarket(address,address)" or type(action["count"]) is not int or action["count"] != 1 or type(action["valueWei"]) is not int or action["valueWei"] != 0:
        fail("stage3a: only one zero-value DemoMarket creation is permitted")
    if len(action["arguments"]) != 2 or [address(v, "constructor argument") for v in action["arguments"]] != [TOKEN, SIGNER]:
        fail("stage3a: constructor arguments do not match authorization")
    if m["chainId"] != 84532 or address(m["signer"], "signer") != SIGNER or address(m["operator"], "operator") != SIGNER or address(m["token"], "token") != TOKEN:
        fail("stage3a: chain, signer, operator or token mismatch")
    if operational["networks"]["base"]["chainId"] != 84532 or address(operational["roles"]["deployer"], "approved deployer") != SIGNER or address(operational["roles"]["marketOperator"], "approved operator") != SIGNER or address(operational["networks"]["base"]["demoAsset"], "verified token") != TOKEN:
        fail("stage3a: operational binding mismatch")
    approved = operational["stage3AMarketProposal"]
    if approved["broadcastAuthorized"] is not True or approved["status"] != "authorized-preflight-passed-not-broadcast" or approved["proposedCeilingWei"] != str(STAGE3A_LIMIT) or m.get("broadcastAuthorized") is not True or not isinstance(m.get("authorization"), str) or not m["authorization"].strip():
        fail("stage3a: explicit scoped authorization missing")
    if stage1.get("status") != "stage1-both-deployments-verified" or stage2.get("status") != "stage2-deployment-verified-authorization-closed":
        fail("stage3a: prerequisite deployment evidence missing")
    token_receipt = stage1["tokenPreflight"]["receipt"]
    oracle_receipt = stage1["oracle"]["receipt"]
    vault_receipt = stage2["deploymentReceipt"]
    for rec, expected in ((token_receipt, TOKEN), (oracle_receipt, ORACLE), (vault_receipt, VAULT)):
        if not isinstance(rec, dict) or rec.get("status") != "success" or not re.fullmatch(r"0x[0-9a-fA-F]{64}", rec.get("transactionHash", "")) or address(rec.get("actualAddress", rec.get("contractAddress")), "prerequisite") != expected or rec.get("constructorAndCreationBytecodeMatch", rec.get("exactConstructorAndCreationCode")) is not True:
            fail("stage3a: prerequisite receipt evidence invalid")
    if token_receipt.get("runtimeHashMatches") is not True or oracle_receipt.get("runtimeHashWithImmutableMatches") is not True or vault_receipt.get("runtimeHash") != "0x5403b0445d1270d125ae86c25f4a6ca4daefd9ff1169a559e1aeb20c10f943c0":
        fail("stage3a: prerequisite runtime evidence invalid")
    if m.get("stage2Evidence") != "deployments/m4e2.stage2.verified.json" or operational["networks"]["base"]["deploymentReceipts"].get("demoAsset", "").lower() != token_receipt["transactionHash"].lower() or address(operational["networks"]["unichain"]["collateralVault"], "vault") != VAULT:
        fail("stage3a: conflicting prerequisite evidence")
    snapshot = m["snapshot"]
    latest = uint(snapshot["latestNonce"], "latest nonce")
    pending = uint(snapshot["pendingNonce"], "pending nonce")
    if latest != 15 or pending != latest or uint(snapshot["block"], "block") == 0 or not isinstance(snapshot.get("signerBalanceWei"), str) or not snapshot["signerBalanceWei"].isdigit() or int(snapshot["signerBalanceWei"]) < STAGE3A_LIMIT:
        fail("stage3a: unexpected or conflicting nonce evidence")
    predicted = address(m["predictedAddressAtNonce15"], "predicted address")
    if address(cast("compute-address", SIGNER, "--nonce", str(latest)), "computed address") != predicted or m["predictedAddressCodeAtPreflight"] != "0x":
        fail("stage3a: CREATE prediction or empty-code evidence invalid")
    code = artifact["bytecode"]["object"]
    if not isinstance(code, str) or not re.fullmatch(r"0x[0-9a-fA-F]+", code) or cast("keccak", code).lower() != MARKET_CODE_HASH or m["creationCodeHash"].lower() != MARKET_CODE_HASH:
        fail("stage3a: artifact creation code mismatch")
    if m["simulationEvidence"] != {"signerSpecificEstimate": True, "singleCreationScript": True, "source": "deployments/m4e2.stage3a.simulation.json"} or m.get("simulatedCreationCount") != 1:
        fail("stage3a: simulation evidence missing")
    txs = simulation["transactions"]
    if simulation.get("chain") != 84532 or len(txs) != 1:
        fail("stage3a: simulation must contain one Base creation")
    tx = txs[0]
    inner = tx["transaction"]
    expected_input = code.lower() + TOKEN[2:].rjust(64, "0") + SIGNER[2:].rjust(64, "0")
    if tx.get("hash") is not None or tx.get("transactionType") != "CREATE" or tx.get("contractName") != "DemoMarket" or tx.get("exactArtifactMatch") is not True or address(tx.get("contractAddress"), "simulation address") != predicted or [address(v, "simulation argument") for v in tx.get("arguments", [])] != [TOKEN, SIGNER] or address(inner.get("from"), "simulation sender") != SIGNER or inner.get("to") is not None or int(inner.get("value", "-1"), 16) != 0 or inner.get("input", "").lower() != expected_input:
        fail("stage3a: simulation action does not match exact constructor")
    gas = uint(m["forgeScriptBufferedGas"], "gas")
    price = uint(m["maxExecutionGasPriceWei"], "max gas price")
    l1 = uint(m["syntheticL1FeeWei"], "L1 estimate")
    operator = uint(m["operatorFeeEstimateWei"], "operator estimate")
    if gas == 0 or gas != int(inner["gas"], 16) or uint(m["gasEstimate"], "signer estimate") == 0 or price != 15_000_000 or gas * price + l1 + operator > STAGE3A_LIMIT:
        fail("stage3a: simulation or estimated expenditure exceeds ceiling")
    if m["proposedStage3ACeilingsWei"] != {"base": STAGE3A_LIMIT, "unichain": 0, "lasna": 0} or any(type(v) is not int for v in m["proposedStage3ACeilingsWei"].values()):
        fail("stage3a: expenditure authorization mismatch")
    if m["scope"] != {"actions": ["deployMarket"], "participantFundingWei": 0, "providerReserveWei": 0, "tokenIssuance": False, "marketConfiguration": False, "collateralLocking": False, "financialExecution": False} or any(type(m["scope"][k]) is not bool for k in ("tokenIssuance", "marketConfiguration", "collateralLocking", "financialExecution")) or any(type(m["scope"][k]) is not int for k in ("participantFundingWei", "providerReserveWei")):
        fail("stage3a: unsupported expenditure or expanded action scope")
    if m.get("marketReceipt") is not None:
        fail("stage3a: deployment already recorded")
    print("Stage 3A offline record accepted for exactly one DemoMarket creation; not full financial readiness. Recheck RPC state and exact command independently before broadcast.")
    print("Validated action: DeployM4.deployMarket(address,address), " + TOKEN + ", " + SIGNER + "; account=covenant-testnet; chain=84532; value=0")
    print("Validated command: M4_SIGNER=" + SIGNER + " ~/.foundry/bin/forge script script/DeployM4.s.sol:DeployM4 --rpc-url https://base-sepolia-rpc.publicnode.com --sender " + SIGNER + " --sig \"deployMarket(address,address)\" " + TOKEN + " " + SIGNER + " --account covenant-testnet --broadcast --with-gas-price 15000000 --priority-gas-price 1000000 --gas-estimate-multiplier 130")


def run_stage3a(m):
    validate_stage3a(m, load_public(ROOT / "deployments/m4.financial-readiness.proposed.json"),
        load_public(ROOT / "deployments/m4e2.stage1.verified.json"),
        load_public(ROOT / "deployments/m4e2.stage2.verified.json"),
        load_public(ROOT / "deployments/m4e2.stage3a.simulation.json"),
        load_public(ROOT / "out/DemoMarket.sol/DemoMarket.json"))



MARKET = "0x2e1df1c633972b4c8e2d9148484f592a5b48e244"
ATTESTORS = [SIGNER, "0x6f4ae62fee718db67652500807886052e98ea422", "0xac1a3b8c98883e8f1d5e014e547cc0e109ead4c9", "0x1243b643c14e8a916f3cef5474b0e047af0757a0"]
STAGE3B_ARTIFACTS = {
    "CollateralAttestationVerifier": "0x9edd6b48521b7ca536f2e1449b52460e7cdc90c1837cc86c7b5a4694bb138439",
    "DemoAdapter": "0x6fc119647640fbd6e99fb2dd316811de1770b01ef6e1cfd3010400cd58dd484b",
    "DemoDeploymentFactory": "0x3ebd93ec3f7a86e98712420aff177c6f22077c951e0a6ca020cadd6e0c7d5947",
    "TestnetCreditFactory": "0xb644aa597faa6d7fba63fd07749c95981ad16507df9f6791964184c75a603c96",
    "TestnetCreditManager": "0x81063f5e389a5b7371549abf78b01c96f46a20c4e5954881b9ba7338bcb047f9",
    "CreditLiquidityVault": "0x4e5b843d7823c9ed1370950119dce61355a7388c123da4fb767db10bd44b098f",
}


def validate_stage3b(m, operational, stage1, stage2, stage3a, artifacts, trace, broadcast=False):
    if m.get("stageId") != "stage3b" or m.get("status") != "stage3b-preparation-pending-authorization":
        fail("stage3b: incorrect, closed or consumed stage")
    if m.get("chainId") != 84532 or address(m.get("signer"), "signer") != SIGNER or address(operational["roles"]["deployer"], "approved signer") != SIGNER:
        fail("stage3b: chain or signer mismatch")
    if address(operational["roles"]["governance"], "governance") != SIGNER or address(operational["roles"]["emergencyAuthority"], "emergency") != SIGNER or [address(v, "attestor") for v in operational["roles"]["attestors"]] != ATTESTORS or len(set(ATTESTORS)) != 4 or operational["governance"]["threshold"] != 3:
        fail("stage3b: governance or attestor configuration mismatch")
    expected_dependencies = {"token": TOKEN, "oracle": ORACLE, "market": MARKET, "sourceVault": VAULT}
    if set(m["actualDependencies"]) != set(expected_dependencies) or any(address(m["actualDependencies"][k], k) != v for k, v in expected_dependencies.items()):
        fail("stage3b: dependency mismatch")
    if stage1.get("status") != "stage1-both-deployments-verified" or stage2.get("status") != "stage2-deployment-verified-authorization-closed" or stage3a.get("status") != "stage3a-market-verified-authorization-closed" or m.get("stage3aEvidence") != "deployments/m4e2.stage3a.verified.json":
        fail("stage3b: prerequisite evidence missing")
    for rec, expected in ((stage1["tokenPreflight"]["receipt"],TOKEN),(stage1["oracle"]["receipt"],ORACLE),(stage2["deploymentReceipt"],VAULT),(stage3a["marketReceipt"],MARKET)):
        if not isinstance(rec, dict) or rec.get("status") != "success" or not re.fullmatch(r"0x[0-9a-fA-F]{64}", rec.get("transactionHash", "")) or address(rec.get("actualAddress", rec.get("contractAddress")), "prerequisite") != expected or rec.get("constructorAndCreationBytecodeMatch", rec.get("exactConstructorAndCreationCode")) is not True:
            fail("stage3b: invalid prerequisite receipt")
    market_receipt = stage3a["marketReceipt"]
    if market_receipt.get("runtimeHash") != "0x8eedb99eb7ed89d9b77469ab149c4a8ca8dd671df541801aa9c13454b50eb836" or address(market_receipt.get("token"), "market token") != TOKEN or address(market_receipt.get("operator"), "market operator") != SIGNER or address(operational["networks"]["base"]["market"], "recorded market") != MARKET:
        fail("stage3b: market binding or runtime evidence mismatch")
    snapshot = m["snapshot"]
    if uint(snapshot["latestNonce"], "latest nonce") != 16 or uint(snapshot["pendingNonce"], "pending nonce") != 16 or uint(snapshot["block"], "block") == 0:
        fail("stage3b: unexpected or pending signer nonce")
    if not isinstance(snapshot.get("balanceWei"), str) or not snapshot["balanceWei"].isdigit():
        fail("stage3b: invalid signer balance evidence")
    addrs = m["conditionalAddresses"]
    names = ("verifierNonce16", "adapterNonce17", "outerFactoryNonce18", "nestedFactory", "manager", "liquidityVault")
    if set(addrs) != set(names) or set(m["codeChecks"]) != set(names) or any(m["codeChecks"][k] != "0x" for k in names):
        fail("stage3b: missing code or prediction checks")
    for k, nonce in (("verifierNonce16",16),("adapterNonce17",17),("outerFactoryNonce18",18)):
        if address(addrs[k], k) != address(cast("compute-address", SIGNER, "--nonce", str(nonce)), k):
            fail("stage3b: incorrect top-level CREATE prediction")
    for child, parent, nonce in (("nestedFactory","outerFactoryNonce18",1),("manager","nestedFactory",1),("liquidityVault","nestedFactory",2)):
        if address(addrs[child], child) != address(cast("compute-address", addrs[parent], "--nonce", str(nonce)), child):
            fail("stage3b: incorrect nested CREATE prediction")
    expected_actions = [
        {"contract":"CollateralAttestationVerifier","signature":"deployVerifier(address,address,address,address,address[4])","nonce":16,"address":addrs["verifierNonce16"],"arguments":[VAULT,addrs["manager"],SIGNER,SIGNER,ATTESTORS],"valueWei":0},
        {"contract":"DemoAdapter","signature":"deployAdapter(address,address,address)","nonce":17,"address":addrs["adapterNonce17"],"arguments":[TOKEN,MARKET,addrs["manager"]],"valueWei":0},
        {"contract":"DemoDeploymentFactory","signature":"deployFactory(address,address,address,address,address,address)","nonce":18,"address":addrs["outerFactoryNonce18"],"arguments":[SIGNER,TOKEN,addrs["verifierNonce16"],ORACLE,addrs["adapterNonce17"],addrs["outerFactoryNonce18"]],"valueWei":0},
    ]
    def lower_tree(v):
        if isinstance(v, str): return v.lower()
        if isinstance(v, list): return [lower_tree(x) for x in v]
        if isinstance(v, dict): return {k:lower_tree(x) for k,x in v.items()}
        return v
    if lower_tree(m["orderedActions"]) != lower_tree(expected_actions) or any(type(a["nonce"]) is not int or type(a["valueWei"]) is not int for a in m["orderedActions"]):
        fail("stage3b: action order, nonce, constructor or manager binding mismatch")
    if m["scope"] != {"actions":["deployVerifier","deployAdapter","deployFactory"],"unichainWei":0,"lasnaWei":0,"participantFundingWei":0,"providerReserveWei":0,"tokenIssuance":False,"marketConfiguration":False,"collateralLocking":False,"financialExecution":False,"callbackConfiguration":False} or any(type(m["scope"][k]) is not bool for k in ("tokenIssuance","marketConfiguration","collateralLocking","financialExecution","callbackConfiguration")) or any(type(m["scope"][k]) is not int for k in ("unichainWei","lasnaWei","participantFundingWei","providerReserveWei")):
        fail("stage3b: additional action or funding not allowed")
    if m["artifactHashes"] != STAGE3B_ARTIFACTS or set(artifacts) != set(STAGE3B_ARTIFACTS):
        fail("stage3b: artifact inventory mismatch")
    for k,h in STAGE3B_ARTIFACTS.items():
        code = artifacts[k]["bytecode"]["object"]
        if cast("keccak", code).lower() != h: fail("stage3b: artifact bytecode mismatch")
    fork=m["forkSimulation"]
    if fork.get("result") != "pass" or fork.get("test") != "testStage3BRemainingSequenceOnFork" or fork.get("trace") != "deployments/m4e2.stage3b.fork-trace.txt" or fork.get("source") != "docs/M4E2_STAGE3B_FORK_HARNESS.txt" or "[PASS] testStage3BRemainingSequenceOnFork()" not in trace:
        fail("stage3b: complete fork simulation evidence missing")
    trace_names={"CollateralAttestationVerifier":"verifierNonce16","DemoAdapter":"adapterNonce17","DemoDeploymentFactory":"outerFactoryNonce18","TestnetCreditFactory":"nestedFactory","TestnetCreditManager":"manager","CreditLiquidityVault":"liquidityVault"}
    if set(m["runtimeHashes"]) != set(trace_names): fail("stage3b: runtime evidence incomplete")
    for name,key in trace_names.items():
        if ("new " + name + "@" + addrs[key]).lower() not in trace.lower() or not re.fullmatch(r"0x[0-9a-fA-F]{64}",m["runtimeHashes"][name]) or not any(m["runtimeHashes"][name].lower() in line.lower() and addrs[key].lower() in line.lower() and "emit RuntimeHash(" in line for line in trace.splitlines()):
            fail("stage3b: fork creation or runtime evidence mismatch")
    lim=m["limits"]; aggregate=uint(lim["aggregateWei"],"aggregate limit"); caps=lim["perTransactionWei"]; price=uint(lim["maxExecutionPriceWei"],"max price")
    if aggregate == 0 or int(snapshot["balanceWei"]) < aggregate or len(caps)!=3 or any(uint(v,"transaction limit")==0 for v in caps) or sum(caps)>aggregate or price!=15_000_000 or m["candidateCeilingWei"] != str(aggregate):
        fail("stage3b: invalid or unfunded expenditure envelope")
    estimates=m["estimates"]; total=0
    for i,k in enumerate(("verifier","adapter","factory")):
        e=estimates[k];gas=e["assumedGasLimit"] if k=="factory" else e["bufferedGasAssumption"]
        if type(gas) is not int or gas<=0 or not isinstance(e["syntheticL1Wei"],str) or not e["syntheticL1Wei"].isdigit() or not isinstance(e["operatorFeeWei"],str) or not e["operatorFeeWei"].isdigit(): fail("stage3b: itemized estimate invalid")
        if k != "factory" and (type(e["ethEstimateGas"]) is not int or e["ethEstimateGas"]<=0 or gas < e["ethEstimateGas"]): fail("stage3b: live constructor estimate missing or gas limit too low")
        if k == "factory" and (e["ethEstimateGas"] is not None or type(e["forkConstructorTraceGas"]) is not int or e["forkConstructorTraceGas"]<=0 or gas < e["forkConstructorTraceGas"]): fail("stage3b: factory assumption evidence invalid")
        cost=gas*price+int(e["syntheticL1Wei"])+int(e["operatorFeeWei"]);total+=cost
        if cost>caps[i]: fail("stage3b: per-transaction estimate exceeds limit")
    if total>aggregate or estimates["illustrativeTotalWei"] != str(total): fail("stage3b: aggregate estimate exceeds limit")
    auth=m["authorization"]
    if set(auth) != {"approved","consumed","evidence","approvedAggregateWei","approvedPerTransactionWei"} or type(auth["approved"]) is not bool or auth["consumed"] is not False: fail("stage3b: invalid or consumed authorization")
    if broadcast and (auth["approved"] is not True or m.get("broadcastAuthorized") is not True or m.get("ceilingApproved") is not True or not isinstance(auth["evidence"],str) or not auth["evidence"].strip() or type(auth["approvedAggregateWei"]) is not int or auth["approvedAggregateWei"] != aggregate or auth["approvedPerTransactionWei"] != caps or any(type(v) is not int for v in auth["approvedPerTransactionWei"])):
        fail("stage3b: explicit sequence authorization and ceilings required")
    print("Stage 3B offline preparation record accepted; " + ("authorization record present" if broadcast else "preparation only; no broadcast authorization conferred") + "; not full financial readiness. Refresh RPC state before each transaction.")


def run_stage3b(m, broadcast):
    artifacts={n:load_public(ROOT / "out" / (n + ".sol") / (n + ".json")) for n in STAGE3B_ARTIFACTS}
    trace=(ROOT / "deployments/m4e2.stage3b.fork-trace.txt").read_text(encoding="utf-8")
    validate_stage3b(m,load_public(ROOT / "deployments/m4.financial-readiness.proposed.json"),load_public(ROOT / "deployments/m4e2.stage1.verified.json"),load_public(ROOT / "deployments/m4e2.stage2.verified.json"),load_public(ROOT / "deployments/m4e2.stage3a.verified.json"),artifacts,trace,broadcast)

def main():
    if len(sys.argv) != 3 or sys.argv[2] not in ("plan", "wired", "stage3a", "stage3b-plan", "stage3b-broadcast"):
        fail("usage: check_m4_manifest.py MANIFEST plan|wired|stage3a|stage3b-plan|stage3b-broadcast")
    with open(sys.argv[1], encoding="utf-8") as stream:
        m = json.load(stream)
    scan(m)
    if sys.argv[2] == "stage3a":
        run_stage3a(m)
        return
    if sys.argv[2] in ("stage3b-plan", "stage3b-broadcast"):
        run_stage3b(m, sys.argv[2] == "stage3b-broadcast")
        return
    n, roles = m["networks"], m["roles"]
    for chain, chain_id, rpc in (("unichain", 1301, "https://sepolia.unichain.org"), ("base", 84532, "https://sepolia.base.org"), ("lasna", 5318007, "https://lasna-rpc.rnk.dev/")):
        if n[chain]["chainId"] != chain_id or n[chain]["rpc"] != rpc:
            fail(f"{chain}: unexpected chain or public RPC")
    if address(n["base"]["callbackProxy"], "callback proxy") != "0x476f44b11f5c942c58f4c8e3d0300e5710743585" or address(n["lasna"]["system"], "system") != "0x8888888888888888888888888888888888888888":
        fail("unexpected provider addresses")
    for name in ("deployer", "lender", "borrower", "callbackFundingAuthority", "tokenAuthority", "marketOperator", "oracleOperator", "reactiveOperator", "governance", "emergencyAuthority"):
        address(roles[name], name)
    address(n["unichain"]["binder"], "binder")
    signers = [address(v, "attestor") for v in roles["attestors"]]
    if len(signers) != 4 or len(set(signers)) != 4:
        fail("four unique attestors required")
    gov = m["governance"]
    if gov["threshold"] != 3 or gov["validitySeconds"] != 1800 or gov["rotationDelaySeconds"] != 86400 or not gov["approvedFinalityPolicy"]:
        fail("attestation policy unresolved or inconsistent")
    if not isinstance(gov["approvedFinalityPolicy"], str) or not gov["approvedFinalityPolicy"].strip():
        fail("approved finality policy reference required")
    route = m["financialRoute"]
    if route["originChainId"] != 84532 or route["destinationChainId"] != 84532 or not isinstance(route["callbackGas"], int) or not 1_000_000 <= route["callbackGas"] <= 3_000_000:
        fail("financial route or callback gas invalid")
    if route.get("callbackGasStatus") != "approved":
        fail("callback gas not approved")
    for name in ("financialReactiveReserveWei", "financialReceiverReserveWei"):
        value = m["funding"][name]
        if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
            fail(f"{name}: approved positive integer reserve required")
    ceilings = m["funding"]["financialCeilings"]
    if not isinstance(ceilings, dict):
        fail("financial expenditure ceilings unresolved")
    for name in ("baseWei", "unichainWei", "lasnaWei"):
        if isinstance(ceilings.get(name), bool) or not isinstance(ceilings.get(name), int) or ceilings[name] <= 0:
            fail(f"{name}: positive integer ceiling required")
    for name in ("ceilingLasnaLreact", "ceilingBaseEth", "ceilingUnichainEth"):
        value = m["funding"]["m1bTransport"].get(name)
        try:
            amount = Decimal(str(value))
            if not amount.is_finite() or amount <= 0:
                fail(f"{name}: positive transport ceiling required")
        except InvalidOperation:
            fail(f"{name}: positive transport ceiling required")
    if m.get("status") != "approved-for-deployment":
        fail("manifest is not approved for deployment")
    approvals = m["approvals"]
    approval_evidence = m["approvalEvidence"]
    for name in ("rolesAndCustody", "finalityPolicy", "governanceAndIncidentResponse", "demoDependencies", "callbackGasAndReserves", "networkExpenditureCeilings", "permanentCollateralLock", "m1bLiveTransportEvidence", "broadcastAuthorized"):
        if approvals.get(name) is not True or not isinstance(approval_evidence.get(name), str) or not approval_evidence[name].strip():
            fail(f"{name}: explicit approval and evidence reference required")
    for name in ("unichainToBase", "baseToUnichain", "baseToBase"):
        evidence = m["m1bRouteEvidence"].get(name)
        if not isinstance(evidence, str) or not evidence.strip():
            fail(f"{name}: live transport evidence reference required")
    if sys.argv[2] == "wired":
        for chain, fields in (("unichain", ("collateralVault",)), ("base", ("demoAsset", "oracle", "market", "adapter", "attestationVerifier", "demoFactory", "nestedFactory", "manager", "liquidityVault", "signalRegistry", "financialReceiver")), ("lasna", ("financialReactive",))):
            for field in fields:
                address(n[chain][field], f"{chain}.{field}")
        for field, chain, entry in (("registry", "base", "signalRegistry"), ("manager", "base", "manager"), ("receiver", "base", "financialReceiver"), ("reactive", "lasna", "financialReactive")):
            if address(route[field], field) != address(n[chain][entry], entry):
                fail(f"route {field} does not match network deployment")
    print("Configuration structure accepted; verify approval authenticity, receipts, bytecode and on-chain bindings independently.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, json.JSONDecodeError) as error:
        print(f"Configuration rejected: {error}", file=sys.stderr)
        sys.exit(1)
