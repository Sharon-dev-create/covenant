type CovenantLogoProps = {
  variant?: 'icon' | 'wordmark';
  size?: number;
  color?: string;
};

export function CovenantLogo({ variant = 'icon', size = 32, color }: CovenantLogoProps) {
  const withWordmark = variant === 'wordmark';
  return <span className="covenant-logo" style={{ color }}>
    <svg
      width={size}
      height={size}
      viewBox="0 0 160 160"
      fill="none"
      stroke="currentColor"
      strokeWidth="10"
      strokeLinejoin="round"
      role={withWordmark ? undefined : 'img'}
      aria-label={withWordmark ? undefined : 'Covenant'}
      aria-hidden={withWordmark ? true : undefined}
      focusable="false"
    >
      <path d="M111 45 L75 24 L28 51 L28 109 L75 137 L112 115" />
      <path d="M91 62 L119 94 L151 32" />
    </svg>
    {withWordmark && <span>Covenant</span>}
  </span>;
}
