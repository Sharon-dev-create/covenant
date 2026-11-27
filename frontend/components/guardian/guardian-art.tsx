import Image from 'next/image';
import { motion, type MotionValue } from 'motion/react';
import reference from '../../public/images/covenant-guardian.png';
import styles from './guardian.module.css';

type ParallaxOffset = MotionValue<number> | number;

export function GuardianArt({ shieldX, shieldY }: { shieldX: ParallaxOffset; shieldY: ParallaxOffset }) {
  return <>
    <Image className={styles.reference} src={reference} alt="" sizes="(max-width: 600px) 340px, (max-width: 1050px) 46vw, 580px" preload draggable={false} />
    <span className={styles.core} />
    <motion.svg className={styles.hologram} viewBox="0 0 801 810" fill="none" focusable="false" aria-hidden="true">
      <motion.g data-guardian-shield style={{ x: shieldX, y: shieldY }}>
        <path className={styles.shield} d="M548 241Q579 265 615 275C605 336 572 379 530 394C486 371 466 318 484 260Q521 257 548 241Z" />
      </motion.g>
    </motion.svg>
  </>;
}
