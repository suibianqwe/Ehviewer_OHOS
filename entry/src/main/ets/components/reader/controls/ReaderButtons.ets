import {
  uiButtonHighlightBorderColor,
  uiMaterialLayerBackground,
  uiMaterialForegroundColor,
  uiRadius,
  uiTintedButtonMaterial
} from '../../../shared/EhUiStyle';

@Component
export struct ReaderToolButton {
  text: string = '';
  active: boolean = true;
  onTap: () => void = () => {};

  build() {
    Button(this.text)
      .height(32)
      .fontSize(12)
      .fontColor(this.active ? uiMaterialForegroundColor(Color.White) : '#6B7280')
      .backgroundColor(uiMaterialLayerBackground(this.active ? '#334155' : '#1F2937'))
      .systemMaterial(uiTintedButtonMaterial(this.active ? '#334155' : '#1F2937'))
      .border({ width: 1, color: uiButtonHighlightBorderColor() })
      .enabled(this.active)
      .onClick(() => {
        if (this.active) {
          this.onTap();
        }
      })
  }
}

@Component
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
    .backgroundColor(uiMaterialLayerBackground(this.active ? '#2F6F8F' : '#1F2937'))
    .systemMaterial(uiTintedButtonMaterial(this.active ? '#2F6F8F' : '#1F2937'))
    .borderRadius(uiRadius(4))
    .border({ width: 1, color: uiButtonHighlightBorderColor() })
    .onClick(() => {
      if (this.active) {
        this.onTap();
      }
    })
  }
}
