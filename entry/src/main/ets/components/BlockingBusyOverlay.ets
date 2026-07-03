import { uiText } from '../shared/EhShared';
import {
  themePrimaryText,
  themeScrimColor,
  themeSecondaryText,
  themeShadowColor,
  themeSurface
} from '../shared/EhTheme';

@Component
export struct BlockingBusyOverlay {
  @Prop message: string = 'Loading...';

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
        Text(uiText('Please wait...'))
          .fontSize(12)
          .fontColor(themeSecondaryText())
          .textAlign(TextAlign.Center)
      }
      .width(230)
      .constraintSize({ maxWidth: '72%' })
      .padding({ left: 20, right: 20, top: 20, bottom: 18 })
      .backgroundColor(themeSurface())
      .borderRadius(8)
      .shadow({ radius: 18, color: themeShadowColor(), offsetX: 0, offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }
}
