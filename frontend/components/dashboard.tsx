import Link from 'next/link';
import { chains, type ChainKey } from '../lib/chains';
import type { Agreement, Overview } from '../lib/data';
import { formatUnits } from '../lib/finance';
import { AgreementStatus, Allocation, DataNotice, Network, Panel, ResponsiveTable, Timeline, TokenAmount } from './ui';

export const pageCopy = {
  overview: { title: 'Protocol overview', description: 'Monitor liquidity, collateral custody, and cross-chain activity in one workspace.' },
  agreements: { title: 'Credit agreements', description: 'Review committed capital, authorized repayment, and agreement status.' },
  create: { title: 'Create agreement', description: 'Foundation for future agreement origination.' },
  detail: { title: 'Agreement details', description: 'Review the terms and state of the demonstration agreement.' },
  liquidity: { title: 'Liquidity', description: 'Track free cash, reserved commitments, and outstanding principal.' },
  collateral: { title: 'Collateral', description: 'Review the demonstration lock on Unichain Sepolia.' },
  activity: { title: 'Reactive activity', description: 'Follow the illustrated signal, callback request, and financial lifecycle.' },
  demo: { title: 'Guided demonstration', description: 'Walk through the pre-execution snapshot and the expected repayment outcome.' },
};

type View = keyof typeof pageCopy;
export function resolveView(parts: string[]): View | undefined {
  if (!parts.length) return 'overview';
  if (parts[0] === 'agreements' && parts.length === 2) return parts[1] === 'create' ? 'create' : 'detail';
  if (parts.length === 1 && ['agreements', 'liquidity', 'collateral', 'activity', 'demo'].includes(parts[0])) return parts[0] as View;
}

const toDashboard = (path: string) => '/dashboard/' + path;
function ViewLink({ path, children }: { path: string; children: React.ReactNode }) {
  return <Link className="text-link" href={toDashboard(path)}>{children}</Link>;
}

function Agreements({ agreements }: { agreements: Overview['agreements'] }) {
  if (!agreements.length) return <DataNotice kind="empty" />;
  return <ResponsiveTable headers={['Agreement', 'Commitment', 'Status']}>
    {agreements.map(item => <tr key={item.id}>
      <th scope="row"><ViewLink path={'agreements/' + item.id}>{item.name}</ViewLink><span className="table-id">{item.id}</span></th>
      <td><TokenAmount value={item.commitment} /></td><td><AgreementStatus status={item.status} /></td>
    </tr>)}
  </ResponsiveTable>;
}

function AgreementDetails({ agreement, marketDebt }: { agreement: Agreement; marketDebt: bigint }) {
  return <Panel title={agreement.name} action={<AgreementStatus status={agreement.status} />}>
    <dl className="detail-list">
      <div><dt>Agreement</dt><dd>{agreement.id}</dd></div>
      <div><dt>Commitment</dt><dd><TokenAmount value={agreement.commitment} /></dd></div>
      <div><dt>Simulated external debt</dt><dd><TokenAmount value={marketDebt} /></dd></div>
      <div><dt>Authorized repayment</dt><dd><TokenAmount value={agreement.authorized} /></dd></div>
      <div><dt>Simple interest</dt><dd>{formatUnits(agreement.aprBps, 2)}% annually</dd></div>
      <div><dt>Maximum LTV</dt><dd>{formatUnits(agreement.ltvBps, 2)}%</dd></div>
    </dl>
    <ViewLink path="agreements">Back to credit agreements</ViewLink>
  </Panel>;
}

function LiquidityLedger({ overview, showCollateral = false }: { overview: Overview; showCollateral?: boolean }) {
  const { free, reserved, principal, collateral } = overview;
  return <section className="liquidity-ledger" aria-labelledby="liquidity-ledger-title">
    <div className="ledger-cash">
      <div className="panel-heading"><h2 id="liquidity-ledger-title">Vault liquidity</h2>{showCollateral && <ViewLink path="liquidity">View liquidity</ViewLink>}</div>
      <Allocation free={free} reserved={reserved} />
    </div>
    <div className="ledger-exposure">
      <div className="panel-heading"><h2>Exposure</h2></div>
      <dl>
        <div><dt>Outstanding principal</dt><dd><TokenAmount value={principal} /></dd></div>
        {showCollateral && <div><dt><ViewLink path="collateral">Locked collateral</ViewLink></dt><dd><TokenAmount value={collateral} asset="test ETH" /></dd></div>}
      </dl>
      <p>Principal is a receivable. Vault cash includes free and reserved liquidity.</p>
    </div>
  </section>;
}

function Networks() {
  return <Panel title="Network infrastructure"><div className="network-grid">
    {(Object.keys(chains) as ChainKey[]).map(key => <article key={key}>
      <Network network={key} /><p>{chains[key].role}</p>
      <small>Chain {chains[key].id} · {chains[key].access === 'wallet' ? 'Wallet supported' : 'Read-only monitoring'}</small>
    </article>)}
  </div></Panel>;
}

export function DashboardContent({ view, overview, agreementId }: { view: View; overview: Overview; agreementId?: string }) {
  const { collateral, agreements, activity, marketDebt } = overview;
  switch (view) {
    case 'overview':
      return <>
        <LiquidityLedger overview={overview} showCollateral />
        <div className="overview-grid">
          <Panel title="Credit agreements" action={<ViewLink path="agreements">View agreements</ViewLink>}><Agreements agreements={agreements} /></Panel>
          <Panel title="Recent activity" action={<ViewLink path="activity">View activity</ViewLink>}><Timeline entries={activity} /></Panel>
        </div>
        <Networks />
      </>;
    case 'agreements':
      return <Panel title="Agreement register" action={<ViewLink path="agreements/create">Creation overview</ViewLink>}><Agreements agreements={agreements} /></Panel>;
    case 'detail': {
      const agreement = agreements.find(item => item.id === agreementId);
      return agreement ? <AgreementDetails agreement={agreement} marketDebt={marketDebt} /> : <DataNotice kind="empty" />;
    }
    case 'liquidity':
      return <LiquidityLedger overview={overview} />;
    case 'collateral':
      return <Panel title="Demonstration collateral" action={<Network network="unichain" />}>
        <div className="record-amount"><TokenAmount value={collateral} asset="test ETH" /></div>
        <p>The demonstration assumes an exact lock in Unichain custody. The current vault has no release path. Collateral finality and attestation acceptance require separate evidence.</p>
      </Panel>;
    case 'activity':
      return <Panel title="Financial and Reactive timeline"><Timeline entries={activity} /></Panel>;
    case 'demo':
      return <Panel title="Scenario walkthrough" action={<ViewLink path="agreements/demo-001">Review agreement terms</ViewLink>}>
        <ol className="demo-steps">
          <li>Deposit 1,000 cMOCK, then reserve 300 cMOCK for the agreement. This leaves 700 cMOCK free.</li>
          <li>Lock 0.001 test ETH on Unichain. After independent finality review and attestation, the agreement can activate.</li>
          <li>Emit a signal for the simulated position with 800 cMOCK in external debt. Lasna observes it and requests a Base callback.</li>
          <li>In a successful outcome, Base applies 200 cMOCK to the designated debt. Base then records 200 cMOCK principal, frees the unused reserve, and leaves 800 cMOCK free.</li>
        </ol>
        <p>The dashboard shows the scenario before the illustrated repayment. The callback request alone does not establish execution.</p>
      </Panel>;
    case 'create':
      return null;
  }
}
