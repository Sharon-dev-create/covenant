import { demoProvider } from './demo.ts';
import { parseReviewedManifest } from './deployment.ts';
import type { OverviewProvider } from './data.ts';

const liveProvider: OverviewProvider = {
  mode: 'live',
  async read() {
    let manifest: unknown;
    try {
      manifest = JSON.parse(process.env.COVENANT_REVIEWED_MANIFEST ?? 'null');
    } catch {
      return { kind: 'unconfigured' };
    }
    return { kind: parseReviewedManifest(manifest).status === 'configured' ? 'unavailable' : 'unconfigured' };
  },
};

export function overviewProvider(mode: string | string[] | undefined): OverviewProvider {
  return mode === 'live' ? liveProvider : demoProvider;
}
