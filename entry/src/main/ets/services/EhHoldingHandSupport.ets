import { motion } from '@kit.MultimodalAwarenessKit';

export const HOLDING_HAND_SIDE_LEFT: string = 'Left';
export const HOLDING_HAND_SIDE_RIGHT: string = 'Right';
export const HOLDING_HAND_SIDE_NONE: string = '';

// The awareness service reports raw sensor transitions, which flicker while the user shifts the
// grip. A candidate side must stay stable before it is applied, and consecutive switches are
// rate-limited, so the adaptation feels calmer and closer to the system smart-grip behavior.
const SIDE_SETTLE_DELAY_MS: number = 900;
const SIDE_MIN_SWITCH_INTERVAL_MS: number = 1500;

export function holdingHandSwitchDelay(elapsedSinceLastSwitchMs: number): number {
  return Math.max(SIDE_SETTLE_DELAY_MS,
    SIDE_MIN_SWITCH_INTERVAL_MS - Math.max(0, elapsedSinceLastSwitchMs));
}

export function floatingActionSideForOperatingHand(status: motion.OperatingHandStatus): string {
  if (status === motion.OperatingHandStatus.LEFT_HAND_OPERATED) {
    return HOLDING_HAND_SIDE_LEFT;
  }
  if (status === motion.OperatingHandStatus.RIGHT_HAND_OPERATED) {
    return HOLDING_HAND_SIDE_RIGHT;
  }
  return HOLDING_HAND_SIDE_NONE;
}

export function floatingActionSideForHoldingHand(status: motion.HoldingHandStatus): string {
  if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
    return HOLDING_HAND_SIDE_LEFT;
  }
  if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
    return HOLDING_HAND_SIDE_RIGHT;
  }
  return HOLDING_HAND_SIDE_NONE;
}

export function subscribeHoldingHandSide(onChange: (side: string) => void): () => void {
  let holdingSubscribed = false;
  let operatingSubscribed = false;
  let holdingSide = HOLDING_HAND_SIDE_NONE;
  let operatingSide = HOLDING_HAND_SIDE_NONE;
  let appliedSide = HOLDING_HAND_SIDE_NONE;
  let pendingSide = HOLDING_HAND_SIDE_NONE;
  let pendingTimer = -1;
  let lastAppliedAt = 0;
  const effectiveSide = (): string => holdingSide.length > 0 ? holdingSide : operatingSide;
  const cancelPending = (): void => {
    if (pendingTimer !== -1) {
      clearTimeout(pendingTimer);
      pendingTimer = -1;
    }
    pendingSide = HOLDING_HAND_SIDE_NONE;
  };
  const applySide = (side: string): void => {
    appliedSide = side;
    lastAppliedAt = Date.now();
    onChange(side);
  };
  const scheduleEffectiveSide = (immediate: boolean = false): void => {
    const side = effectiveSide();
    if (side === appliedSide) {
      cancelPending();
      return;
    }
    if (immediate) {
      cancelPending();
      applySide(side);
      return;
    }
    if (pendingSide === side && pendingTimer !== -1) {
      return;
    }
    cancelPending();
    pendingSide = side;
    const wait = holdingHandSwitchDelay(Date.now() - lastAppliedAt);
    pendingTimer = setTimeout((): void => {
      pendingTimer = -1;
      if (pendingSide === effectiveSide() && pendingSide !== appliedSide) {
        applySide(pendingSide);
      }
      pendingSide = HOLDING_HAND_SIDE_NONE;
    }, wait);
  };
  const holdingCallback = (status: motion.HoldingHandStatus): void => {
    // Two-hand holds and unknown samples say nothing about which side to prefer; keep the side
    // the user is already using instead of flipping to the operating hand.
    if (status === motion.HoldingHandStatus.BOTH_HANDS_HELD ||
      status === motion.HoldingHandStatus.UNKNOWN_STATUS) {
      return;
    }
    holdingSide = floatingActionSideForHoldingHand(status);
    scheduleEffectiveSide();
  };
  const operatingCallback = (status: motion.OperatingHandStatus): void => {
    operatingSide = floatingActionSideForOperatingHand(status);
    if (holdingSide.length === 0) {
      scheduleEffectiveSide();
    }
  };
  try {
    motion.on('holdingHandChanged', holdingCallback);
    holdingSubscribed = true;
  } catch (error) {
    console.warn('EhHoldingHandSupport: holding-hand awareness is unavailable');
    onChange(HOLDING_HAND_SIDE_NONE);
    return (): void => {};
  }
  try {
    operatingSide = floatingActionSideForOperatingHand(motion.getRecentOperatingHandStatus());
    scheduleEffectiveSide(true);
  } catch (error) {
    console.warn('EhHoldingHandSupport: recent operating-hand status is unavailable');
  }
  try {
    motion.on('operatingHandChanged', operatingCallback);
    operatingSubscribed = true;
  } catch (error) {
    console.warn('EhHoldingHandSupport: operating-hand awareness is unavailable');
  }
  return (): void => {
    cancelPending();
    if (holdingSubscribed) {
      holdingSubscribed = false;
      try {
        motion.off('holdingHandChanged', holdingCallback);
      } catch (error) {
      }
    }
    if (operatingSubscribed) {
      operatingSubscribed = false;
      try {
        motion.off('operatingHandChanged', operatingCallback);
      } catch (error) {
      }
    }
  };
}
