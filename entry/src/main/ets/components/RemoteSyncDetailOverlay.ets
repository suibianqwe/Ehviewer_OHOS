import { uiText } from '../shared/EhTranslations';
import {
  themePrimaryText,
  themeSecondaryText,
  themeSurfaceVariant,
  themeTertiaryText
} from '../shared/EhTheme';
import {
  uiButtonHighlightBorderColor,
  uiButtonMaterial,
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiDialogMaterial,
  uiDialogSurfaceBackground,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiRadius,
  uiTransparentButtonBackgroundEffect
} from '../shared/EhUiStyle';
import {
  REMOTE_SYNC_ACTIVE_KEY,
  REMOTE_SYNC_PROGRESS_DETAIL_KEY,
  REMOTE_SYNC_PROGRESS_PERCENT_KEY,
  REMOTE_SYNC_PROGRESS_TITLE_KEY,
  REMOTE_SYNC_STATUS_DETAIL_KEY,
  REMOTE_SYNC_STATUS_TEXT_KEY
} from '../services/RemoteStorageSyncService';
import { PopupScrim } from './PopupScrim';

// Drawer footer row. Values arrive as @Prop so the row re-renders whenever the page-level
// AppStorage observers change, without the drawer rebuilding its list.
@Component
export struct RemoteSyncStatusRow {
  @Prop text: string = '';
  @Prop detail: string = '';
  @Prop active: boolean = false;
  @Prop percent: number = -1;
  onTap: () => void = () => {};

  build() {
    Row() {
      if (this.active) {
        LoadingProgress()
          .width(15)
          .height(15)
          .color(themeSecondaryText())
      } else {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(15)
          .fontColor([themeSecondaryText()])
      }
      Column({ space: 2 }) {
        Text(this.percent >= 0 && this.active ? this.text + ' · ' + this.percent.toString() + '%' : this.text)
          .fontSize(12)
          .fontColor(themeSecondaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.detail.length > 0) {
          Text(this.detail)
            .fontSize(10)
            .fontColor(themeSecondaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .opacity(0.75)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 6 })
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(12)
        .fontColor([themeTertiaryText()])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(themeSurfaceVariant())
    .onClick(() => {
      this.onTap();
    })
  }
}

@Component
export struct RemoteSyncDetailOverlay {
  onClose: () => void = () => {};
  @StorageProp(REMOTE_SYNC_STATUS_TEXT_KEY) syncText: string = '';
  @StorageProp(REMOTE_SYNC_STATUS_DETAIL_KEY) syncDetail: string = '';
  @StorageProp(REMOTE_SYNC_ACTIVE_KEY) syncActive: boolean = false;
  @StorageProp(REMOTE_SYNC_PROGRESS_TITLE_KEY) progressTitle: string = '';
  @StorageProp(REMOTE_SYNC_PROGRESS_DETAIL_KEY) progressDetail: string = '';
  @StorageProp(REMOTE_SYNC_PROGRESS_PERCENT_KEY) progressPercent: number = -1;
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;

  @Builder
  private infoRow(label: string, value: string) {
    Row() {
      Text(uiText(label))
        .fontSize(12)
        .fontColor(themeTertiaryText())
        .width(84)
      Text(value)
        .fontSize(13)
        .fontColor(themePrimaryText())
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
    .alignItems(VerticalAlign.Top)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      PopupScrim({
        showCutout: this.popupWidth > 0 && this.popupHeight > 0,
        cutoutWidth: this.popupWidth,
        cutoutHeight: this.popupHeight,
        cutoutRadius: uiDialogSurfaceRadius(),
        onDismiss: this.onClose
      })

      Column() {
        Row() {
          Text(uiText('Sync details'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([uiMaterialForegroundColor(themePrimaryText())])
          }
          .width(40)
          .height(40)
          .backgroundColor(uiMaterialBackground(themeSurfaceVariant()))
          .border({ width: 1, color: uiButtonHighlightBorderColor() })
          .backgroundEffect(uiTransparentButtonBackgroundEffect())
          .systemMaterial(uiButtonMaterial())
          .onClick(this.onClose)
        }
        .width('100%')

        Column() {
          if (this.syncActive) {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color(themeSecondaryText())
              Text(this.progressTitle.length > 0 ? this.progressTitle : uiText('Syncing...'))
                .fontSize(14)
                .fontColor(themePrimaryText())
                .layoutWeight(1)
              if (this.progressPercent >= 0) {
                Text(this.progressPercent.toString() + '%')
                  .fontSize(13)
                  .fontColor(themeSecondaryText())
              }
            }
            .width('100%')
            .padding({ top: 10, bottom: 10 })

            if (this.progressPercent >= 0) {
              Progress({ value: this.progressPercent, total: 100, type: ProgressType.Linear })
                .width('100%')
                .color(themePrimaryText())
            }
            if (this.progressDetail.length > 0) {
              Text(this.progressDetail)
                .fontSize(12)
                .fontColor(themeSecondaryText())
                .width('100%')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 8 })
            }
          } else {
            Text(uiText('No active sync'))
              .fontSize(13)
              .fontColor(themeSecondaryText())
              .width('100%')
              .padding({ top: 10, bottom: 10 })
          }

          Divider()
            .color(themeSurfaceVariant())
            .strokeWidth(0.5)
            .margin({ top: 10, bottom: 8 })

          this.infoRow('Status', this.syncText)
          this.infoRow('Server', this.syncDetail)
          if (this.progressTitle.length > 0) {
            this.infoRow('Current', this.progressTitle)
          }
          if (this.progressDetail.length > 0) {
            this.infoRow('Progress', this.progressDetail)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('88%')
      .constraintSize({ maxWidth: 460 })
      .padding(18)
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
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }
}
