import { FLOATING_ACTION_SIDE_RIGHT, normalizeFloatingActionSide } from '../components/FloatingActionLayoutSupport';
import { getAbilityContext } from '../shared/EhShared';
import { subscribeHoldingHandSide } from './EhHoldingHandSupport';
import {
  FLOATING_ACTION_HOLDING_HAND_SETTING_KEY,
  FLOATING_ACTION_SIDE_REVISION_KEY,
  FLOATING_ACTION_SIDE_SETTING_KEY,
  ehSettingsStore
} from './EhSettingsStore';

/**
 * Shared floating-action side binding for every gallery-style page. It owns the holding-hand
 * subscription, the persisted manual side and the precedence between them, so pages only have to
 * provide the animation callback for their own action dock.
 */
export class FloatingActionSideController {
  private holdingSide: string = '';
  private unsubscribe: () => void = () => {};
  private readonly applySide: (side: string) => void;

  constructor(applySide: (side: string) => void) {
    this.applySide = applySide;
  }

  syncFromSettings(): void {
    this.dispose();
    this.holdingSide = '';
    this.applySide(this.storedSide());
    if (ehSettingsStore.getValue(FLOATING_ACTION_HOLDING_HAND_SETTING_KEY, 'On') !== 'On') {
      return;
    }
    this.unsubscribe = subscribeHoldingHandSide((side: string) => {
      this.applyHoldingSide(side);
    });
  }

  handleManualSettingChanged(): void {
    if (this.holdingSide.length > 0) {
      return;
    }
    this.applySide(this.storedSide());
  }

  handleManualSide(side: string): void {
    const normalized = normalizeFloatingActionSide(side);
    ehSettingsStore.setValue(FLOATING_ACTION_SIDE_SETTING_KEY, normalized);
    const revision = AppStorage.get<number>(FLOATING_ACTION_SIDE_REVISION_KEY) ?? 0;
    AppStorage.setOrCreate<number>(FLOATING_ACTION_SIDE_REVISION_KEY, revision + 1);
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSettingsStore.save(context).catch(() => {});
    }
    if (this.holdingSide.length === 0) {
      this.applySide(normalized);
    }
  }

  dispose(): void {
    this.unsubscribe();
    this.unsubscribe = () => {};
    this.holdingSide = '';
  }

  private storedSide(): string {
    return normalizeFloatingActionSide(
      ehSettingsStore.getValue(FLOATING_ACTION_SIDE_SETTING_KEY, FLOATING_ACTION_SIDE_RIGHT));
  }

  private applyHoldingSide(side: string): void {
    this.holdingSide = side;
    this.applySide(side.length > 0 ? normalizeFloatingActionSide(side) : this.storedSide());
  }
}
