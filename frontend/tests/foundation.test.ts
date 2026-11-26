import assert from 'node:assert/strict';
import { test } from 'node:test';
import { walletNetwork } from '../lib/chains.ts';
import { demoProvider } from '../lib/demo.ts';
import { parseReviewedManifest } from '../lib/deployment.ts';
import { formatUnits, allocationPercent } from '../lib/finance.ts';
import { overviewProvider } from '../lib/source.ts';

test('pre-execution snapshot reconciles cash and keeps authorized repayment outside principal', async () => {
  const state = await demoProvider.read();
  assert.equal(state.data.free + state.data.reserved, 1_000_000_000n);
  assert.equal(state.data.principal, 0n);
  assert.equal(state.data.agreements[0].authorized, 200_000_000n);
  assert.equal(state.data.activity[0].status, 'illustrative');
});

test('formatting preserves subunits and avoids lossy large-token arithmetic', () => {
  assert.equal(formatUnits(9007199254740993000001n, 6), '9,007,199,254,740,993.000001');
  assert.equal(formatUnits(1_000_000_000_000_000n, 18), '0.001');
  assert.equal(allocationPercent(700n, 1000n), 70);
  assert.equal(allocationPercent(0n, 0n), 0);
});

test('wallet networks exclude Lasna and mainnet', () => {
  assert.equal(walletNetwork(84532)?.name, 'Base Sepolia');
  assert.equal(walletNetwork(1301)?.name, 'Unichain Sepolia');
  assert.equal(walletNetwork(5318007), undefined);
  assert.equal(walletNetwork(1), undefined);
});

test('reviewed manifests require all network IDs and nonzero address entries', () => {
  const address = '0x' + 'ab'.repeat(20);
  const manifest = {
    status: 'reviewed',
    revision: 'test-revision',
    networks: {
      base: { chainId: 84532, demoAsset: address, oracle: address, market: address, adapter: address, attestationVerifier: address, manager: address, liquidityVault: address, signalRegistry: address, financialReceiver: address },
      unichain: { chainId: 1301, collateralVault: address },
      lasna: { chainId: 5318007, financialReactive: address },
    },
  };
  assert.equal(parseReviewedManifest(manifest).status, 'configured');
  manifest.networks.lasna.chainId = 1;
  assert.equal(parseReviewedManifest(manifest).status, 'unconfigured');
  manifest.networks.lasna.chainId = 5318007;
  manifest.networks.lasna.financialReactive = '0x' + '0'.repeat(40);
  assert.equal(parseReviewedManifest(manifest).status, 'unconfigured');
});

test('explicit live mode never falls back to demonstration data', async () => {
  const result = await overviewProvider('live').read();
  assert.ok(result.kind === 'unconfigured' || result.kind === 'unavailable');
  assert.equal(overviewProvider(undefined).mode, 'demo');
});
