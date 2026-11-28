"""Synthetic negative controls: mutations of copied public fixtures, not live evidence."""
import copy
import importlib.util
import io
from contextlib import redirect_stdout
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('m4_validator', ROOT / 'script/check_m4_manifest.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)

def read(p):
    return json.loads((ROOT / p).read_text())

class Stage3AValidationTests(unittest.TestCase):
    def setUp(self):
        self.m = read('deployments/m4e2.stage3a.pending.json')
        self.o = read('deployments/m4.financial-readiness.proposed.json')
        # Synthetic pre-deployment fixture: the real Stage 3A may already be closed.
        self.m['status'] = 'stage3a-authorized-market-preflight-passed-not-broadcast'
        self.m['marketReceipt'] = None
        self.o['stage3AMarketProposal']['status'] = 'authorized-preflight-passed-not-broadcast'
        self.s1 = read('deployments/m4e2.stage1.verified.json')
        self.s2 = read('deployments/m4e2.stage2.verified.json')
        self.sim = read('deployments/m4e2.stage3a.simulation.json')
        self.art = read('out/DemoMarket.sol/DemoMarket.json')
    def validate(self):
        v.validate_stage3a(self.m,self.o,self.s1,self.s2,self.sim,self.art)
    def rejected(self):
        with self.assertRaises((ValueError,KeyError,TypeError)):
            self.validate()
    def test_valid_scoped_pass(self):
        out=io.StringIO()
        with redirect_stdout(out): self.validate()
        self.assertIn("Validated command:",out.getvalue())
        self.assertIn("deployMarket(address,address)",out.getvalue())
        self.assertNotIn("deployAdapter(",out.getvalue())
    def test_full_plan_stays_blocked(self):
        p=subprocess.run(['python3',str(ROOT/'script/check_m4_manifest.py'),str(ROOT/'deployments/m4.financial-readiness.proposed.json'),'plan'],capture_output=True,text=True)
        self.assertNotEqual(p.returncode,0); self.assertIn('callback gas not approved',p.stderr)
    def test_no_full_readiness(self):
        self.validate();self.assertNotEqual(self.o['status'],'approved-for-deployment');self.assertFalse(self.o['approvals']['broadcastAuthorized'])
    def test_missing_authorization(self): self.m['broadcastAuthorized']=False;self.rejected()
    def test_incorrect_chain(self): self.m['chainId']=1301;self.rejected()
    def test_incorrect_signer(self): self.m['signer']='0x'+'12'*20;self.rejected()
    def test_incorrect_operator(self): self.m['operator']='0x'+'12'*20;self.rejected()
    def test_incorrect_token(self): self.m['token']='0x'+'12'*20;self.rejected()
    def test_missing_prerequisite(self): self.s2['deploymentReceipt']=None;self.rejected()
    def test_conflicting_nonce(self): self.m['snapshot']['pendingNonce']=16;self.rejected()
    def test_incorrect_nonce(self): self.m['snapshot']['latestNonce']=16;self.m['snapshot']['pendingNonce']=16;self.rejected()
    def test_bad_address(self): self.m['predictedAddressAtNonce15']='0x'+'12'*20;self.rejected()
    def test_missing_simulation(self): self.m.pop('simulationEvidence');self.rejected()
    def test_exceeds_budget(self): self.m['syntheticL1FeeWei']=60000000000001;self.rejected()
    def test_other_chain_spend(self): self.m['proposedStage3ACeilingsWei']['lasna']=1;self.rejected()
    def test_participant_funding(self): self.m['scope']['participantFundingWei']=1;self.rejected()
    def test_provider_funding(self): self.m['scope']['providerReserveWei']=1;self.rejected()
    def test_token_issuance(self): self.m['scope']['tokenIssuance']=True;self.rejected()
    def test_market_configuration(self): self.m['scope']['marketConfiguration']=True;self.rejected()
    def test_other_action(self): self.m['validatedAction']['contract']='DemoAdapter';self.rejected()
    def test_second_creation(self): self.sim['transactions'].append(copy.deepcopy(self.sim['transactions'][0]));self.rejected()
    def test_changed_calldata(self): self.sim['transactions'][0]['transaction']['input']='0x00';self.rejected()
    def test_artifact_change(self): self.art['bytecode']['object']='0x6000';self.rejected()
    def test_unknown_stage(self):
        p=subprocess.run(['python3',str(ROOT/'script/check_m4_manifest.py'),str(ROOT/'deployments/m4e2.stage3a.pending.json'),'stage3b'],capture_output=True,text=True)
        self.assertNotEqual(p.returncode,0)
    def test_manifest_cannot_define_checks(self): self.m['scope']['skipChecks']=True;self.rejected()
    def test_bad_constructor(self): self.m['validatedAction']['arguments'][0]='0x'+'12'*20;self.rejected()
    def test_nonempty_code(self): self.m['predictedAddressCodeAtPreflight']='0x6000';self.rejected()
    def test_stage_id(self): self.m['stageId']='stage3b';self.rejected()


class Stage3BValidationTests(unittest.TestCase):
    """Synthetic copies and mutations; approval is controlled independently of the operational manifest."""
    def setUp(self):
        self.m=read('deployments/m4e2.stage3b.pending.json')
        self.m['authorization']={'approved':False,'consumed':False,'evidence':None,'approvedAggregateWei':None,'approvedPerTransactionWei':None}
        self.m['broadcastAuthorized']=False;self.m['ceilingApproved']=False
        self.o=read('deployments/m4.financial-readiness.proposed.json')
        self.s1=read('deployments/m4e2.stage1.verified.json')
        self.s2=read('deployments/m4e2.stage2.verified.json')
        self.s3=read('deployments/m4e2.stage3a.verified.json')
        self.art={n:read(f'out/{n}.sol/{n}.json') for n in v.STAGE3B_ARTIFACTS}
        self.trace=(ROOT/'deployments/m4e2.stage3b.fork-trace.txt').read_text()
    def validate(self,broadcast=False):
        v.validate_stage3b(self.m,self.o,self.s1,self.s2,self.s3,self.art,self.trace,broadcast)
    def rejected(self,broadcast=False):
        with self.assertRaises((ValueError,KeyError,TypeError)): self.validate(broadcast)
    def approve_synthetic(self):
        self.m['authorization']={'approved':True,'consumed':False,'evidence':'SYNTHETIC TEST ONLY','approvedAggregateWei':self.m['limits']['aggregateWei'],'approvedPerTransactionWei':self.m['limits']['perTransactionWei'][:]}
        self.m['broadcastAuthorized']=True;self.m['ceilingApproved']=True
    def test_preparation_without_broadcast_approval_passes(self): self.validate()
    def test_broadcast_without_approval_rejected(self): self.rejected(True)
    def test_synthetic_exact_approval_passes(self): self.approve_synthetic();self.validate(True)
    def test_incorrect_order(self): self.m['orderedActions'].reverse();self.rejected()
    def test_unexpected_nonce(self): self.m['snapshot']['latestNonce']=17;self.rejected()
    def test_pending_nonce(self): self.m['snapshot']['pendingNonce']=17;self.rejected()
    def test_wrong_nested_factory(self): self.m['conditionalAddresses']['nestedFactory']='0x'+'12'*20;self.rejected()
    def test_wrong_manager(self): self.m['conditionalAddresses']['manager']='0x'+'12'*20;self.rejected()
    def test_adapter_manager_disagrees(self): self.m['orderedActions'][1]['arguments'][2]='0x'+'12'*20;self.rejected()
    def test_verifier_manager_disagrees(self): self.m['orderedActions'][0]['arguments'][1]='0x'+'12'*20;self.rejected()
    def test_missing_prerequisite(self): self.s3['marketReceipt']=None;self.rejected()
    def test_missing_fork(self): self.trace='';self.rejected()
    def test_unauthorized_extra_transaction(self): self.m['scope']['actions'].append('transfer');self.rejected()
    def test_aggregate_expenditure_exceeded(self): self.m['estimates']['factory']['syntheticL1Wei']=str(10**18);self.rejected()
    def test_per_transaction_cap_exceeded(self): self.m['limits']['perTransactionWei'][0]=1;self.rejected()
    def test_participant_funding(self): self.m['scope']['participantFundingWei']=1;self.rejected()
    def test_provider_funding(self): self.m['scope']['providerReserveWei']=1;self.rejected()
    def test_other_network_spending(self): self.m['scope']['lasnaWei']=1;self.rejected()
    def test_unrelated_contract(self): self.m['orderedActions'][0]['contract']='FinancialReactive';self.rejected()
    def test_closed_stage(self): self.m['status']='stage3b-closed';self.rejected()
    def test_consumed_authorization(self): self.approve_synthetic();self.m['authorization']['consumed']=True;self.rejected(True)
    def test_authorized_limits_mismatch(self): self.approve_synthetic();self.m['authorization']['approvedAggregateWei']-=1;self.rejected(True)
    def test_artifact_change(self): self.art['DemoAdapter']['bytecode']['object']='0x6000';self.rejected()
    def test_callback_configuration_forbidden(self): self.m['scope']['callbackConfiguration']=True;self.rejected()
    def test_no_full_readiness(self): self.validate();self.assertFalse(self.o['approvals']['broadcastAuthorized'])
    def test_closed_stage3a_not_reusable(self):
        p=subprocess.run(['python3',str(ROOT/'script/check_m4_manifest.py'),str(ROOT/'deployments/m4e2.stage3a.pending.json'),'stage3a'],capture_output=True,text=True)
        self.assertNotEqual(p.returncode,0); self.assertIn('incorrect stage or state',p.stderr)
    def test_mismatched_fork_runtime(self): self.m['runtimeHashes']['DemoAdapter']=self.m['runtimeHashes']['DemoDeploymentFactory'];self.rejected()
    def test_factory_gas_less_than_trace(self): self.m['estimates']['factory']['assumedGasLimit']=1;self.rejected()
    def test_changed_attestor(self): self.o['roles']['attestors'][0]='0x'+'12'*20;self.rejected()

if __name__ == '__main__': unittest.main()
