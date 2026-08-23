import {
  uiButtonMaterial,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiRadius
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
      .backgroundColor(uiMaterialBackground(this.active ? '#334155' : '#1F2937'))
      .systemMaterial(uiButtonMaterial())
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
    .backgroundColor(uiMaterialBackground(this.active ? '#2F6F8F' : '#1F2937'))
    .systemMaterial(uiButtonMaterial())
    .borderRadius(uiRadius(4))
    .onClick(() => {
      if (this.active) {
        this.onTap();
      }
    })
  }
}
