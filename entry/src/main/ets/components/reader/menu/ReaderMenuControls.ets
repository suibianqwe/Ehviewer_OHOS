import {
  normalizeAutoTransferTimeOption,
  normalizeBrightnessLevelOption,
  normalizeUltraDarkLightnessOption,
  uiText,
  uiValue
} from '../../../shared/EhShared';
import { readerSelectColors, selectArrowModifier } from '../../../shared/EhSelectStyle';
import { themeDividerColor, themePrimaryText, themeScrimColor, themeSurface } from '../../../shared/EhTheme';

@Component
export struct ReaderPopupBackdrop {
  onDismiss: () => void = () => {};

  build() {
    Stack() {}
      .width('100%')
      .height('100%')
      .backgroundColor(themeScrimColor())
      .onClick(() => {
        this.onDismiss();
      })
      .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
  }
}

@Component
export struct ReaderImageActionDialog {
  onRefresh: () => void = () => {};
  onShare: () => void = () => {};
  onSaveToAlbum: () => void = () => {};
  onSave: () => void = () => {};

  build() {
    Column({ space: 0 }) {
      ReaderImageActionButton({
        label: uiText('Refresh'),
        symbolIcon: $r('sys.symbol.arrow_clockwise'),
        onTap: this.onRefresh
      })
      ReaderMenuDivider()
      ReaderImageActionButton({
        label: uiText('Share'),
        symbolIcon: $r('sys.symbol.share'),
        onTap: this.onShare
      })
      ReaderMenuDivider()
      SaveButton({
        icon: SaveIconStyle.LINES,
        text: SaveDescription.SAVE_TO_GALLERY,
        buttonType: ButtonType.Normal
      })
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .fontSize(15)
        .fontColor(themePrimaryText())
        .iconSize(20)
        .layoutDirection(SecurityComponentLayoutDirection.HORIZONTAL)
        .onClick((_event: ClickEvent, result: SaveButtonOnClickResult) => {
          if (result === SaveButtonOnClickResult.SUCCESS) {
            this.onSaveToAlbum();
          }
        })
      ReaderMenuDivider()
      ReaderImageActionButton({
        label: uiText('Save to...'),
        symbolIcon: $r('sys.symbol.save'),
        onTap: this.onSave
      })
    }
    .width('78%')
    .constraintSize({ maxWidth: 360 })
    .padding({ top: 6, bottom: 6 })
    .backgroundColor(themeSurface())
    .borderRadius(12)
    .clip(true)
    .shadow({ radius: 18, color: '#66000000', offsetY: 8 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
  }
}

@Component
struct ReaderImageActionButton {
  label: string = '';
  symbolIcon: Resource = $r('sys.symbol.circle');
  onTap: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row() {
        SymbolGlyph(this.symbolIcon)
          .fontSize(20)
          .fontColor([themePrimaryText()])
        Text(this.label)
          .fontSize(15)
          .fontColor(themePrimaryText())
          .margin({ left: 12 })
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height(48)
    .backgroundColor(Color.Transparent)
    .borderRadius(0)
    .onClick(() => {
      this.onTap();
    })
  }
}

@Component
export struct ReaderMenuDivider {
  build() {
    Divider()
      .height(1)
      .color(themeDividerColor())
      .margin({ left: 16, right: 16 })
  }
}

@Component
export struct ReaderMenuSelect {
  label: string = '';
  options: string[] = [];
  value: string = '';
  onChange: (v: string) => void = () => {};

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor('#E5E7EB')
        .layoutWeight(1)
      Select(this.options.map((o: string) => ({ value: uiValue(o) } as SelectOption)))
        .id('reader-menu-select-' + this.label + '-' + this.value)
        .selected(readerMenuOptionIndex(this.options, this.value))
        .value(uiValue(this.value))
        .font({ size: 13 })
        .fontColor(readerSelectColors().buttonText)
        .backgroundColor(readerSelectColors().buttonBackground)
        .menuBackgroundColor(readerSelectColors().menuBackground)
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .optionBgColor(readerSelectColors().optionBackground)
        .optionFontColor(readerSelectColors().optionText)
        .optionFont({ size: 13 })
        .selectedOptionBgColor(readerSelectColors().selectedOptionBackground)
        .selectedOptionFontColor(readerSelectColors().selectedOptionText)
        .menuOutline({ width: 1, color: readerSelectColors().outline })
        .arrowModifier(selectArrowModifier(readerSelectColors().arrow))
        .onSelect((idx: number) => {
          if (idx >= 0 && idx < this.options.length) {
            this.onChange(this.options[idx]);
          }
        })
        .height(32)
        .constraintSize({ minWidth: 136, maxWidth: 188 })
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct ReaderMenuSlider {
  label: string = '';
  @Prop @Watch('onValueChange') value: number = 0;
  min: number = 0;
  max: number = 100;
  step: number = 1;
  valueText: (v: number) => string = (v: number): string => v.toString();
  onChange: (v: number) => void = () => {};
  @State liveValue: number = 0;

  aboutToAppear(): void {
    this.liveValue = this.value;
  }

  onValueChange(): void {
    this.liveValue = this.value;
  }

  build() {
    Column({ space: 4 }) {
      Row() {
        Text(this.label)
          .fontSize(14)
          .fontColor('#E5E7EB')
          .layoutWeight(1)
        Text(this.valueText(this.liveValue))
          .fontSize(13)
          .fontColor('#CBD5E1')
          .width(54)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Slider({
        value: this.liveValue,
        min: this.min,
        max: this.max,
        step: this.step
      })
        .width('100%')
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.liveValue = Math.max(this.min, Math.min(this.max, Math.round(value)));
          this.onChange(this.liveValue);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 8 })
  }
}

function readerMenuOptionIndex(options: string[], value: string): number {
  for (let i = 0; i < options.length; i++) {
    if (options[i] === value) {
      return i;
    }
  }
  return 0;
}

export function readerAutoTransferSliderValue(value: string): number {
  return Number.parseInt(normalizeAutoTransferTimeOption(value));
}

export function readerAutoTransferValue(value: number): string {
  return Math.max(1, Math.min(20, Math.round(value))).toString() + 's';
}

export function readerBrightnessSliderValue(value: string): number {
  const numberValue = Number.parseInt(value);
  if (Number.isNaN(numberValue)) {
    return 50;
  }
  return Math.max(0, Math.min(100, numberValue));
}

export function readerBrightnessValue(value: number): string {
  return normalizeBrightnessLevelOption(Math.max(0, Math.min(100, Math.round(value))).toString() + '%');
}

export function readerUltraDarkSliderValue(value: string): number {
  const numberValue = Number.parseInt(value);
  if (Number.isNaN(numberValue)) {
    return 50;
  }
  return Math.max(1, Math.min(100, numberValue));
}

export function readerUltraDarkValue(value: number): string {
  return normalizeUltraDarkLightnessOption(Math.max(1, Math.min(100, Math.round(value))).toString() + '%');
}


@Component
export struct ReaderMenuToggle {
  label: string = '';
  value: boolean = false;
  onChange: (v: boolean) => void = () => {};

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor('#E5E7EB')
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.value })
        .onChange((v: boolean) => { this.onChange(v); })
        .selectedColor('#2F6F8F')
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }
}
