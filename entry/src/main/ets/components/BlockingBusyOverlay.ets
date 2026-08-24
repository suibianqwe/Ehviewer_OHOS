import { uiText } from '../shared/EhShared';
import {
  themePrimaryText,
  themeScrimColor,
  themeSecondaryText
} from '../shared/EhTheme';
import {
  uiDialogMaterial,
  uiDialogSurfaceBackground,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow
} from '../shared/EhUiStyle';

@Component
export struct BlockingBusyOverlay {
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
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(themeScrimColor())

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
      .borderRadius(uiDialogSurfaceRadius())
      .systemMaterial(uiDialogMaterial())
      .shadow(uiDialogSurfaceShadow())
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }
}
