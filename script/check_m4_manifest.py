#!/usr/bin/env python3
"""Offline check of public deployment configuration; never reads keys or connects to RPCs."""
import json
from decimal import Decimal, InvalidOperation
import re
import sys


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


def main():
    if len(sys.argv) != 3 or sys.argv[2] not in ("plan", "wired"):
        fail("usage: check_m4_manifest.py MANIFEST plan|wired")
    with open(sys.argv[1], encoding="utf-8") as stream:
        m = json.load(stream)
    scan(m)
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
