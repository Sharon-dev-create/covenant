import type { Metadata } from 'next';
import './globals.css';
import { initializeTheme } from '../lib/theme';

export const metadata: Metadata = {
  title: { default: 'Covenant', template: '%s · Covenant' },
  description: 'Cross-chain liquidity backstop infrastructure.',
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en" suppressHydrationWarning><head><script dangerouslySetInnerHTML={{ __html: initializeTheme }} /></head><body><a className="skip-link" href="#main">Skip to content</a>{children}</body></html>;
}
