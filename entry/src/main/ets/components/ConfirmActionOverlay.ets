import { uiText } from '../shared/EhShared';
import {
  themeDangerBackground,
  themeDangerText,
  themeOnPrimaryText,
  themePrimaryText,
  themeScrimColor,
  themeSecondaryText,
  themeSurfaceVariant
} from '../shared/EhTheme';
import {
  uiButtonMaterial,
  uiControlRadius,
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiDialogMaterial,
  uiDialogSurfaceBackground,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow,
  uiMaterialForegroundColor
} from '../shared/EhUiStyle';

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
            .fontColor(uiMaterialForegroundColor(themePrimaryText()))
            .backgroundColor(themeSurfaceVariant())
            .systemMaterial(uiButtonMaterial())
            .borderRadius(uiControlRadius(6))
            .layoutWeight(1)
            .onClick(this.onCancel)
          Button(uiText(this.confirmLabel), { type: ButtonType.Normal, stateEffect: true })
            .fontSize(14)
            .fontColor(this.danger ? themeDangerText() : uiMaterialForegroundColor(themeOnPrimaryText()))
            .backgroundColor(this.danger ? themeDangerBackground() : themeSurfaceVariant())
            .systemMaterial(uiButtonMaterial())
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
      .backgroundColor(uiDialogSurfaceBackground())
      .systemMaterial(uiDialogMaterial())
      .backgroundBlurStyle(uiDialogBlurStyle(), uiDialogBlurOptions())
      .borderRadius(uiDialogSurfaceRadius())
      .shadow(uiDialogSurfaceShadow())
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }
}
