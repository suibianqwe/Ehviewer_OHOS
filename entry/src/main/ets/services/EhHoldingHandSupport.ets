import { motion } from '@kit.MultimodalAwarenessKit';

export const HOLDING_HAND_SIDE_LEFT: string = 'Left';
export const HOLDING_HAND_SIDE_RIGHT: string = 'Right';
export const HOLDING_HAND_SIDE_NONE: string = '';

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
  let subscribed = false;
  const callback = (status: motion.HoldingHandStatus): void => {
    const side = floatingActionSideForHoldingHand(status);
    console.info(`EhHoldingHandSupport: status=${status}, side=${side || 'Fallback'}`);
    onChange(side);
  };
  try {
    motion.on('holdingHandChanged', callback);
    subscribed = true;
    console.info('EhHoldingHandSupport: subscribed');
  } catch (error) {
    console.warn('EhHoldingHandSupport: holding-hand awareness is unavailable');
  }
  return (): void => {
    if (!subscribed) {
      return;
    }
    subscribed = false;
    try {
      motion.off('holdingHandChanged', callback);
    } catch (error) {
    }
  };
}
