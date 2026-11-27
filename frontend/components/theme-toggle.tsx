'use client';

import { useSyncExternalStore } from 'react';
import { Moon, Sun } from 'lucide-react';
import { themeStorageKey } from '../lib/theme';

function subscribe(listener: () => void) {
  const observer = new MutationObserver(listener);
  observer.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
  return () => observer.disconnect();
}

const isLight = () => document.documentElement.dataset.theme === 'light';
const serverSnapshot = () => false;

export function ThemeToggle() {
  const light = useSyncExternalStore(subscribe, isLight, serverSnapshot);

  function toggle() {
    const theme = isLight() ? 'dark' : 'light';
    document.documentElement.dataset.theme = theme;
    try { localStorage.setItem(themeStorageKey, theme); } catch {}
  }

  return <button className="button theme-toggle" type="button" aria-label="Light theme" aria-pressed={light} title={light ? 'Switch to dark theme' : 'Switch to light theme'} onClick={toggle}>
    <Sun size={17} aria-hidden="true" className="theme-icon-sun" />
    <Moon size={17} aria-hidden="true" className="theme-icon-moon" />
  </button>;
}
