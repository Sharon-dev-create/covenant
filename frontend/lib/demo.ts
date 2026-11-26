import type { Overview, OverviewProvider } from './data.ts';

const snapshot = {
  free: 700_000_000n,
  reserved: 300_000_000n,
  principal: 0n,
  collateral: 1_000_000_000_000_000n,
  marketDebt: 800_000_000n,
  agreements: [{ id: 'demo-001', name: 'Purpose-bound repayment', status: 'Active', commitment: 300_000_000n, authorized: 200_000_000n, aprBps: 500n, ltvBps: 5000n }],
  activity: [
    { title: 'Callback requested', description: 'Illustrative request. Execution is still pending in this scenario.', chain: 'lasna', status: 'illustrative' },
    { title: 'Distress signal emitted', description: 'The simulated market position has 800 cMOCK in debt.', chain: 'base', status: 'illustrative' },
    { title: 'Backstop activated', description: '300 cMOCK reserved for the agreement.', chain: 'base', status: 'illustrative' },
    { title: 'Collateral locked', description: '0.001 test ETH in Unichain custody.', chain: 'unichain', status: 'illustrative' },
  ],
} as const satisfies Overview;

export const demoProvider = {
  mode: 'demo',
  async read() { return { kind: 'ready', data: snapshot }; },
} satisfies OverviewProvider;
