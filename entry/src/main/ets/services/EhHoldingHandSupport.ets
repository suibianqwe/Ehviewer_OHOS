import { motion } from '@kit.MultimodalAwarenessKit';

export const HOLDING_HAND_SIDE_LEFT: string = 'Left';
export const HOLDING_HAND_SIDE_RIGHT: string = 'Right';
export const HOLDING_HAND_SIDE_NONE: string = '';

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
  const emitEffectiveSide = (): void => {
    onChange(holdingSide.length > 0 ? holdingSide : operatingSide);
  };
  const holdingCallback = (status: motion.HoldingHandStatus): void => {
    holdingSide = floatingActionSideForHoldingHand(status);
    emitEffectiveSide();
  };
  const operatingCallback = (status: motion.OperatingHandStatus): void => {
    operatingSide = floatingActionSideForOperatingHand(status);
    if (holdingSide.length === 0) {
      emitEffectiveSide();
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
    emitEffectiveSide();
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
