import { ReleaseInfo } from '../services/EhUpdateChecker';
import { uiText } from '../shared/EhShared';
import {
  themeOnPrimaryText,
  themePrimaryColor,
  themePrimaryText,
  themeScrimColor,
  themeSecondaryText,
  themeSurface,
  themeSurfaceVariant,
  themeTertiaryText
} from '../shared/EhTheme';
import {
  uiButtonMaterial,
  uiControlRadius,
  uiDialogMaterial,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiPanelRadius
} from '../shared/EhUiStyle';

@Component
export struct UpdatePromptOverlay {
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
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(themeScrimColor())
        .onClick(this.onCancel)

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
            .systemMaterial(uiButtonMaterial())
            .borderRadius(uiControlRadius(6))
            .layoutWeight(1)
            .onClick(this.onCancel)
          Button(uiText('Update'), { type: ButtonType.Normal, stateEffect: true })
            .height(38)
            .fontSize(14)
            .fontColor(uiMaterialForegroundColor(themeOnPrimaryText()))
            .backgroundColor(themePrimaryColor())
            .systemMaterial(uiButtonMaterial())
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
      .backgroundColor(uiMaterialBackground(themeSurface()))
      .borderRadius(uiPanelRadius(8))
      .systemMaterial(uiDialogMaterial())
      .shadow({
        radius: 18,
        color: '#33000000',
        offsetX: 0,
        offsetY: 8
      })
    }
    .width('100%')
    .height('100%')
  }
}
