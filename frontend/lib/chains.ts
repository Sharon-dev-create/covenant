export const chains = {
  base: { id: 84532, name: 'Base Sepolia', role: 'Financial execution', access: 'wallet', color: 'blue' },
  unichain: { id: 1301, name: 'Unichain Sepolia', role: 'Collateral custody', access: 'wallet', color: 'pink' },
  lasna: { id: 5318007, name: 'Reactive Lasna', role: 'Event orchestration', access: 'read-only', color: 'mint' },
} as const;

export type ChainKey = keyof typeof chains;
export function walletNetwork(chainId: number | null) {
  return Object.values(chains).find(chain => chain.access === 'wallet' && chain.id === chainId);
}
