import { uiText } from '../shared/EhShared';
import {
  themePrimaryText,
  themeSecondaryText
} from '../shared/EhTheme';
import {
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiDialogMaterial,
  uiDialogSurfaceBackground,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow
} from '../shared/EhUiStyle';
import { PopupScrim } from './PopupScrim';

@Component
export struct BlockingBusyOverlay {
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;
  @Prop message: string = 'Loading...';
  @Prop progressText: string = '';
  @Prop progressCurrent: number = -1;
  @Prop progressTotal: number = -1;

  private hasProgress(): boolean {
    return this.progressCurrent >= 0 && this.progressTotal > 0;
  }

  private progressValue(): number {
    if (!this.hasProgress()) {
      return 0;
    }
    return Math.max(0, Math.min(100, this.progressCurrent * 100 / this.progressTotal));
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      PopupScrim({
        showCutout: this.popupWidth > 0 && this.popupHeight > 0,
        cutoutWidth: this.popupWidth,
        cutoutHeight: this.popupHeight,
        cutoutRadius: uiDialogSurfaceRadius()
      })

      Column({ space: 12 }) {
        LoadingProgress()
          .width(42)
          .height(42)
          .color(themePrimaryText())
        Text(uiText(this.message))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.hasProgress()) {
          Progress({ value: this.progressValue(), total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(6)
            .color(themePrimaryText())
          if (this.progressText.length > 0) {
            Text(this.progressText)
              .fontSize(12)
              .fontColor(themeSecondaryText())
              .textAlign(TextAlign.Center)
              .maxLines(2)
              .width('100%')
          }
        }
        Text(uiText('Please wait...'))
          .fontSize(12)
          .fontColor(themeSecondaryText())
          .textAlign(TextAlign.Center)
      }
      .width(280)
      .constraintSize({ maxWidth: '72%' })
      .padding({ left: 20, right: 20, top: 20, bottom: 18 })
      .backgroundColor(uiDialogSurfaceBackground())
      .systemMaterial(uiDialogMaterial())
      .backgroundBlurStyle(uiDialogBlurStyle(), uiDialogBlurOptions())
      .borderRadius(uiDialogSurfaceRadius())
      .shadow(uiDialogSurfaceShadow())
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
