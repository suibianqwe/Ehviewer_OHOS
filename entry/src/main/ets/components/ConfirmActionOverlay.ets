import { uiText } from '../shared/EhShared';
import {
  themeDangerBackground,
  themeDangerText,
  themeOnPrimaryText,
  themePrimaryText,
  themeScrimColor,
  themeSecondaryText,
  themeSurface,
  themeSurfaceVariant
} from '../shared/EhTheme';
import { uiControlRadius, uiDialogMaterial, uiPanelRadius } from '../shared/EhUiStyle';

@Component
export struct ConfirmActionOverlay {
  title: string = '';
  message: string = '';
  confirmLabel: string = 'OK';
  danger: boolean = true;
  onCancel: () => void = () => {};
  onConfirm: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(themeScrimColor())
        .onClick(this.onCancel)

      Column() {
        Text(uiText(this.title))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .width('100%')
        Text(uiText(this.message))
          .fontSize(14)
          .fontColor(themeSecondaryText())
          .lineHeight(20)
          .width('100%')
          .margin({ top: 10 })

        Row({ space: 8 }) {
          Button(uiText('Cancel'), { type: ButtonType.Normal, stateEffect: true })
            .fontSize(14)
            .fontColor(themePrimaryText())
            .backgroundColor(themeSurfaceVariant())
            .borderRadius(uiControlRadius(6))
            .layoutWeight(1)
            .onClick(this.onCancel)
          Button(uiText(this.confirmLabel), { type: ButtonType.Normal, stateEffect: true })
            .fontSize(14)
            .fontColor(this.danger ? themeDangerText() : themeOnPrimaryText())
            .backgroundColor(this.danger ? themeDangerBackground() : themeSurfaceVariant())
            .borderRadius(uiControlRadius(6))
            .layoutWeight(1)
            .onClick(this.onConfirm)
        }
        .width('100%')
        .margin({ top: 18 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 420 })
      .padding(18)
      .backgroundColor(themeSurface())
      .borderRadius(uiPanelRadius(8))
      .systemMaterial(uiDialogMaterial())
      .shadow({ radius: 18, color: '#33000000', offsetX: 0, offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }
}
