'use client';

import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { motion, useInView, useMotionValue, useReducedMotion, useSpring, useTransform } from 'motion/react';
import { GuardianArt } from './guardian-art';
import styles from './guardian.module.css';

const spring = { stiffness: 150, damping: 22, mass: .6 };
const idleTransition = { duration: 4.8, ease: 'easeInOut' } as const;
const reducedMotionQuery = '(prefers-reduced-motion: reduce)';
const readReducedMotion = () => window.matchMedia(reducedMotionQuery).matches;
const serverReducedMotion = () => null;

function watchReducedMotion(listener: () => void) {
  const preference = window.matchMedia(reducedMotionQuery);
  preference.addEventListener('change', listener);
  return () => preference.removeEventListener('change', listener);
}

function normalize(point: number, center: number, viewportSize: number) {
  const distance = point - center;
  const available = distance < 0 ? center : viewportSize - center;
  return Math.max(-1, Math.min(1, distance / Math.max(available, 1)));
}

export function CovenantGuardian() {
  const surface = useRef<HTMLButtonElement>(null);
  const timeout = useRef<number | undefined>(undefined);
  const [hasFloated, setHasFloated] = useState(false);
  const [acknowledging, setAcknowledging] = useState(false);
  const inView = useInView(surface);
  const motionPreference = useReducedMotion();
  const livePreference = useSyncExternalStore(watchReducedMotion, readReducedMotion, serverReducedMotion);
  const reducedMotion = livePreference ?? motionPreference;
  const motionEnabled = inView && !reducedMotion;
  const idle = motionEnabled && !hasFloated;
  const pointerX = useMotionValue(0);
  const pointerY = useMotionValue(0);
  const hoverScale = useSpring(1, spring);
  const smoothX = useSpring(pointerX, spring);
  const smoothY = useSpring(pointerY, spring);
  const rotateX = useTransform(smoothY, [-1, 1], [15, -15]);
  const rotateY = useTransform(smoothX, [-1, 1], [-20, 20]);
  const x = useTransform(smoothX, [-1, 1], [-20, 20]);
  const y = useTransform(smoothY, [-1, 1], [-15, 15]);
  const ambientX = useTransform(smoothX, [-1, 1], [9, -9]);
  const ambientY = useTransform(smoothY, [-1, 1], [6, -6]);
  const shadowX = useTransform(smoothX, [-1, 1], [-7, 7]);
  const shieldX = useTransform(smoothX, [-1, 1], [-2, 2]);
  const shieldY = useTransform(smoothY, [-1, 1], [-1.5, 1.5]);

  useEffect(() => {
    if (!motionEnabled) {
      hoverScale.jump(1);
      return;
    }
    const frame = surface.current;
    if (!frame) return;
    const finePointer = matchMedia('(any-hover: hover) and (any-pointer: fine)');
    const neutral = () => {
      pointerX.set(0);
      pointerY.set(0);
    };
    const track = (event: PointerEvent) => {
      if (!finePointer.matches || event.pointerType !== 'mouse') return;
      const box = frame.getBoundingClientRect();
      pointerX.set(normalize(event.clientX, box.left + box.width / 2, window.innerWidth));
      pointerY.set(normalize(event.clientY, box.top + box.height / 2, window.innerHeight));
    };
    const leaveViewport = (event: PointerEvent) => {
      if (event.relatedTarget === null && event.pointerType === 'mouse') neutral();
    };
    window.addEventListener('pointermove', track, { passive: true, capture: true });
    window.addEventListener('pointerout', leaveViewport, true);
    window.addEventListener('pointercancel', neutral, true);
    finePointer.addEventListener('change', neutral);
    window.addEventListener('blur', neutral);
    return () => {
      window.removeEventListener('pointermove', track, true);
      window.removeEventListener('pointerout', leaveViewport, true);
      window.removeEventListener('pointercancel', neutral, true);
      finePointer.removeEventListener('change', neutral);
      window.removeEventListener('blur', neutral);
      neutral();
    };
  }, [motionEnabled, hoverScale, pointerX, pointerY]);

  useEffect(() => () => window.clearTimeout(timeout.current), []);

  function acknowledge() {
    if (timeout.current !== undefined) return;
    setAcknowledging(true);
    timeout.current = window.setTimeout(() => {
      timeout.current = undefined;
      setAcknowledging(false);
    }, 740);
  }

  const bouncing = acknowledging && inView && !reducedMotion;

  return <div className={styles.guardian} data-idle={idle} data-motion={motionEnabled} data-acknowledging={acknowledging}>
    <motion.div className={styles.ambient} aria-hidden="true" style={{ x: reducedMotion ? 0 : ambientX, y: reducedMotion ? 0 : ambientY }} />
    <motion.button type="button" ref={surface} className={styles.surface} aria-label="Acknowledge Covenant Guardian" onClick={acknowledge} onHoverStart={() => { if (motionEnabled) hoverScale.set(1.035); }} onHoverEnd={() => hoverScale.set(1)}>
      <span className={styles.scene} aria-hidden="true">
        <motion.span className={styles.shadow} style={{ x: reducedMotion ? 0 : shadowX }} initial={false} animate={idle ? { scale: [1, .84, 1], opacity: [.78, .42, .78] } : { scale: 1, opacity: .78 }} transition={idle ? idleTransition : { duration: 0 }} />
        <motion.span data-guardian-tilt className={styles.tilt} style={{ rotateX: reducedMotion ? 0 : rotateX, rotateY: reducedMotion ? 0 : rotateY, x: reducedMotion ? 0 : x, y: reducedMotion ? 0 : y }}>
          <motion.span data-guardian-float className={styles.float} initial={false} animate={idle ? { y: [0, -16, 0], scale: [1, 1.018, 1] } : { y: 0, scale: 1 }} transition={idle ? idleTransition : { duration: 0 }} onAnimationComplete={() => { if (idle) setHasFloated(true); }}>
            <motion.span className={styles.hover} style={{ scale: motionEnabled ? hoverScale : 1 }}>
              <motion.span data-guardian-response className={styles.response} initial={false} animate={bouncing ? { y: [0, -10, 2, 0], scale: [1, 1.024, 1, 1] } : { y: 0, scale: 1 }} transition={{ duration: bouncing ? .7 : 0, ease: 'easeInOut' }}>
                <GuardianArt shieldX={reducedMotion ? 0 : shieldX} shieldY={reducedMotion ? 0 : shieldY} />
              </motion.span>
            </motion.span>
          </motion.span>
        </motion.span>
      </span>
    </motion.button>
  </div>;
}
