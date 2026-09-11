import { DownloadInfo, DownloadState } from '../services/EhDownloadStore';
import {
  createEmptyDownloadInfo,
  downloadStateColor,
  downloadStateLabel,
  DOWNLOAD_STATUS_FILTER_OPTIONS,
  uiText,
  uiValue,
} from '../shared/EhShared';
import {
  themeDividerColor,
  themeFieldBackground,
  themeOnPrimaryText,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSelectedBackground,
  themeSelectedText,
  themeSurface,
  themeTertiaryText,
} from '../shared/EhTheme';
import {
  uiButtonMaterial,
  uiTransparentButtonBackgroundEffect,
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiDialogMaterial,
  uiDialogSurfaceBackground,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow,
  uiListGap,
  uiListItemBackground,
  uiListItemBorderColor,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiRadius,
} from '../shared/EhUiStyle';
import { PopupScrim } from './PopupScrim';
import { ActionBubble } from './GalleryScenes';
import {
  FLOATING_ACTION_GAP,
  FLOATING_ACTION_PRIMARY_GAP,
  FLOATING_ACTION_SIZE,
  FLOATING_ACTION_SIDE_LEFT,
  FLOATING_ACTION_SIDE_RIGHT,
  floatingActionGridHeight,
  floatingActionGridWidth,
  floatingActionHitIndex,
  floatingActionIndexesForColumn,
  floatingActionSideFromDrag,
  floatingActionToolbarWidth,
  floatingActionVisualColumns,
  normalizeFloatingActionSide,
} from './FloatingActionLayoutSupport';


@Component
struct DownloadStatusFilterOptionRow {
  @Link selectedStatuses: string[];
  @Prop status: string = '';
  @Prop allOption: boolean = false;

  private isSelected(): boolean {
    return this.allOption ? this.selectedStatuses.length === DOWNLOAD_STATUS_FILTER_OPTIONS.length :
      this.selectedStatuses.indexOf(this.status) >= 0;
  }

  private toggle(): void {
    if (this.allOption) {
      this.selectedStatuses = this.selectedStatuses.length === DOWNLOAD_STATUS_FILTER_OPTIONS.length ? [] :
        DOWNLOAD_STATUS_FILTER_OPTIONS.slice();
      return;
    }
    const next = this.selectedStatuses.slice();
    const index = next.indexOf(this.status);
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(this.status);
    }
    this.selectedStatuses = next;
  }

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row() {
        Text(uiText(this.allOption ? 'All' : this.status))
          .fontSize(15)
          .fontColor(uiMaterialForegroundColor(this.isSelected() ? themeSelectedText() : themePrimaryText()))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)

        SymbolGlyph(this.isSelected() ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
          .fontSize(21)
          .fontColor([uiMaterialForegroundColor(this.isSelected() ? themeSelectedText() : themeTertiaryText())])
      }
      .width('100%')
      .padding({ left: 14, right: 14 })
    }
    .width('100%')
    .height(46)
    .backgroundColor(uiMaterialBackground(this.isSelected() ? themeSelectedBackground() : Color.Transparent))
    .borderRadius(uiRadius(8))
    .backgroundEffect(uiTransparentButtonBackgroundEffect())
    .systemMaterial(uiButtonMaterial())
    .onClick(() => {
      this.toggle();
    })
  }
}

@Component
export struct DownloadStatusFilterOverlay {
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;
  @Link selectedStatuses: string[];
  onCancel: () => void = () => {};
  onApply: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      PopupScrim({
        showCutout: this.popupWidth > 0 && this.popupHeight > 0,
        cutoutWidth: this.popupWidth,
        cutoutHeight: this.popupHeight,
        cutoutRadius: uiDialogSurfaceRadius(),
        onDismiss: () => {
          this.onCancel();
        }
      })

