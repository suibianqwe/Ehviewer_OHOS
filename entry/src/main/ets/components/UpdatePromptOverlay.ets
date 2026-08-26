import { ReleaseInfo } from '../services/EhUpdateChecker';
import { uiText } from '../shared/EhShared';
import {
  themeOnPrimaryText,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSurfaceVariant,
  themeTertiaryText
} from '../shared/EhTheme';
import {
  uiTransparentButtonBackgroundEffect,
  uiControlRadius,
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiDialogMaterial,
  uiDialogSurfaceBackground,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow,
  uiMaterialForegroundColor
} from '../shared/EhUiStyle';
import { PopupScrim } from './PopupScrim';

@Component
export struct UpdatePromptOverlay {
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;
  release: ReleaseInfo | null = null;
  currentVersion: string = '';
  onCancel: () => void = () => {};
  onUpdate: () => void = () => {};

  private releaseTitle(): string {
    if (this.release === null) {
      return '';
    }
    return this.release.name + ' (' + this.release.tagName + ')';
  }

  private releaseBody(): string {
    if (this.release === null || this.release.body.length === 0) {
      return uiText('No release notes');
    }
    return this.release.body;
  }

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
        Text(uiText('New version available'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .width('100%')
        Text(uiText('Current version') + ': ' + this.currentVersion)
          .fontSize(12)
          .fontColor(themeTertiaryText())
          .width('100%')
          .margin({ top: 6 })
        Text(this.releaseTitle())
          .fontSize(14)
          .fontColor(themeSecondaryText())
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .margin({ top: 12 })

        Scroll() {
          Text(this.releaseBody())
            .fontSize(13)
            .fontColor(themeSecondaryText())
            .lineHeight(20)
            .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: 260 })
        .margin({ top: 10 })

        Row({ space: 10 }) {
          Button(uiText('Cancel'), { type: ButtonType.Normal, stateEffect: true })
            .height(38)
            .fontSize(14)
            .fontColor(uiMaterialForegroundColor(themePrimaryText()))
            .backgroundColor(themeSurfaceVariant())
            .backgroundEffect(uiTransparentButtonBackgroundEffect())
            .borderRadius(uiControlRadius(6))
            .layoutWeight(1)
            .onClick(this.onCancel)
          Button(uiText('Update'), { type: ButtonType.Normal, stateEffect: true })
            .height(38)
            .fontSize(14)
            .fontColor(uiMaterialForegroundColor(themeOnPrimaryText()))
            .backgroundColor(themePrimaryColor())
            .backgroundEffect(uiTransparentButtonBackgroundEffect())
            .borderRadius(uiControlRadius(6))
            .layoutWeight(1)
            .onClick(this.onUpdate)
        }
        .width('100%')
        .margin({ top: 18 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 460 })
      .padding(18)
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
  }
}
