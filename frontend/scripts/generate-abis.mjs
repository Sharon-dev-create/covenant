import { mkdir, readFile, writeFile } from 'node:fs/promises';

const selection = {
  CollateralVault: ['positions', 'totalLocked', 'CollateralLocked'],
  CreditLiquidityVault: ['totalFree', 'totalReserved', 'free', 'reserved', 'LiquidityDeposited', 'LiquidityReserved', 'ReservationConsumed', 'RepaymentCredited'],
  TestnetCreditManager: ['agreement', 'pendingDraw', 'principal', 'debtPreview', 'AgreementActivated', 'DrawExecuted', 'DebtRepaid'],
  CollateralAttestationVerifier: ['verify', 'EvidenceAccepted', 'EvidenceConflict'],
  RiskSignalRegistry: ['RiskSignaled'],
  FinancialReactive: ['FinancialSignalObserved', 'FinancialCallbackRequested'],
  FinancialCallbackReceiver: ['Disposition', 'Duplicate'],
  DemoMarket: ['debt'],
};

const bindings = await Promise.all(Object.entries(selection).map(async ([name, members]) => {
  const artifact = new URL(`../../out/${name}.sol/${name}.json`, import.meta.url);
  const { abi } = JSON.parse(await readFile(artifact, 'utf8'));
  const subset = abi.filter(item => members.includes(item.name));
  if (subset.length !== members.length || subset.some(item => item.type !== 'event' && item.stateMutability !== 'view' && item.stateMutability !== 'pure')) {
    throw new Error(`Unexpected read ABI in ${name}`);
  }
  return [name, subset];
}));

const target = new URL('../lib/abis/', import.meta.url);
await mkdir(target, { recursive: true });
await writeFile(new URL('reads.json', target), JSON.stringify(Object.fromEntries(bindings), null, 2) + '\n');