      Column({ space: 10 }) {
        Text(uiText('Download status'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .width('100%')

        Text(uiText('Select statuses to display'))
          .fontSize(13)
          .fontColor(themeSecondaryText())
          .width('100%')

        List({ space: uiListGap() }) {
          ListItem() {
            DownloadStatusFilterOptionRow({
              selectedStatuses: $selectedStatuses,
              allOption: true
            })
          }

          ForEach(DOWNLOAD_STATUS_FILTER_OPTIONS, (status: string) => {
            ListItem() {
              DownloadStatusFilterOptionRow({
                selectedStatuses: $selectedStatuses,
                status: status
              })
            }
          }, (status: string) => status)
        }
        .width('100%')
        .height(0)
        .layoutWeight(1)
        .scrollBar(BarState.Auto)

        Row({ space: 10 }) {
          Button(uiText('Cancel'))
            .height(40)
            .layoutWeight(1)
            .fontSize(14)
            .fontColor(uiMaterialForegroundColor(themePrimaryText()))
            .backgroundColor(uiMaterialBackground(themeFieldBackground()))
            .borderRadius(uiRadius(8))
            .backgroundEffect(uiTransparentButtonBackgroundEffect())
            .systemMaterial(uiButtonMaterial())
            .onClick(() => {
              this.onCancel();
            })

          Button(uiText('OK'))
            .height(40)
            .layoutWeight(1)
            .fontSize(14)
            .fontColor(uiMaterialForegroundColor(themeOnPrimaryText()))
            .backgroundColor(uiMaterialBackground(themePrimaryColor()))
            .borderRadius(uiRadius(8))
            .backgroundEffect(uiTransparentButtonBackgroundEffect())
            .systemMaterial(uiButtonMaterial())
            .onClick(() => {
              this.onApply();
            })
        }
        .width('100%')
      }
      .width('82%')
      .height('72%')
      .constraintSize({ maxWidth: 380, maxHeight: 560 })
      .padding(16)
      .backgroundColor(uiMaterialBackground(uiDialogSurfaceBackground()))
      .shadow(uiDialogSurfaceShadow())
      .borderRadius(uiDialogSurfaceRadius())
      .backgroundBlurStyle(uiDialogBlurStyle(), uiDialogBlurOptions())
      .systemMaterial(uiDialogMaterial())
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.popupWidth = Number.parseFloat(newArea.width.toString());
        this.popupHeight = Number.parseFloat(newArea.height.toString());
      })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct DownloadToolColumn {
  @Prop expanded: boolean = false;
  @Prop hasSelection: boolean = false;
  @Prop canOperate: boolean = false;
  @Prop canJump: boolean = false;
  @Prop canRandom: boolean = false;
  @Prop maxExpandedHeight: number = 360;
  @Prop showTranslationButton: boolean = true;
  @Prop translationEnabled: boolean = false;
  @Prop side: string = FLOATING_ACTION_SIDE_RIGHT;
  @State activeActionIndex: number = -1;
  onToggle: () => void = () => {};
  onStatus: () => void = () => {};
  onJump: () => void = () => {};
  onStart: () => void = () => {};
  onStop: () => void = () => {};
  onRestore: () => void = () => {};
  onRandom: () => void = () => {};
  onTranslate: () => void = () => {};
  onSelectAll: () => void = () => {};
  onLabel: () => void = () => {};
  onDelete: () => void = () => {};
  onExportZip: () => void = () => {};
  onSideChange: (side: string) => void = (_side: string) => {};
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  private sideDragDetected: boolean = false;

  private isLeftSide(): boolean {
    return normalizeFloatingActionSide(this.side) === FLOATING_ACTION_SIDE_LEFT;
  }

  private toggleExpanded(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.onToggle();
    });
  }

  private actionCount(): number {
    if (!this.expanded) {
      return 0;
    }
    if (this.hasSelection) {
      return this.showTranslationButton ? 8 : 7;
    }
    return this.showTranslationButton ? 7 : 6;
  }

  private primaryIndex(): number {
    return this.actionCount();
  }

  private expandedActionsHeight(): number {
    return floatingActionGridHeight(this.actionCount(), this.maxExpandedHeight);
  }

  private expandedActionsWidth(): number {
    return floatingActionGridWidth(this.actionCount(), this.maxExpandedHeight);
  }

  private toolbarWidth(): number {
    return floatingActionToolbarWidth(this.actionCount(), this.maxExpandedHeight);
  }

  private visualActionColumns(): number[] {
    return floatingActionVisualColumns(this.actionCount(), this.maxExpandedHeight, this.side);
  }

  private actionIndexesForColumn(column: number): number[] {
    return floatingActionIndexesForColumn(column, this.actionCount(), this.maxExpandedHeight);
  }

  private actionKind(index: number): string {
    if (this.hasSelection) {
      if (index === 0) return 'select';
      if (index === 1) return 'label';
      if (index === 2) return 'export';
      if (index === 3) return 'delete';
      if (index === 4) return 'jump';
      if (index === 5) return 'start';
      if (index === 6) return 'stop';
      if (index === 7 && this.showTranslationButton) return 'translate';
      return '';
    }
    if (index === 0) return 'status';
    if (index === 1) return 'jump';
    if (index === 2) return 'start';
    if (index === 3) return 'stop';
    if (index === 4) return 'scan';
    if (index === 5 && this.showTranslationButton) return 'translate';
    if (index === (this.showTranslationButton ? 6 : 5)) return 'random';
    return '';
  }

  private actionLabel(index: number): string {
    const kind = this.actionKind(index);
    if (kind === 'select') return uiText('Select all');
    if (kind === 'label') return uiText('Label');
    if (kind === 'export') return uiText('Export');
    if (kind === 'delete') return uiText('Delete');
    if (kind === 'status') return uiText('Status');
    if (kind === 'jump') return uiText('Jump');
    if (kind === 'start') return this.hasSelection ? uiText('Start selected') : uiText('Start filtered');
    if (kind === 'stop') return this.hasSelection ? uiText('Stop selected') : uiText('Stop filtered');
    if (kind === 'scan') return uiText('Scan');
    if (kind === 'translate') {
      return this.translationEnabled ? uiText('Show original titles') : uiText('Translate titles');
    }
    if (kind === 'random') return uiText('Random');
    return '';
  }

  private actionIcon(index: number): Resource {
    const kind = this.actionKind(index);
    if (kind === 'select') return $r('sys.symbol.checkmark_circle');
    if (kind === 'label') return $r('sys.symbol.folder');
    if (kind === 'export') return $r('sys.symbol.archivebox');
    if (kind === 'delete') return $r('sys.symbol.trash');
    if (kind === 'status') return $r('sys.symbol.funnel');
    if (kind === 'jump') return $r('sys.symbol.chevron_forward');
    if (kind === 'start') return $r('sys.symbol.play_fill');
    if (kind === 'stop') return $r('sys.symbol.pause_fill');
    if (kind === 'scan') return $r('sys.symbol.doc_text_badge_magnifyingglass');
    if (kind === 'translate') return $r('sys.symbol.translate');
    if (kind === 'random') return $r('sys.symbol.shuffle');
    return $r('sys.symbol.more');
  }

  private actionEnabled(index: number): boolean {
    const kind = this.actionKind(index);
    if (kind === 'jump') {
      return this.canJump;
    }
    if (kind === 'start' || kind === 'stop') {
      return this.canOperate;
    }
    if (kind === 'random') {
      return this.canRandom;
    }
    return kind.length > 0;
  }

  private hitActionIndex(x: number, y: number): number {
    return floatingActionHitIndex(x, y, this.actionCount(), this.maxExpandedHeight, this.side);
  }

  private touchX(event: TouchEvent): number {
    if (event.touches.length > 0) {
      return event.touches[0].x;
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0].x;
    }
    return -1;
  }

  private touchY(event: TouchEvent): number {
    if (event.touches.length > 0) {
      return event.touches[0].y;
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0].y;
    }
    return -1;
  }

  private updateActiveAction(event: TouchEvent): void {
    const index = this.hitActionIndex(this.touchX(event), this.touchY(event));
    if (index !== this.activeActionIndex) {
      this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
        this.activeActionIndex = index;
      });
    }
  }

  private triggerAction(index: number): void {
    if (index < 0) {
      return;
    }
    if (index === this.primaryIndex()) {
      this.toggleExpanded();
      return;
    }
    const kind = this.actionKind(index);
    if (kind === 'select') {
      this.onSelectAll();
    } else if (kind === 'label') {
      this.onLabel();
    } else if (kind === 'export') {
      this.onExportZip();
    } else if (kind === 'delete') {
      this.onDelete();
    } else if (kind === 'status') {
      this.onStatus();
    } else if (kind === 'jump' && this.canJump) {
      this.onJump();
    } else if (kind === 'start' && this.canOperate) {
      this.onStart();
    } else if (kind === 'stop' && this.canOperate) {
      this.onStop();
    } else if (kind === 'scan') {
      this.onRestore();
    } else if (kind === 'translate') {
      this.onTranslate();
    } else if (kind === 'random' && this.canRandom) {
      this.onRandom();
    }
  }

  private handleToolbarTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.touchStartX = this.touchX(event);
      this.touchStartY = this.touchY(event);
      this.sideDragDetected = false;
      this.updateActiveAction(event);
    } else if (event.type === TouchType.Move) {
      const offsetX = this.touchX(event) - this.touchStartX;
      const offsetY = this.touchY(event) - this.touchStartY;
      if (floatingActionSideFromDrag(offsetX, offsetY).length > 0) {
        this.sideDragDetected = true;
        this.activeActionIndex = -1;
      } else if (!this.sideDragDetected) {
        this.updateActiveAction(event);
      }
    } else if (event.type === TouchType.Up) {
      if (this.sideDragDetected) {
        const offsetX = this.touchX(event) - this.touchStartX;
        const offsetY = this.touchY(event) - this.touchStartY;
        const targetSide = floatingActionSideFromDrag(offsetX, offsetY);
        this.sideDragDetected = false;
        this.activeActionIndex = -1;
        if (targetSide.length > 0) {
          this.onSideChange(targetSide);
        }
        return;
      }
      const index = this.hitActionIndex(this.touchX(event), this.touchY(event));
      const fallbackIndex = index >= 0 ? index : this.activeActionIndex;
      this.activeActionIndex = -1;
      this.triggerAction(fallbackIndex);
    } else if (event.type === TouchType.Cancel) {
      this.sideDragDetected = false;
      this.activeActionIndex = -1;
    }
  }

  @Builder
  private actionBubble(index: number) {
    ActionBubble({
      label: this.actionLabel(index),
      symbolIcon: this.actionIcon(index),
      isEnabled: this.actionEnabled(index),
      checked: this.actionKind(index) === 'translate' && this.translationEnabled,
      active: this.activeActionIndex === index,
      side: this.side,
      directTap: false
    })
  }

  build() {
    Column() {
      if (this.expanded) {
        Row({ space: FLOATING_ACTION_GAP }) {
          ForEach(this.visualActionColumns(), (column: number) => {
            Column({ space: FLOATING_ACTION_GAP }) {
              ForEach(this.actionIndexesForColumn(column), (index: number) => {
                Row() {
                  this.actionBubble(index)
                }
                .width(FLOATING_ACTION_SIZE)
                .height(FLOATING_ACTION_SIZE)
                .justifyContent(this.isLeftSide() ? FlexAlign.Start : FlexAlign.End)
                .clip(false)
              }, (index: number) => index.toString())
            }
            .width(FLOATING_ACTION_SIZE)
            .alignItems(this.isLeftSide() ? HorizontalAlign.Start : HorizontalAlign.End)
          }, (column: number) => column.toString())
        }
        .width(this.expandedActionsWidth())
        .height(this.expandedActionsHeight())
        .alignItems(VerticalAlign.Top)
        .margin({ bottom: FLOATING_ACTION_PRIMARY_GAP })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: 12 }))
          .animation({ duration: 180, curve: Curve.EaseOut }))
      }

      ActionBubble({
        label: uiText('Actions'),
        symbolIcon: this.expanded ? $r('sys.symbol.xmark') : $r('sys.symbol.more'),
        isEnabled: true,
        primary: true,
        active: this.activeActionIndex === this.primaryIndex(),
        side: this.side,
        directTap: false
      })
    }
    .width(this.toolbarWidth())
    .alignItems(this.isLeftSide() ? HorizontalAlign.Start : HorizontalAlign.End)
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .onTouch((event: TouchEvent) => {
      this.handleToolbarTouch(event);
    })
  }
}

