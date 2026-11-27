export const themeStorageKey = 'covenant-theme';

export const initializeTheme = `try {
  if (localStorage.getItem(${JSON.stringify(themeStorageKey)}) === 'light') {
    document.documentElement.dataset.theme = 'light';
  }
} catch {}`;
