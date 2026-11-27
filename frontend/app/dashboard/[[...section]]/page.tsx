import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Brand, DataNotice, ModeIndicator, PageHeader, Panel } from '../../../components/ui';
import { Navigation } from '../../../components/navigation';
import { ThemeToggle } from '../../../components/theme-toggle';
import { WalletControl } from '../../../components/wallet';
import { DashboardContent, pageCopy, resolveView } from '../../../components/dashboard';
import { overviewProvider } from '../../../lib/source';
import type { DataState, Overview } from '../../../lib/data';

type Props = {
  params: Promise<{ section?: string[] }>;
  searchParams: Promise<{ mode?: string | string[] }>;
};

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const view = resolveView((await params).section ?? []);
  return { title: view ? pageCopy[view].title : 'Page unavailable' };
}

export default async function Dashboard({ params, searchParams }: Props) {
  const [{ section = [] }, { mode }] = await Promise.all([params, searchParams]);
  const view = resolveView(section);
  if (!view) notFound();
  const source = overviewProvider(mode);
  const live = source.mode === 'live';
  const suffix = live ? '?mode=live' : '';
  const copy = pageCopy[view];
  let state: DataState<Overview>;
  try {
    state = await source.read();
  } catch {
    state = { kind: 'failed' };
  }
  if (view === 'detail' && state.kind === 'ready' && !state.data.agreements.some(agreement => agreement.id === section[1])) notFound();

  return <div className="shell">
    <header className="console-header">
      <div className="console-masthead">
        <Brand />
        <div className="console-context">
          <div className="topbar-mode"><ModeIndicator live={live} /><Link className="text-link" href={'/dashboard' + (section.length ? '/' + section.join('/') : '') + (live ? '' : '?mode=live')}>{live ? 'View demonstration' : 'View live testnet'}</Link></div>
          <div className="console-actions"><ThemeToggle /><WalletControl /></div>
        </div>
      </div>
      <Navigation live={live} />
    </header>
    <div className="workspace">
      <main id="main" className="dashboard" tabIndex={-1}>
        <PageHeader title={copy.title}>{copy.description}</PageHeader>
        {!live && <div className="demo-note"><strong>Simulated data</strong><span>Pre-execution snapshot</span></div>}
        {view === 'create' && <Panel title="Agreement creation">
          <p>Agreement drafting, signing, and registration are outside M7-A.</p>
          <Link className="text-link" href={'/dashboard/agreements' + suffix}>Back to credit agreements</Link>
        </Panel>}
        {state.kind !== 'ready' ? <DataNotice kind={state.kind} /> : <DashboardContent view={view} agreementId={section[1]} overview={state.data} />}
      </main>
      <footer className="brand-footer console-footer"><Brand size={24} /></footer>
    </div>
  </div>;
}
