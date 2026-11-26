import Link from 'next/link';
import { CovenantGuardian } from '../components/guardian/covenant-guardian';
import { Brand, Network } from '../components/ui';
import { chains, type ChainKey } from '../lib/chains';

export default function Home() {
  return <div className="home">
    <header className="home-header"><Brand /><Link className="button" href="/dashboard/demo">Guided demonstration</Link></header>
    <main id="main" className="home-main" tabIndex={-1}>
      <div>
        <p className="eyebrow">Cross-chain liquidity infrastructure</p>
        <h1>Capital committed.<br />Liquidity when it matters.</h1>
        <p className="home-description">Covenant lets lenders reserve capital in advance so an eligible distressed position can receive a bounded, purpose-specific debt repayment.</p>
        <Link className="button primary" href="/dashboard">Open dashboard</Link>
      </div>
      <CovenantGuardian>
        <h3>Protocol architecture</h3>
        {(Object.keys(chains) as ChainKey[]).map(key => <div key={key}><Network network={key} /><p>{chains[key].role}</p></div>)}
      </CovenantGuardian>
    </main>
    <footer>Reactive Omni Buildathon · Testnet demonstration</footer>
  </div>;
}
