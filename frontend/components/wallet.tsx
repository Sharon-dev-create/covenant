'use client';

import { useEffect, useState } from 'react';
import { Wallet } from 'lucide-react';
import { walletNetwork } from '../lib/chains';

type Provider = {
  request(args: { method: string }): Promise<unknown>;
  on?(event: string, listener: (value: unknown) => void): void;
  removeListener?(event: string, listener: (value: unknown) => void): void;
};

const provider = () => (window as Window & { ethereum?: Provider }).ethereum;
const address = (value: unknown) => Array.isArray(value) && typeof value[0] === 'string' && /^0x[0-9a-f]{40}$/i.test(value[0]) ? value[0] : null;
const chain = (value: unknown) => typeof value === 'string' && /^0x[0-9a-f]+$/i.test(value) ? Number(value) : null;

export function WalletControl() {
  const [account, setAccount] = useState<string | null>(null);
  const [chainId, setChainId] = useState<number | null>(null);
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState('');
  const network = walletNetwork(chainId);

  useEffect(() => {
    const wallet = provider();
    if (!wallet) return;
    let active = true;
    let accountChanged = false;
    let chainChanged = false;
    const onAccount = (value: unknown) => { accountChanged = true; setAccount(address(value)); };
    const onChain = (value: unknown) => { chainChanged = true; setChainId(chain(value)); };
    const onDisconnect = () => { onAccount([]); onChain(null); };
    wallet.on?.('accountsChanged', onAccount);
    wallet.on?.('chainChanged', onChain);
    wallet.on?.('disconnect', onDisconnect);
    void wallet.request({ method: 'eth_accounts' }).then(value => {
      if (active && !accountChanged) setAccount(address(value));
    }).catch(() => {});
    void wallet.request({ method: 'eth_chainId' }).then(value => {
      if (active && !chainChanged) setChainId(chain(value));
    }).catch(() => {});
    return () => {
      active = false;
      wallet.removeListener?.('accountsChanged', onAccount);
      wallet.removeListener?.('chainChanged', onChain);
      wallet.removeListener?.('disconnect', onDisconnect);
    };
  }, []);

  async function connect() {
    const wallet = provider();
    if (!wallet) { setMessage('No browser wallet detected.'); return; }
    setMessage('');
    setPending(true);
    try {
      const connected = address(await wallet.request({ method: 'eth_requestAccounts' }));
      setAccount(connected);
      setChainId(chain(await wallet.request({ method: 'eth_chainId' })));
      if (!connected) setMessage('The wallet returned no accounts.');
    } catch {
      setMessage('Wallet connection was declined or unavailable.');
    } finally {
      setPending(false);
    }
  }

  return <div className="wallet">
    {account ? <span className="wallet-account" title={account}><Wallet size={16} aria-hidden />{account.slice(0, 6)}…{account.slice(-4)}</span>
      : <button className="button wallet-button" type="button" onClick={connect} disabled={pending}><Wallet size={16} aria-hidden />{pending ? 'Connecting…' : 'Connect wallet'}</button>}
    <div role="status" className="wallet-status">{message || (account ? network?.name ?? 'Use Base or Unichain Sepolia' : '')}</div>
  </div>;
}
