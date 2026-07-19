import {
  normalizeAutoTransferTimeOption,
  normalizeBrightnessLevelOption,
  normalizeUltraDarkLightnessOption,
  uiText,
  uiValue
} from '../../../shared/EhShared';
import { readerSelectColors } from '../../../shared/EhSelectStyle';
import { themeScrimColor } from '../../../shared/EhTheme';

const READER_MENU_SURFACE = '#EE111827';
const READER_MENU_ITEM_TEXT = '#E5E7EB';
const READER_MENU_ITEM_ICON = '#FFFFFF';
const READER_MENU_DIVIDER = '#334155';

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
  onSaveToAlbum: (result: SaveButtonOnClickResult) => void = (_result: SaveButtonOnClickResult) => {};
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
        .fontColor(READER_MENU_ITEM_TEXT)
        .iconColor(READER_MENU_ITEM_ICON)
        .iconSize(20)
        .layoutDirection(SecurityComponentLayoutDirection.HORIZONTAL)
        .onClick((_event: ClickEvent, result: SaveButtonOnClickResult) => {
          this.onSaveToAlbum(result);
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
    .backgroundColor(READER_MENU_SURFACE)
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
          .fontColor([READER_MENU_ITEM_ICON])
        Text(this.label)
          .fontSize(15)
          .fontColor(READER_MENU_ITEM_TEXT)
          .margin({ left: 12 })
          .layoutWeight(1)
          .textAlign(TextAlign.End)
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
      .color(READER_MENU_DIVIDER)
      .margin({ left: 16, right: 16 })
  }
}

@Component
export struct ReaderMenuSelect {
  label: string = '';
  options: string[] = [];
  value: string = '';
  onChange: (v: string) => void = () => {};
  @State expanded: boolean = false;

  build() {
    Column() {
      Row() {
        Text(this.label)
          .fontSize(14)
          .fontColor('#E5E7EB')
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Row() {
            Text(uiValue(this.value))
              .fontSize(13)
              .fontColor(readerSelectColors().buttonText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .textAlign(TextAlign.End)
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(14)
              .fontColor([readerSelectColors().arrow])
              .margin({ left: 6 })
              .rotate({ angle: this.expanded ? 180 : 0 })
          }
          .width('100%')
          .padding({ left: 10, right: 8 })
        }
        .height(32)
        .constraintSize({ minWidth: 136, maxWidth: 188 })
        .backgroundColor(readerSelectColors().buttonBackground)
        .borderRadius(8)
        .onClick(() => {
          this.expanded = !this.expanded;
        })
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .alignItems(VerticalAlign.Center)

      if (this.expanded) {
        Column({ space: 2 }) {
          ForEach(this.options, (option: string, index: number) => {
            Button({ type: ButtonType.Normal, stateEffect: true }) {
              Row() {
                Text(uiValue(option))
                  .fontSize(13)
                  .fontColor(option === this.value ?
                    readerSelectColors().selectedOptionText : readerSelectColors().optionText)
                  .layoutWeight(1)
                  .textAlign(TextAlign.Start)
                if (option === this.value) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(14)
                    .fontColor([readerSelectColors().selectedOptionText])
                }
              }
              .width('100%')
              .padding({ left: 12, right: 12 })
            }
            .width('100%')
            .height(36)
            .backgroundColor(option === this.value ?
              readerSelectColors().selectedOptionBackground : readerSelectColors().optionBackground)
            .borderRadius(8)
            .onClick(() => {
              this.expanded = false;
              this.onChange(option);
            })
          }, (option: string, index: number) => option + '-' + index.toString())
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
      }
    }
    .width('100%')
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
  @Prop value: boolean = false;
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
