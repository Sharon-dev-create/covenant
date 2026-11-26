import { chains } from './chains.ts';

type Address = `0x${string}`;
type RecordValue = Record<string, unknown>;
const fields = {
  base: ['demoAsset', 'oracle', 'market', 'adapter', 'attestationVerifier', 'manager', 'liquidityVault', 'signalRegistry', 'financialReceiver'],
  unichain: ['collateralVault'],
  lasna: ['financialReactive'],
} as const;
type VerifiedAddresses = { [K in keyof typeof fields]: Record<(typeof fields)[K][number], Address> };

function record(value: unknown): RecordValue {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as RecordValue : {};
}

export function parseReviewedManifest(input: unknown) {
  const root = record(input);
  const networks = record(root.networks);
  const buckets = Object.entries(fields).map(([key, names]) => {
    const network = record(networks[key]);
    if (network.chainId !== chains[key as keyof typeof chains].id) return null;
    const entries = names.map(name => [name, network[name]] as const);
    if (entries.some(([, address]) => typeof address !== 'string' || !/^0x[0-9a-fA-F]{40}$/.test(address) || /^0x0{40}$/.test(address))) return null;
    return [key, Object.fromEntries(entries)] as const;
  });
  if (!root.revision || root.status === 'template-not-deployed' || buckets.some(bucket => bucket === null)) {
    return { status: 'unconfigured' } as const;
  }
  return { status: 'configured', addresses: Object.fromEntries(buckets.filter(bucket => bucket !== null)) as VerifiedAddresses } as const;
}
