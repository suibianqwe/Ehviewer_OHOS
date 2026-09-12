import {
  uiButtonHighlightBorderColor,
  uiMaterialLayerBackground,
  uiMaterialForegroundColor,
  uiFloatingButtonBackgroundEffect,
  uiRadius,
  uiTintedButtonMaterial,
  uiMaterialBackground
} from '../../../shared/EhUiStyle';

@Component
// Reader buttons carry material/blur styling reused across reader hosts.
// eslint-disable-next-line @performance/avoid-overusing-custom-component-check
export struct ReaderToolButton {
  text: string = '';
  active: boolean = true;
  onTap: () => void = () => {};

  build() {
    Button(this.text)
      .height(32)
      .fontSize(12)
      .fontColor(this.active ? uiMaterialForegroundColor(Color.White) : '#6B7280')
      .backgroundColor(uiMaterialBackground(uiMaterialLayerBackground(this.active ? '#334155' : '#1F2937')))
      .enabled(this.active)
      .border({ width: 1, color: uiButtonHighlightBorderColor() })
      .backgroundEffect(uiFloatingButtonBackgroundEffect(this.active ? '#334155' : '#1F2937'))
      .systemMaterial(uiTintedButtonMaterial(this.active ? '#334155' : '#1F2937'))
      .onClick(() => {
        if (this.active) {
          this.onTap();
        }
      })
  }
}

@Component
// eslint-disable-next-line @performance/avoid-overusing-custom-component-check
export struct ReaderNavButton {
  text: string = '';
  active: boolean = true;
  onTap: () => void = () => {};

  build() {
    Row() {
      Text(this.text)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.active ? uiMaterialForegroundColor(Color.White) : '#98A2B3')
    }
    .justifyContent(FlexAlign.Center)
    .height(42)
    .width('100%')
    .backgroundColor(uiMaterialBackground(uiMaterialLayerBackground(this.active ? '#2F6F8F' : '#1F2937')))
    .border({ width: 1, color: uiButtonHighlightBorderColor() })
    .borderRadius(uiRadius(4))
    .backgroundEffect(uiFloatingButtonBackgroundEffect(this.active ? '#2F6F8F' : '#1F2937'))
    .systemMaterial(uiTintedButtonMaterial(this.active ? '#2F6F8F' : '#1F2937'))
    .onClick(() => {
      if (this.active) {
        this.onTap();
      }
    })
  }
}
