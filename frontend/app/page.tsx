import Link from 'next/link';
import { ThemeToggle } from '../components/theme-toggle';
import { CovenantGuardian } from '../components/guardian/covenant-guardian';
import { Brand, Network } from '../components/ui';
import { chains, type ChainKey } from '../lib/chains';

export default function Home() {
  return <div className="home">
    <header className="home-header"><Brand /><div className="home-header-actions"><ThemeToggle /><Link className="button" href="/dashboard/demo">Guided demonstration</Link></div></header>
    <main id="main" tabIndex={-1}>
      <section className="home-main" aria-labelledby="home-title">
        <div className="home-copy">
          <p className="eyebrow">Cross-chain liquidity infrastructure</p>
          <h1 id="home-title">Capital committed.<br />Liquidity when it matters.</h1>
          <p className="home-description">Covenant lets lenders reserve capital in advance so an eligible distressed position can receive a bounded, purpose-specific debt repayment.</p>
          <Link className="button primary" href="/dashboard">Open dashboard</Link>
        </div>
        <CovenantGuardian />
      </section>
      <section className="home-architecture" aria-labelledby="architecture-title">
        <h2 id="architecture-title">Protocol architecture</h2>
        <ul>
          {(Object.keys(chains) as ChainKey[]).map(key => <li key={key}><Network network={key} /><p>{chains[key].role}</p></li>)}
        </ul>
      </section>
    </main>
    <footer className="brand-footer"><Brand size={24} /><span>Reactive Omni Buildathon · Testnet demonstration</span></footer>
  </div>;
}
