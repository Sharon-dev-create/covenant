import type { ChainKey } from './chains.ts';

export type TransactionState = 'illustrative' | 'pending' | 'confirmed' | 'failed';
export type Activity = { title: string; description: string; chain: ChainKey; status: TransactionState };
export type Agreement = { id: string; name: string; status: 'Active' | 'Pending' | 'Closed'; commitment: bigint; authorized: bigint; aprBps: bigint; ltvBps: bigint };
export type Overview = {
  free: bigint; reserved: bigint; principal: bigint; collateral: bigint; marketDebt: bigint;
  agreements: readonly Agreement[]; activity: readonly Activity[];
};
export type DataState<T> =
  | { kind: 'ready'; data: T }
  | { kind: 'loading' | 'empty' | 'unconfigured' | 'unavailable' | 'failed' };
export interface OverviewProvider {
  mode: 'demo' | 'live';
  read(): Promise<DataState<Overview>>;
}
