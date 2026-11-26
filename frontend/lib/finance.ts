export function formatUnits(amount: bigint, decimals: number) {
  const scale = 10n ** BigInt(decimals);
  const magnitude = amount < 0n ? -amount : amount;
  const whole = (magnitude / scale).toLocaleString('en-US');
  const fraction = (magnitude % scale).toString().padStart(decimals, '0').replace(/0+$/, '');
  return `${amount < 0n ? '−' : ''}${whole}${fraction ? '.' + fraction : ''}`;
}

export function allocationPercent(amount: bigint, total: bigint) {
  return total === 0n ? 0 : Number(amount * 10000n / total) / 100;
}
