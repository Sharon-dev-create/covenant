'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Activity, BookOpen, Coins, FileText, LayoutGrid, Lock } from 'lucide-react';

const items = [
  ['Overview', '/dashboard', LayoutGrid],
  ['Credit agreements', '/dashboard/agreements', FileText],
  ['Liquidity', '/dashboard/liquidity', Coins],
  ['Collateral', '/dashboard/collateral', Lock],
  ['Reactive activity', '/dashboard/activity', Activity],
  ['Guided demonstration', '/dashboard/demo', BookOpen],
] as const;

export function Navigation({ live }: { live: boolean }) {
  const pathname = usePathname();
  return <nav aria-label="Dashboard" className="nav">
    {items.map(([label, href, Icon]) => {
      const selected = pathname === href || (href !== '/dashboard' && pathname.startsWith(href + '/'));
      return <Link key={href} href={live ? href + '?mode=live' : href} aria-current={selected ? (pathname === href ? 'page' : 'location') : undefined}>
        <Icon size={17} aria-hidden />{label}
      </Link>;
    })}
  </nav>;
}
