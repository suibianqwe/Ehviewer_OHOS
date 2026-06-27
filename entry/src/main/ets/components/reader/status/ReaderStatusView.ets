import { uiText } from '../../../shared/EhShared';
import { themeOnPrimarySecondaryText, themeScrimColor } from '../../../shared/EhTheme';

@Component
export struct ReaderStatusView {
  failed: boolean = false;
  compact: boolean = false;
  @Prop progress: number = -1;
  onRetry: () => void = () => {};

  private iconSize(): number {
    return this.compact ? 32 : 44;
  }

  private ringStrokeWidth(): number {
    return this.compact ? 3 : 4;
  }

  private progressValue(): number {
    if (this.progress >= 0) {
      return Math.max(0, Math.min(100, this.progress));
    }
    return 0;
  }

  private trackColor(): string {
    return '#5F6875';
  }

  build() {
    Column({ space: this.compact ? 8 : 12 }) {
      if (this.failed) {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
          .fontSize(32)
          .fontColor(['#98A2B3'])
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Progress({ value: 100, total: 100, type: ProgressType.Ring })
            .width(this.iconSize())
            .height(this.iconSize())
            .color(this.trackColor())
            .style({ strokeWidth: this.ringStrokeWidth(), enableSmoothEffect: false })
          Progress({ value: this.progressValue(), total: 100, type: ProgressType.Ring })
            .width(this.iconSize())
            .height(this.iconSize())
            .color(themeOnPrimarySecondaryText())
            .style({ strokeWidth: this.ringStrokeWidth(), enableSmoothEffect: false })
        }
          .width(this.iconSize())
          .height(this.iconSize())
          .padding(8)
          .backgroundColor(themeScrimColor())
          .borderRadius(this.iconSize() / 2)
      }
      if (!this.compact || this.failed) {
        Text(this.failed ? uiText('Image page failed to load') : uiText('Image page is loading'))
          .fontSize(16)
          .fontColor('#98A2B3')
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      if (this.failed) {
        this.onRetry();
      }
    })
  }
}