@ObservedV2
export class DownloadCardState {
  @Trace state: DownloadState = DownloadState.None;
  @Trace progressText: string = '';
  @Trace progressValue: number = 0;
  @Trace speedText: string = '';

  update(state: DownloadState, progressText: string, progressValue: number, speedText: string): void {
    if (this.state !== state) {
      this.state = state;
    }
    if (this.progressText !== progressText) {
      this.progressText = progressText;
    }
    if (this.progressValue !== progressValue) {
      this.progressValue = progressValue;
    }
    if (this.speedText !== speedText) {
      this.speedText = speedText;
    }
  }
}

@ComponentV2
export struct DownloadCardStatus {
  @Param item: DownloadInfo = createEmptyDownloadInfo();
  @Require @Param cardState: DownloadCardState = new DownloadCardState();
  @Event onStatusTap: (item: DownloadInfo) => void = (_item: DownloadInfo) => {};

  private isDownloading(): boolean {
    return this.cardState.state === DownloadState.Downloading;
  }

  build() {
    Column() {
      Row() {
        Text(uiValue(downloadStateLabel(this.cardState.state)))
          .fontSize(10)
          .fontColor(themeOnPrimaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(downloadStateColor(this.cardState.state))
          .borderRadius(uiRadius(3))
        Text(this.cardState.progressText)
          .fontSize(11)
          .fontColor(themeSecondaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 6 })
          .layoutWeight(1)
        if (this.isDownloading() && this.cardState.speedText.length > 0) {
          Text(this.cardState.speedText)
            .fontSize(11)
            .fontColor(themeTertiaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')

      Row() {
        Progress({ value: this.cardState.progressValue, total: 100, type: ProgressType.Linear })
          .value(this.cardState.progressValue)
          .width('100%')
          .height(4)
          .color(downloadStateColor(this.cardState.state))
          .backgroundColor(themeDividerColor())
      }
        .width('100%')
        .height(4)
        .margin({ top: 6 })
        .clip(true)
        .id('download-progress-' + this.item.gid.toString())
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .backgroundColor(uiListItemBackground(themeSurface()))
    .border({ width: 1, color: uiListItemBorderColor(themeDividerColor()) })
    .borderRadius(uiRadius(16))
    .onClick(() => {
      this.onStatusTap(this.item);
    })
    .animation({ duration: 180, curve: Curve.EaseOut })
  }
}

