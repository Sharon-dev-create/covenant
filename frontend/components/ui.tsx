import type { ReactNode } from 'react';
import Link from 'next/link';
import { CovenantLogo } from './CovenantLogo';
import { chains, type ChainKey } from '../lib/chains';
import type { Activity, Agreement, DataState, TransactionState } from '../lib/data';
import { allocationPercent, formatUnits } from '../lib/finance';

export function Brand({ size = 36 }: { size?: number }) {
  return <Link href="/" className="brand"><CovenantLogo variant="wordmark" size={size} /></Link>;
}

export function PageHeader({ title, children }: { title: string; children: ReactNode }) {
  return <header className="page-header"><h1>{title}</h1><p>{children}</p></header>;
}

export function TokenAmount({ value, asset = 'cMOCK' }: { value: bigint; asset?: 'cMOCK' | 'test ETH' }) {
  return <span className="token">{formatUnits(value, asset === 'cMOCK' ? 6 : 18)} <small>{asset}</small></span>;
}

export function Network({ network }: { network: ChainKey }) {
  const { name, color } = chains[network];
  return <span className="network"><i className={color} aria-hidden />{name}</span>;
}

export function ModeIndicator({ live }: { live: boolean }) {
  return <span className="mode"><i aria-hidden />{live ? 'Live testnet mode' : 'Demonstration mode'}</span>;
}

export function AgreementStatus({ status }: { status: Agreement['status'] }) {
  return <span className="badge" data-status={status}>{status}</span>;
}

export function TransactionStatus({ status }: { status: TransactionState }) {
  return <span className="badge" data-status={status}>{status}</span>;
}

export function Panel({ title, action, children }: { title: string; action?: ReactNode; children: ReactNode }) {
  return <section className="panel"><div className="panel-heading"><h2>{title}</h2>{action}</div>{children}</section>;
}

export function Allocation({ free, reserved }: { free: bigint; reserved: bigint }) {
  const total = free + reserved;
  const freePercent = allocationPercent(free, total);
  const reservedPercent = allocationPercent(reserved, total);
  return <div className="allocation">
    <div className="allocation-total"><TokenAmount value={total} /><span>Managed cash</span></div>
    <div className="allocation-bar" aria-hidden="true"><i style={{ width: freePercent + '%' }} /><i style={{ width: reservedPercent + '%' }} /></div>
    <dl className="allocation-legend">
      <div><dt><i />Free liquidity</dt><dd><TokenAmount value={free} /><span>{freePercent}%</span></dd></div>
      <div><dt><i />Reserved liquidity</dt><dd><TokenAmount value={reserved} /><span>{reservedPercent}%</span></dd></div>
    </dl>
  </div>;
}

export function Timeline({ entries }: { entries: readonly Activity[] }) {
  if (!entries.length) return <DataNotice kind="empty" />;
  return <ol className="timeline">{entries.map(entry => <li key={entry.title}>
    <div className="event-meta"><Network network={entry.chain} /><TransactionStatus status={entry.status} /></div>
    <h3>{entry.title}</h3><p>{entry.description}</p>
  </li>)}</ol>;
}

export function ResponsiveTable({ headers, children }: { headers: string[]; children: ReactNode }) {
  return <div className="table-wrap" role="region" aria-label="Credit agreements table" tabIndex={0}>
    <table><thead><tr>{headers.map(header => <th scope="col" key={header}>{header}</th>)}</tr></thead><tbody>{children}</tbody></table>
  </div>;
}

const stateText = {
  empty: ['No records', 'There are no records for this view.'],
  unconfigured: ['Deployment unconfigured', 'Live data requires a reviewed testnet deployment manifest.'],
  unavailable: ['Live network data unavailable', 'The manifest is configured. Live contract reads are outside M7-A.'],
  failed: ['Request failed', 'The data request could not be completed. Reload the page to try again.'],
};

export function DataNotice({ kind }: { kind: Exclude<DataState<unknown>['kind'], 'ready'> }) {
  if (kind === 'loading') return <section className="panel skeleton" aria-busy="true"><span role="status">Loading dashboard data…</span><i /><i /><i /></section>;
  const [title, detail] = stateText[kind];
  return <section className="panel" role={kind === 'failed' ? 'alert' : undefined}><h2>{title}</h2><p>{detail}</p></section>;
}
