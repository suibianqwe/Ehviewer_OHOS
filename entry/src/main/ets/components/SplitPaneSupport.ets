import { ehSettingsStore } from '../services/EhSettingsStore';
import { getAbilityContext } from '../shared/EhShared';
import {
  themeDividerColor,
  themePrimaryColor,
  themeSurface,
  themeSurfaceVariant
} from '../shared/EhTheme';

export const SPLIT_PANE_RATIO_REVISION_KEY: string = 'ehviewer_split_pane_ratio_revision';
export const SPLIT_PANE_BREAKPOINT: number = 840;
export const SPLIT_PANE_LIST_MIN_WIDTH: number = 340;
export const SPLIT_PANE_SIDE_MIN_WIDTH: number = 360;
const SPLIT_PANE_PREVIOUS_ROUTE_RIGHT_PANE_KEY: string = 'ehviewer_previous_route_right_pane';
const SPLIT_PANE_DEFAULT_RATIO: number = 0.42;
const SPLIT_PANE_MIN_RATIO: number = 0.25;
const SPLIT_PANE_MAX_RATIO: number = 0.75;

export function splitPaneModeEnabled(): boolean {
  return ehSettingsStore.getValue('split_screen_mode', 'On') === 'On';
}

export function splitPaneCurrentRatio(): number {
  const value = Number.parseFloat(ehSettingsStore.getValue('split_screen_ratio',
    SPLIT_PANE_DEFAULT_RATIO.toString()));
  if (Number.isNaN(value)) {
    return SPLIT_PANE_DEFAULT_RATIO;
  }
  return clampSplitPaneRatio(value);
}

export function markPreviousRouteRightPane(visible: boolean): void {
  AppStorage.setOrCreate<boolean>(SPLIT_PANE_PREVIOUS_ROUTE_RIGHT_PANE_KEY, visible);
}

export function shouldFadeRestoredRightPane(): boolean {
  return AppStorage.get<boolean>(SPLIT_PANE_PREVIOUS_ROUTE_RIGHT_PANE_KEY) === true;
}

export function saveSplitPaneRatio(ratio: number): void {
  const nextRatio = clampSplitPaneRatio(ratio);
  ehSettingsStore.setValue('split_screen_ratio', nextRatio.toFixed(4));
  const currentRevision = AppStorage.get<number>(SPLIT_PANE_RATIO_REVISION_KEY);
  AppStorage.setOrCreate<number>(SPLIT_PANE_RATIO_REVISION_KEY,
    currentRevision === undefined ? 1 : currentRevision + 1);
  const context = getAbilityContext();
  if (context !== undefined) {
    ehSettingsStore.save(context).catch(() => {
    });
  }
}

export function splitPaneListWidth(totalWidth: number, ratio: number,
  minList: number = SPLIT_PANE_LIST_MIN_WIDTH, minSide: number = SPLIT_PANE_SIDE_MIN_WIDTH): number {
  if (totalWidth <= 0 || Number.isNaN(totalWidth)) {
    return Math.max(minList, 420);
  }
  const maxWidth = Math.max(minList, totalWidth - minSide - 1);
  return Math.max(minList, Math.min(maxWidth, Math.floor(totalWidth * clampSplitPaneRatio(ratio))));
}

export function splitPaneSideWidth(totalWidth: number, listWidth: number,
  minSide: number = SPLIT_PANE_SIDE_MIN_WIDTH): number {
  if (totalWidth <= 0 || Number.isNaN(totalWidth)) {
    return 0;
  }
  return Math.max(minSide, totalWidth - listWidth - 1);
}

export function splitPaneRatioForWidth(totalWidth: number, listWidth: number): number {
  if (totalWidth <= 0 || Number.isNaN(totalWidth)) {
    return SPLIT_PANE_DEFAULT_RATIO;
  }
  return clampSplitPaneRatio(listWidth / totalWidth);
}

export function splitPaneWidthFromDrag(totalWidth: number, startWidth: number, offsetX: number,
  minList: number = SPLIT_PANE_LIST_MIN_WIDTH, minSide: number = SPLIT_PANE_SIDE_MIN_WIDTH): number {
  if (totalWidth <= 0 || Number.isNaN(totalWidth)) {
    return startWidth;
  }
  const maxWidth = Math.max(minList, totalWidth - minSide - 1);
  return Math.max(minList, Math.min(maxWidth, startWidth + offsetX));
}

export function areaDimensionToVp(value: Length, px2vp: (value: number) => number): number {
  const text = value.toString();
  const parsed = Number.parseFloat(text);
  if (Number.isNaN(parsed)) {
    return 0;
  }
  if (text.indexOf('px') > 0) {
    return px2vp(parsed);
  }
  return parsed;
}

function clampSplitPaneRatio(value: number): number {
  return Math.max(SPLIT_PANE_MIN_RATIO, Math.min(SPLIT_PANE_MAX_RATIO, value));
}

@Component
export struct SplitPaneDivider {
  @Prop x: number = 0;
  @Prop dragging: boolean = false;
  onSplitDragStart: () => void = () => {
  };
  onSplitDragUpdate: (offsetX: number) => void = (_offsetX: number) => {
  };
  onSplitDragEnd: () => void = () => {
  };

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Divider()
        .vertical(true)
        .strokeWidth(2)
        .color(this.dragging ? themePrimaryColor() : themeDividerColor())
        .width(2)
        .height('100%')

      Column({ space: 3 }) {
        Column()
          .width(3)
          .height(3)
          .borderRadius(2)
          .backgroundColor(this.dragging ? themePrimaryColor() : themeDividerColor())
        Column()
          .width(3)
          .height(3)
          .borderRadius(2)
          .backgroundColor(this.dragging ? themePrimaryColor() : themeDividerColor())
        Column()
          .width(3)
          .height(3)
          .borderRadius(2)
          .backgroundColor(this.dragging ? themePrimaryColor() : themeDividerColor())
      }
      .width(18)
      .height(38)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(themeSurfaceVariant())
      .border({ width: 1, color: this.dragging ? themePrimaryColor() : themeDividerColor() })
      .borderRadius(9)
      .shadow({ radius: this.dragging ? 8 : 3, color: '#33000000', offsetY: 1 })
    }
    .width(24)
    .height('100%')
    .position({ x: this.x - 12, y: 0 })
    .zIndex(80)
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.move(TransitionEdge.END).animation({ duration: 300, curve: Curve.EaseOut }),
      TransitionEffect.move(TransitionEdge.END).animation({ duration: 240, curve: Curve.EaseIn })))
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 1 })
        .onActionStart(() => {
          this.onSplitDragStart();
        })
        .onActionUpdate((event: GestureEvent | undefined) => {
          if (event !== undefined) {
            this.onSplitDragUpdate(event.offsetX);
          }
        })
        .onActionEnd(() => {
          this.onSplitDragEnd();
        })
        .onActionCancel(() => {
          this.onSplitDragEnd();
        })
    )
    .animation({ duration: this.dragging ? 0 : 220, curve: Curve.EaseOut })
  }
}
