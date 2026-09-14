import { uiText } from '../shared/EhShared';
import {
  themeDangerBackground,
  themeDangerText,
  themeOnPrimaryText,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSurfaceVariant
} from '../shared/EhTheme';
import {
  uiControlRadius,
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiDialogSurfaceBackground,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow,
  uiButtonMaterial,
  uiFloatingButtonBackgroundEffect,
  uiTransparentButtonBackgroundEffect,
  uiMaterialBackground,
  uiMaterialForegroundColor
} from '../shared/EhUiStyle';
import { PopupScrim } from './PopupScrim';

@Component
export struct ConfirmActionOverlay {
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;
  title: string = '';
  message: string = '';
  confirmLabel: string = 'OK';
  altLabel: string = '';
  danger: boolean = true;
  showCancel: boolean = true;
  onCancel: () => void = () => {};
  onConfirm: () => void = () => {};
  onAlt: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      PopupScrim({
        showCutout: this.popupWidth > 0 && this.popupHeight > 0,
        cutoutWidth: this.popupWidth,
        cutoutHeight: this.popupHeight,
        cutoutRadius: uiDialogSurfaceRadius(),
        onDismiss: this.onCancel
      })

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
          if (this.showCancel) {
            Button(uiText('Cancel'), { type: ButtonType.Normal, stateEffect: true })
              .fontSize(14)
              .fontColor(uiMaterialForegroundColor(themePrimaryText()))
              .backgroundColor(uiMaterialBackground(themeSurfaceVariant()))
              .layoutWeight(1)
              .borderRadius(uiControlRadius(6))
              .backgroundEffect(uiTransparentButtonBackgroundEffect())
              .systemMaterial(uiButtonMaterial())
              .onClick(this.onCancel)
          }
          if (this.altLabel.length > 0) {
            Button(uiText(this.altLabel), { type: ButtonType.Normal, stateEffect: true })
              .fontSize(14)
              .fontColor(uiMaterialForegroundColor(themePrimaryText()))
              .backgroundColor(uiMaterialBackground(themeSurfaceVariant()))
              .layoutWeight(1)
              .borderRadius(uiControlRadius(6))
              .backgroundEffect(uiTransparentButtonBackgroundEffect())
              .systemMaterial(uiButtonMaterial())
              .onClick(this.onAlt)
          }
          Button(uiText(this.confirmLabel), { type: ButtonType.Normal, stateEffect: true })
            .fontSize(14)
            .fontColor(this.danger ? themeDangerText() : uiMaterialForegroundColor(themeOnPrimaryText()))
            .backgroundColor(uiMaterialBackground(this.danger ? themeDangerBackground() : themePrimaryColor()))
            .layoutWeight(1)
            .borderRadius(uiControlRadius(6))
            .backgroundEffect(uiFloatingButtonBackgroundEffect(this.danger ?
              themeDangerBackground() : themePrimaryColor()))
            .systemMaterial(uiButtonMaterial())
            .onClick(this.onConfirm)
        }
        .width('100%')
        .margin({ top: 18 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 420 })
      .padding(18)
      .backgroundColor(uiDialogSurfaceBackground())
      .shadow(uiDialogSurfaceShadow())
      .borderRadius(uiDialogSurfaceRadius())
      .backgroundBlurStyle(uiDialogBlurStyle(), uiDialogBlurOptions())
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
