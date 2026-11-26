'use client';

import { useEffect, useRef, useState, type PointerEvent } from 'react';
import { GuardianArt } from './guardian-art';
import styles from './guardian.module.css';

const duration = { acknowledge: 580, protect: 1000, coordinate: 2200 } as const;
type Action = keyof typeof duration;
const description: Record<Action, string> = {
  acknowledge: 'Guardian acknowledgment.',
  protect: 'Illustrative shield response.',
  coordinate: 'Illustrative coordination: Unichain custody, Reactive orchestration, then Base execution.',
};

export function CovenantGuardian({ children }: { children: React.ReactNode }) {
  const surface = useRef<HTMLButtonElement>(null);
  const panel = useRef<HTMLElement>(null);
  const timer = useRef<number | undefined>(undefined);
  const finePointer = useRef(false);
  const reducedMotion = useRef(false);
  const [action, setAction] = useState<Action | 'idle'>('idle');
  const [paused, setPaused] = useState(false);

  useEffect(() => {
    const fine = window.matchMedia('(any-hover: hover) and (any-pointer: fine)');
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
    const updatePreferences = () => {
      finePointer.current = fine.matches;
      reducedMotion.current = reduced.matches;
      resetPointer();
    };
    updatePreferences();
    fine.addEventListener('change', updatePreferences);
    reduced.addEventListener('change', updatePreferences);
    const target = panel.current;
    const observer = typeof IntersectionObserver === 'undefined' ? undefined : new IntersectionObserver(([entry]) => {
      if (target) target.dataset.visible = String(entry.isIntersecting);
    });
    if (target) observer?.observe(target);
    return () => {
      fine.removeEventListener('change', updatePreferences);
      reduced.removeEventListener('change', updatePreferences);
      observer?.disconnect();
      window.clearTimeout(timer.current);
    };
  }, []);

  function movePointer(event: PointerEvent<HTMLButtonElement>) {
    if (!finePointer.current || reducedMotion.current || paused || event.pointerType !== 'mouse') return;
    const box = event.currentTarget.getBoundingClientRect();
    const clamp = (value: number) => Math.max(-1, Math.min(1, value));
    const x = clamp((event.clientX - box.left) / box.width * 2 - 1);
    const y = clamp((event.clientY - box.top) / box.height * 2 - 1);
    event.currentTarget.style.setProperty('--gaze-x', `${x * 6}px`);
    event.currentTarget.style.setProperty('--gaze-y', `${y * 4}px`);
    event.currentTarget.style.setProperty('--tilt', `${x * 5}deg`);
  }

  function resetPointer() {
    for (const property of ['--gaze-x', '--gaze-y', '--tilt']) surface.current?.style.removeProperty(property);
  }

  function play(next: Action) {
    if (timer.current !== undefined) return;
    setAction(next);
    timer.current = window.setTimeout(() => {
      timer.current = undefined;
      setAction('idle');
    }, duration[next]);
  }

  return <section className={styles.panel} ref={panel} data-action={action} data-paused={paused} aria-label="Covenant Guardian">
    <div className={styles.heading}><h2>Covenant Guardian</h2><button type="button" className={styles.pause} aria-pressed={paused} onClick={() => {
      resetPointer();
      setPaused(!paused);
    }}>Pause idle motion</button></div>
    <button type="button" ref={surface} className={styles.surface} aria-label="Acknowledge Covenant Guardian" onClick={() => play('acknowledge')} onPointerMove={movePointer} onPointerLeave={resetPointer} onPointerCancel={resetPointer}>
      <GuardianArt />
    </button>
    <div className={styles.controls}>
      <span>Illustrative actions</span>
      <div><button type="button" className="button" onClick={() => play('protect')}>Shield</button><button type="button" className="button" onClick={() => play('coordinate')}>Coordinate</button></div>
    </div>
    <span className={styles.status} role="status">{action === 'idle' ? '' : description[action]}</span>
    <div className={styles.networks}>{children}</div>
  </section>;
}
