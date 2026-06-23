import { uiText } from '../../../shared/EhShared';
import { themeOnPrimarySecondaryText, themeScrimColor } from '../../../shared/EhTheme';

@Component
export struct ReaderStatusView {
  failed: boolean = false;
  compact: boolean = false;
  onRetry: () => void = () => {};

  private iconSize(): number {
    return this.compact ? 32 : 44;
  }

  build() {
    Column({ space: this.compact ? 8 : 12 }) {
      if (this.failed) {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
          .fontSize(32)
          .fontColor(['#98A2B3'])
      } else {
        LoadingProgress()
          .width(this.iconSize())
          .height(this.iconSize())
          .color(themeOnPrimarySecondaryText())
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
