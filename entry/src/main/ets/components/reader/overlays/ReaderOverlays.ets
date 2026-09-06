import {
  readerClockText,
  uiText,
  uiValue
} from '../../../shared/EhShared';
import {
  themeAccentTextColor,
  themeDangerBackground,
  themeDangerText,
  themeOnPrimaryText,
  themePrimaryColor,
  themePrimaryText,
  themeScrimColor,
  themeSecondaryText,
  themeSurface,
  themeSurfaceVariant
} from '../../../shared/EhTheme';
import {
  isHarmonyMaterialEnabled,
  isHarmonyUiStyle,
  uiButtonHighlightBorderColor,
  uiButtonMaterial,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiMaterialLayerBackground,
  uiPopupBackgroundEffect,
  uiPopupEffectBackground,
  uiReaderMenuBackgroundEffect,
  uiReaderProgressBackgroundColor,
  uiReaderProgressBackgroundEffect,
  uiReaderOptionControlBackground,
  uiReaderOptionButtonMaterial,
  uiRadius,
  uiSearchFieldHeight,
  uiInputFieldBorder,
  uiSearchMaterial,
  uiTabHeight,
  uiTintedButtonMaterial,
} from '../../../shared/EhUiStyle';
import { PopupScrim } from '../../PopupScrim';
import {
  readerAutoTransferSliderValue,
  readerAutoTransferValue,
  readerBrightnessSliderValue,
  readerBrightnessValue,
  ReaderImageActionDialog,
  ReaderMenuDivider,
  ReaderMenuSelect,
  ReaderMenuSlider,
  ReaderMenuToggle,
  ReaderPopupBackdrop,
  readerUltraDarkSliderValue,
  readerUltraDarkValue
} from '../menu/ReaderMenuControls';

function adjustmentValueText(value: number): string {
  const rounded = Math.round(value);
  return (rounded > 0 ? '+' : '') + rounded.toString();
}

function exposureValueText(value: number): string {
  const ev = Math.round(value) / 50;
  return (ev > 0 ? '+' : '') + ev.toFixed(2) + ' EV';
}

function degreeValueText(value: number): string {
  return Math.round(value).toString() + '°';
}

const READER_SLIDER_BAR_HEIGHT: number = 50;
const READER_SLIDER_PANEL_TOP_PADDING: number = 10;
const READER_SLIDER_PANEL_BOTTOM_PADDING: number = 20;

@Component
export struct ReaderInfoOverlay {
  @Prop showProgress: boolean = true;
  @Prop showClock: boolean = true;
  @Prop showBattery: boolean = true;
  @Prop progressText: string = '';
  @Prop clockText: string = '';
  @Prop batteryText: string = '';
  @Prop top: number = 0;
  @Prop right: number = 12;

  build() {
    Row({ space: 6 }) {
      if (this.showClock) {
        Text(this.clockText)
          .fontSize(14)
          .fontColor(themeOnPrimaryText())
          .lineHeight(16)
          .maxLines(1)
      }
      if (this.showProgress) {
        ReaderProgressText({
          text: this.progressText,
          fontSize: 14,
          fontColor: themeOnPrimaryText(),
          textWidth: 0,
          textHeight: 16
        })
      }
      if (this.showBattery) {
        Text(this.batteryText)
          .fontSize(14)
          .fontColor(themeOnPrimaryText())
          .lineHeight(16)
          .maxLines(1)
      }
    }
    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
    .backgroundColor(themeScrimColor())
    .borderRadius(uiRadius(10))
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

@Component
struct ReaderProgressText {
  @Prop text: string = '';
  @Prop fontSize: number = 14;
  @Prop fontColor: ResourceColor = '#E5E7EB';
  @Prop textWidth: number = 54;
  @Prop textHeight: number = 50;

  build() {
    Text(this.text)
      .fontSize(this.fontSize)
      .fontColor(this.fontColor)
      .lineHeight(Math.max(16, this.fontSize + 2))
      .maxLines(1)
      .textAlign(TextAlign.Center)
      .width(this.textWidth > 0 ? this.textWidth : 'auto')
      .height(this.textHeight)
  }
}

@Component
struct ReaderSliderBubble {
  @Prop @Watch('onTextChange') text: string = '';
  @State displayText: string = '';

  aboutToAppear(): void {
    this.displayText = this.text;
  }

  onTextChange(): void {
    this.displayText = this.text;
  }

  build() {
    Text(this.displayText)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(isHarmonyUiStyle() ? themePrimaryText() : Color.White)
      .lineHeight(40)
      .textAlign(TextAlign.Center)
      .textVerticalAlign(TextVerticalAlign.CENTER)
      .width(40)
      .height(40)
      .backgroundColor(uiReaderProgressBackgroundColor('#1F2937'))
      .backgroundEffect(uiReaderProgressBackgroundEffect())
      .borderRadius(uiRadius(20))
      .borderWidth(1)
      .borderColor(isHarmonyUiStyle() ? uiButtonHighlightBorderColor() : '#3F4756')
      .shadow({ radius: 8, color: 'rgba(0,0,0,0.45)', offsetX: 0, offsetY: 2 })
  }
}

@Component
struct ReaderSliderPageText {
  @Prop text: string = '';

  build() {
    Column() {
      ReaderProgressText({
        text: this.text,
        fontSize: 14,
        fontColor: isHarmonyUiStyle() ? themePrimaryText() : '#E5E7EB',
        textWidth: 54,
        textHeight: 50
      })
    }
    .width(54)
    .height(50)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

@Component
struct ReaderAutoTransferButton {
  @Prop autoTransferPlaying: boolean = false;
  @Prop autoTransferEnabled: boolean = false;
  onToggleAutoTransfer: () => void = () => {};

  build() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(this.autoTransferPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
        .fontSize(24)
        .fontColor([uiMaterialForegroundColor(isHarmonyUiStyle() ? themePrimaryText() : Color.White)])
    }
    .width(50)
    .height(50)
    .enabled(this.autoTransferEnabled)
    .backgroundColor(uiReaderOptionControlBackground(this.autoTransferEnabled ? '#334155' : '#1F2937'))
    .systemMaterial(uiReaderOptionButtonMaterial())
    .border({
      width: isHarmonyUiStyle() ? 1 : 0,
      color: uiButtonHighlightBorderColor()
    })
    .onClick(() => {
      this.onToggleAutoTransfer();
    })
  }
}

@Component
struct ReaderSliderTrack {
  @Prop sliderLiveIndex: number = 0;
  @Prop totalPages: number = 0;
  onSliderChange: (value: number, mode: SliderChangeMode) => void = (_value: number, _mode: SliderChangeMode) => {};
  onTrackWidthChange: (width: number) => void = (_width: number) => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Slider({
        value: this.sliderLiveIndex,
        min: 0,
        max: Math.max(0, this.totalPages - 1),
        step: 1
      })
        .width('100%')
        .height(36)
        .enabled(this.totalPages > 1)
        .onChange((value: number, mode: SliderChangeMode) => {
          this.onSliderChange(value, mode);
        })
    }
    .layoutWeight(1)
    .height(50)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const width = newArea.width as number;
      if (width > 0 && !Number.isNaN(width)) {
        this.onTrackWidthChange(width);
      }
    })
  }
}

@Component
struct ReaderSliderBar {
  @Prop progressText: string = '';
  @Prop sliderLiveIndex: number = 0;
  @Prop totalPages: number = 0;
  @Prop autoTransferPlaying: boolean = false;
  @Prop autoTransferEnabled: boolean = false;
  onSliderChange: (value: number, mode: SliderChangeMode) => void = (_value: number, _mode: SliderChangeMode) => {};
  onTrackWidthChange: (width: number) => void = (_width: number) => {};
  onToggleAutoTransfer: () => void = () => {};

  build() {
    Row() {
      ReaderSliderPageText({ text: this.progressText })

      ReaderSliderTrack({
        sliderLiveIndex: this.sliderLiveIndex,
        totalPages: this.totalPages,
        onSliderChange: this.onSliderChange,
        onTrackWidthChange: this.onTrackWidthChange
      })

      ReaderAutoTransferButton({
        autoTransferPlaying: this.autoTransferPlaying,
        autoTransferEnabled: this.autoTransferEnabled,
        onToggleAutoTransfer: this.onToggleAutoTransfer
      })
    }
    .width('100%')
    .height(READER_SLIDER_BAR_HEIGHT)
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct ReaderSliderPanel {
  @Prop progressText: string = '';
  @Prop sliderDragging: boolean = false;
  @Prop sliderPageText: string = '';
  @Prop sliderBubbleX: number = 0;
  @Prop sliderTrackWidth: number = 1;
  @Prop sliderLiveIndex: number = 0;
  @Prop totalPages: number = 0;
  @Prop bottomInset: number = 0;
  @Prop autoTransferPlaying: boolean = false;
  @Prop autoTransferEnabled: boolean = false;
  onDismiss: () => void = () => {};
  onSliderChange: (value: number, mode: SliderChangeMode) => void = (_value: number, _mode: SliderChangeMode) => {};
  onTrackWidthChange: (width: number) => void = (_width: number) => {};
  onToggleAutoTransfer: () => void = () => {};

  private sliderBubbleLeft(): number {
    const bubbleSize = 40;
    const maxLeft = Math.max(0, this.sliderTrackWidth - bubbleSize);
    return Math.max(0, Math.min(maxLeft, this.sliderBubbleX - bubbleSize / 2));
  }

  private panelHeight(): number {
    return READER_SLIDER_BAR_HEIGHT + READER_SLIDER_PANEL_TOP_PADDING +
      READER_SLIDER_PANEL_BOTTOM_PADDING + Math.max(0, this.bottomInset);
  }

  private bubbleBottomMargin(): number {
    // Bubble sits just above the panel's top edge, completely clear of the panel background.
    return this.panelHeight() + 4;
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Stack() {}
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.onDismiss();
        })
        .hitTestBehavior(HitTestMode.Transparent)
        .zIndex(0)

      if (this.sliderDragging) {
        Row() {
          Blank()
            .width(54)
          Stack() {
            ReaderSliderBubble({ text: this.sliderPageText })
              .position({ x: this.sliderBubbleLeft(), y: 0 })
          }
          .layoutWeight(1)
          .height(40)
          Blank()
            .width(50)
        }
        .width('100%')
        .height(40)
        .padding({ left: 10, right: 10 })
        .offset({ y: -this.bubbleBottomMargin() })
        .zIndex(2)
        .hitTestBehavior(HitTestMode.None)
      }

      Column() {
        ReaderSliderBar({
          progressText: this.progressText,
          sliderLiveIndex: this.sliderLiveIndex,
          totalPages: this.totalPages,
          autoTransferPlaying: this.autoTransferPlaying,
          autoTransferEnabled: this.autoTransferEnabled,
          onSliderChange: this.onSliderChange,
          onTrackWidthChange: this.onTrackWidthChange,
          onToggleAutoTransfer: this.onToggleAutoTransfer
        })
      }
      .width('100%')
      .height(this.panelHeight())
      .padding({
        left: 10,
        right: 10,
        top: READER_SLIDER_PANEL_TOP_PADDING,
        bottom: READER_SLIDER_PANEL_BOTTOM_PADDING + Math.max(0, this.bottomInset)
      })
      .backgroundColor(uiReaderProgressBackgroundColor('#CC111827'))
      .backgroundEffect(uiReaderProgressBackgroundEffect())
      .borderRadius({ topLeft: uiRadius(24), topRight: uiRadius(24) })
      .clip(true)
      .zIndex(1)
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct ReaderImageActionsOverlay {
  onDismiss: () => void = () => {};
  onRefresh: () => void = () => {};
  onShare: () => void = () => {};
  onSaveToAlbum: (result: SaveButtonOnClickResult) => void = (_result: SaveButtonOnClickResult) => {};
  onSave: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      ReaderPopupBackdrop({
        onDismiss: this.onDismiss
      })
      .zIndex(0)

      ReaderImageActionDialog({
        onRefresh: this.onRefresh,
        onShare: this.onShare,
        onSaveToAlbum: this.onSaveToAlbum,
        onSave: this.onSave
      })
      .zIndex(1)
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct ReaderSettingsMenuOverlay {
  @Prop statusText: string = '';
  @Prop menuShowClock: boolean = true;
  @Prop menuShowProgress: boolean = true;
  @Prop menuShowBattery: boolean = true;
  @Prop progressText: string = '';
  @Prop batteryText: string = '';
  @Link menuReaderPreset: string;
  @Link menuReaderPresetSelected: boolean;
  @Link menuReaderPresetCustom: boolean;
  @Link menuReaderPresetEditName: string;
  @Link selectedTab: number;
  @Prop menuScreenRotation: string = 'Default';
  @Prop menuReadingDirection: string = 'Right to left';
  @Prop menuPageScaling: string = 'Fit screen';
  @Prop menuTheme: string = 'Light';
  @Prop menuReaderBackground: string = 'Deep gray';
  @Prop menuAdaptiveDualPage: boolean = false;
  @Prop menuCropWhiteBorders: boolean = false;
  @Prop menuImageSuperResolution: boolean = false;
  @Prop menuImageSuperResolutionEngine: string = 'Detail enhancer';
  @Prop menuSdrToHdrEnabled: boolean = false;
  @Prop menuMoireReduction: string = 'Off';
  @Prop menuImageAdjustmentEnabled: boolean = false;
  @Prop menuImageContrast: number = 0;
  @Prop menuImageClarity: number = 0;
  @Prop menuImageSharpening: number = 0;
  @Prop menuImageExposure: number = 0;
  @Prop menuImageBrightness: number = 0;
  @Prop menuImageHighlights: number = 0;
  @Prop menuImageShadows: number = 0;
  @Prop menuImageHue: number = 0;
  @Prop menuImageSaturation: number = 0;
  @Prop menuImageVibrance: number = 0;
  @Prop menuImageTemperature: number = 0;
  @Prop menuImageGrayscale: number = 0;
  @Prop menuStartPosition: string = 'Center';
  @Prop menuAutoTransferTime: string = '5s';
  @Prop menuKeepScreenOn: boolean = false;
  @Prop menuReadingFullscreen: boolean = true;
  @Prop menuVolumePage: boolean = false;
  @Prop menuReverseVolumePage: boolean = false;
  @Prop menuComicTranslation: boolean = false;
  @Prop menuAiTranslation: boolean = false;
  @Prop @Watch('onMenuCustomBrightnessChange') menuCustomBrightness: boolean = false;
  @Prop menuBrightnessLevel: string = '50%';
  @Prop @Watch('onMenuUltraDarkModeChange') menuUltraDarkMode: boolean = false;
  @Prop menuUltraDarkBrightness: string = '50%';
  @State customBrightnessVisible: boolean = false;
  @State ultraDarkVisible: boolean = false;
  @State presetDialogMode: string = '';
  @State presetPopupWidth: number = 0;
  @State presetPopupHeight: number = 0;
  @State presetEditorName: string = '';
  @State presetNameError: boolean = false;
  @Prop screenRotationOptions: string[] = [];
  @Prop readingDirectionOptions: string[] = [];
  @Prop pageScalingOptions: string[] = [];
  @Prop superResolutionEngineOptions: string[] = [];
  @Link readerPresetOptions: string[];
  onDismiss: () => void = () => {};
  onBack: () => void = () => {};
  onReaderPresetChange: (value: string) => void = (_value: string) => {};
  onCreateReaderPreset: (name: string) => void = (_name: string) => {};
  onSaveReaderPreset: () => void = () => {};
  onRenameReaderPreset: (name: string) => void = (_name: string) => {};
  onDeleteReaderPreset: () => void = () => {};
  onSelectedTabChange: (value: number) => void = (_value: number) => {};
  onScreenRotationChange: (value: string) => void = (_value: string) => {};
  onReadingDirectionChange: (value: string) => void = (_value: string) => {};
  onPageScalingChange: (value: string) => void = (_value: string) => {};
  onThemeChange: (value: string) => void = (_value: string) => {};
  onReaderBackgroundChange: (value: string) => void = (_value: string) => {};
  onAdaptiveDualPageChange: (value: boolean) => void = (_value: boolean) => {};
  onCropWhiteBordersChange: (value: boolean) => void = (_value: boolean) => {};
  onImageSuperResolutionChange: (value: boolean) => void = (_value: boolean) => {};
  onImageSuperResolutionEngineChange: (value: string) => void = (_value: string) => {};
  onSdrToHdrChange: (value: boolean) => void = (_value: boolean) => {};
  onMoireReductionChange: (value: string) => void = (_value: string) => {};
  onImageAdjustmentEnabledChange: (value: boolean) => void = (_value: boolean) => {};
  onImageContrastChange: (value: number) => void = (_value: number) => {};
  onImageClarityChange: (value: number) => void = (_value: number) => {};
  onImageSharpeningChange: (value: number) => void = (_value: number) => {};
  onImageExposureChange: (value: number) => void = (_value: number) => {};
  onImageBrightnessChange: (value: number) => void = (_value: number) => {};
  onImageHighlightsChange: (value: number) => void = (_value: number) => {};
  onImageShadowsChange: (value: number) => void = (_value: number) => {};
  onImageHueChange: (value: number) => void = (_value: number) => {};
  onImageSaturationChange: (value: number) => void = (_value: number) => {};
  onImageVibranceChange: (value: number) => void = (_value: number) => {};
  onImageTemperatureChange: (value: number) => void = (_value: number) => {};
  onImageGrayscaleChange: (value: number) => void = (_value: number) => {};
  onResetImageAdjustments: () => void = () => {};
  onStartPositionChange: (value: string) => void = (_value: string) => {};
  onAutoTransferTimeChange: (value: string) => void = (_value: string) => {};
  onKeepScreenOnChange: (value: boolean) => void = (_value: boolean) => {};
  onShowClockChange: (value: boolean) => void = (_value: boolean) => {};
  onShowProgressChange: (value: boolean) => void = (_value: boolean) => {};
  onShowBatteryChange: (value: boolean) => void = (_value: boolean) => {};
  onReadingFullscreenChange: (value: boolean) => void = (_value: boolean) => {};
  onVolumePageChange: (value: boolean) => void = (_value: boolean) => {};
  onReverseVolumePageChange: (value: boolean) => void = (_value: boolean) => {};
  onComicTranslationChange: (value: boolean) => void = (_value: boolean) => {};
  onAiTranslationChange: (value: boolean) => void = (_value: boolean) => {};
  onCustomBrightnessChange: (value: boolean) => void = (_value: boolean) => {};
  onBrightnessLevelChange: (value: string) => void = (_value: string) => {};
  onUltraDarkModeChange: (value: boolean) => void = (_value: boolean) => {};
  onUltraDarkBrightnessChange: (value: string) => void = (_value: string) => {};

  aboutToAppear(): void {
    this.customBrightnessVisible = this.menuCustomBrightness;
    this.ultraDarkVisible = this.menuUltraDarkMode;
  }

  onMenuCustomBrightnessChange(): void {
    this.customBrightnessVisible = this.menuCustomBrightness;
  }

  onMenuUltraDarkModeChange(): void {
    this.ultraDarkVisible = this.menuUltraDarkMode;
  }

  private openPresetEditor(mode: string): void {
    this.presetDialogMode = mode;
    this.presetEditorName = mode === 'rename' ? this.menuReaderPresetEditName : '';
    this.presetNameError = false;
  }

  private closePresetDialog(): void {
    this.presetDialogMode = '';
    this.presetNameError = false;
  }

  private confirmPresetEditor(): void {
    const name = this.presetEditorName.trim();
    if (name.length === 0) {
      this.presetNameError = true;
      return;
    }
    if (this.presetDialogMode === 'create') {
      this.onCreateReaderPreset(name);
    } else if (this.presetDialogMode === 'rename') {
      this.onRenameReaderPreset(name);
    }
    this.closePresetDialog();
  }

  @Builder
  private PresetActionButton(label: string, symbol: Resource, enabled: boolean, action: () => void) {
    Button({ type: ButtonType.Circle, stateEffect: enabled }) {
      Column({ space: 3 }) {
        SymbolGlyph(symbol)
          .fontSize(20)
          .fontColor([enabled ? themePrimaryText() : themeSecondaryText()])
        Text(uiText(label))
          .fontSize(13)
          .fontColor(enabled ? themePrimaryText() : themeSecondaryText())
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
    }
    .width(58)
    .height(58)
    .enabled(enabled)
    .backgroundColor(uiReaderOptionControlBackground())
    .systemMaterial(uiReaderOptionButtonMaterial())
    .border({ width: 1, color: uiButtonHighlightBorderColor() })
    .onClick(action)
  }

  @Builder
  private PresetActions() {
    Row() {
      this.PresetActionButton('New preset', $r('sys.symbol.plus'), true, () => {
        this.openPresetEditor('create');
      })
      this.PresetActionButton('Save preset', $r('sys.symbol.save'), true, () => {
        if (this.menuReaderPresetSelected) {
          this.onSaveReaderPreset();
        } else {
          this.openPresetEditor('create');
        }
      })
      this.PresetActionButton('Rename preset', $r('sys.symbol.square_and_pencil'), this.menuReaderPresetCustom, () => {
        this.openPresetEditor('rename');
      })
      this.PresetActionButton('Delete preset', $r('sys.symbol.trash'), this.menuReaderPresetCustom, () => {
        this.presetDialogMode = 'delete';
        this.presetNameError = false;
      })
    }
    .width('100%')
    .height(66)
    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
    .justifyContent(FlexAlign.SpaceAround)
  }

  @Builder
  private PresetDialog() {
    Stack({ alignContent: Alignment.Center }) {
      PopupScrim({
        showCutout: this.presetPopupWidth > 0 && this.presetPopupHeight > 0,
        cutoutWidth: this.presetPopupWidth,
        cutoutHeight: this.presetPopupHeight,
        cutoutRadius: uiRadius(12),
        scrimColor: '#99000000',
        onDismiss: () => {
          this.closePresetDialog();
        }
      })

      Column({ space: 14 }) {
        Row() {
          Text(uiText(this.presetDialogMode === 'create' ? 'New reading preset' :
            (this.presetDialogMode === 'rename' ? 'Rename reading preset' : 'Delete reading preset')))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(16)
              .fontColor([themePrimaryText()])
          }
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .systemMaterial(uiButtonMaterial())
          .border({ width: 1, color: uiButtonHighlightBorderColor() })
          .onClick(() => {
            this.closePresetDialog();
          })
        }
        .width('100%')

        if (this.presetDialogMode === 'delete') {
          Text(uiText('Delete this reading preset?'))
            .fontSize(14)
            .fontColor(themeSecondaryText())
            .width('100%')
        } else {
          Column({ space: 5 }) {
            TextInput({ text: this.presetEditorName, placeholder: uiText('Preset name') })
              .width('100%')
              .height(uiSearchFieldHeight())
              .fontSize(14)
              .fontColor(themePrimaryText())
              .placeholderColor(themeSecondaryText())
              .caretColor(themeAccentTextColor())
              .backgroundColor(uiMaterialBackground(themeSurfaceVariant()))
              .systemMaterial(uiSearchMaterial())
              .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
              .border(uiInputFieldBorder(this.presetNameError))
              .onChange((value: string) => {
                this.presetEditorName = value;
                this.presetNameError = false;
              })
            if (this.presetNameError) {
              Text(uiText('Preset name is required'))
                .fontSize(11)
                .fontColor(themeDangerText())
                .width('100%')
            }
          }
          .width('100%')
        }

        Row({ space: 10 }) {
          Button(uiText('Cancel'))
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontColor(themePrimaryText())
            .backgroundColor(Color.Transparent)
            .systemMaterial(uiButtonMaterial())
            .borderRadius(uiRadius(6))
            .border({ width: 1, color: uiButtonHighlightBorderColor() })
            .onClick(() => {
              this.closePresetDialog();
            })
          Button(uiText(this.presetDialogMode === 'delete' ? 'Delete' : 'Save'))
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontColor(this.presetDialogMode === 'delete' ? themeDangerText() : themeOnPrimaryText())
            .backgroundColor(uiMaterialLayerBackground(this.presetDialogMode === 'delete' ?
              themeDangerBackground() : themePrimaryColor()))
            .systemMaterial(uiTintedButtonMaterial(this.presetDialogMode === 'delete' ?
              themeDangerBackground() : themePrimaryColor()))
            .borderRadius(uiRadius(6))
            .border({ width: 1, color: uiButtonHighlightBorderColor() })
            .onClick(() => {
              if (this.presetDialogMode === 'delete') {
                this.onDeleteReaderPreset();
                this.closePresetDialog();
              } else {
                this.confirmPresetEditor();
              }
            })
        }
        .width('100%')
      }
      .width('68%')
      .constraintSize({ minWidth: 260, maxWidth: 340 })
      .padding(18)
      .backgroundColor(uiPopupEffectBackground(themeSurface()))
      .backgroundEffect(uiPopupBackgroundEffect())
      .borderRadius(uiRadius(12))
      .shadow({ radius: 18, color: '#66000000', offsetY: 8 })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.presetPopupWidth = Number.parseFloat(newArea.width.toString());
        this.presetPopupHeight = Number.parseFloat(newArea.height.toString());
      })
    }
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseInOut }))
    .zIndex(2)
  }

  private readerSettingsTabStyle(label: string): SubTabBarStyle {
    return SubTabBarStyle.of(label)
      .selectedMode(SelectedMode.INDICATOR)
      .indicator({
        color: themeAccentTextColor(),
        height: 2,
        width: 28,
        borderRadius: 1,
        marginTop: 5
      })
      .labelStyle({
        font: { size: 14, weight: FontWeight.Medium },
        selectedColor: themeAccentTextColor(),
        unselectedColor: themePrimaryText(),
        maxLines: 1,
        overflow: TextOverflow.Ellipsis
      })
      .padding({ left: 4, right: 4, top: 10, bottom: 8 });
  }

  @Builder
  private ReadingSettingsTab() {
    Scroll() {
      Column({ space: 0 }) {
        ReaderMenuSelect({
          label: uiText('Reading presets'),
          options: this.readerPresetOptions,
          value: this.menuReaderPreset,
          onChange: this.onReaderPresetChange
        })
        this.PresetActions()
        ReaderMenuDivider()
        ReaderMenuSelect({
          label: uiText('Reading direction'),
          options: this.readingDirectionOptions,
          value: this.menuReadingDirection,
          onChange: this.onReadingDirectionChange
        })
        ReaderMenuDivider()
        ReaderMenuSelect({
          label: uiText('Page scaling'),
          options: this.pageScalingOptions,
          value: this.menuPageScaling,
          onChange: this.onPageScalingChange
        })
        ReaderMenuDivider()
        ReaderMenuToggle({
          label: uiText('Adaptive dual page'),
          value: this.menuAdaptiveDualPage,
          onChange: this.onAdaptiveDualPageChange
        })
        ReaderMenuDivider()
        ReaderMenuToggle({
          label: uiText('Crop white and black borders'),
          value: this.menuCropWhiteBorders,
          onChange: this.onCropWhiteBordersChange
        })
        ReaderMenuDivider()
        ReaderMenuSelect({
          label: uiText('Start position'),
          options: ['Top left', 'Top right', 'Bottom left', 'Bottom right', 'Center'],
          value: this.menuStartPosition,
          onChange: this.onStartPositionChange
        })
      }
      .width('100%')
      .padding({ bottom: 8 })
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
  }

  @Builder
  private DisplaySettingsTab() {
    Scroll() {
      Column({ space: 0 }) {
        ReaderMenuSelect({
          label: uiText('Theme'),
          options: ['Light', 'Dark', 'Black'],
          value: this.menuTheme,
          onChange: this.onThemeChange
        })
        ReaderMenuDivider()
        ReaderMenuSelect({
          label: uiText('Reader background'),
          options: ['Black', 'White', 'Deep gray'],
          value: this.menuReaderBackground,
          onChange: this.onReaderBackgroundChange
        })
        ReaderMenuDivider()
        ReaderMenuSelect({
          label: uiText('Screen rotation'),
          options: this.screenRotationOptions,
          value: this.menuScreenRotation,
          onChange: this.onScreenRotationChange
        })
        ReaderMenuDivider()
        ReaderMenuToggle({
          label: uiText('Image super resolution'),
          value: this.menuImageSuperResolution,
          onChange: this.onImageSuperResolutionChange
        })
        if (this.menuImageSuperResolution && this.superResolutionEngineOptions.length > 1) {
          ReaderMenuDivider()
          ReaderMenuSelect({
            label: uiText('Super-resolution engine'),
            options: this.superResolutionEngineOptions,
            value: this.menuImageSuperResolutionEngine,
            onChange: this.onImageSuperResolutionEngineChange
          })
        }
        ReaderMenuDivider()
        ReaderMenuToggle({
          label: uiText('SDR to HDR'),
          value: this.menuSdrToHdrEnabled,
          onChange: this.onSdrToHdrChange
        })
        ReaderMenuDivider()
        ReaderMenuToggle({
          label: uiText('Reading fullscreen'),
          value: this.menuReadingFullscreen,
          onChange: this.onReadingFullscreenChange
        })
        ReaderMenuDivider()
        ReaderMenuToggle({
          label: uiText('Keep screen on'),
          value: this.menuKeepScreenOn,
          onChange: this.onKeepScreenOnChange
        })
        ReaderMenuDivider()
        ReaderMenuToggle({
          label: uiText('Custom brightness'),
          value: this.customBrightnessVisible,
          onChange: (value: boolean) => {
            this.customBrightnessVisible = value;
            this.onCustomBrightnessChange(value);
          }
        })
        if (this.customBrightnessVisible) {
          ReaderMenuDivider()
          ReaderMenuSlider({
            label: uiText('Screen lightness'),
            value: readerBrightnessSliderValue(this.menuBrightnessLevel),
            min: 0,
            max: 100,
            step: 1,
            valueText: (value: number) => {
              return readerBrightnessValue(value);
            },
            onChange: (value: number) => {
              this.onBrightnessLevelChange(readerBrightnessValue(value));
            }
          })
        }
        ReaderMenuDivider()
        ReaderMenuToggle({
          label: uiText('Ultra dark mode'),
          value: this.ultraDarkVisible,
          onChange: (value: boolean) => {
            this.ultraDarkVisible = value;
            this.onUltraDarkModeChange(value);
          }
        })
        if (this.ultraDarkVisible) {
          ReaderMenuDivider()
          ReaderMenuSlider({
            label: uiText('Ultra dark brightness'),
            value: readerUltraDarkSliderValue(this.menuUltraDarkBrightness),
            min: 1,
            max: 100,
            step: 1,
            valueText: (value: number) => {
              return readerUltraDarkValue(value);
            },
            onChange: (value: number) => {
              this.onUltraDarkBrightnessChange(readerUltraDarkValue(value));
            }
          })
        }
      }
      .width('100%')
      .padding({ bottom: 8 })
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
  }

  @Builder
  private ControlSettingsTab() {
    Scroll() {
      Column({ space: 0 }) {
        ReaderMenuSlider({
          label: uiText('Auto transfer time'),
          value: readerAutoTransferSliderValue(this.menuAutoTransferTime),
          min: 1,
          max: 20,
          step: 1,
          valueText: (value: number) => {
            return uiValue(readerAutoTransferValue(value));
          },
          onChange: (value: number) => {
            this.onAutoTransferTimeChange(readerAutoTransferValue(value));
          }
        })
        ReaderMenuDivider()
        ReaderMenuToggle({
          label: uiText('Volume page'),
          value: this.menuVolumePage,
          onChange: this.onVolumePageChange
        })
        if (this.menuVolumePage) {
          ReaderMenuDivider()
          ReaderMenuToggle({
            label: uiText('Reverse volume buttons'),
            value: this.menuReverseVolumePage,
            onChange: this.onReverseVolumePageChange
          })
        }
        ReaderMenuDivider()
        ReaderMenuToggle({
          label: uiText('Comic translation'),
          value: this.menuComicTranslation,
          onChange: this.onComicTranslationChange
        })
        ReaderMenuDivider()
        ReaderMenuToggle({
          label: uiText('AI translation'),
          value: this.menuAiTranslation,
          onChange: this.onAiTranslationChange
        })
        ReaderMenuDivider()
        ReaderMenuToggle({
          label: uiText('Show clock'),
          value: this.menuShowClock,
          onChange: this.onShowClockChange
        })
        ReaderMenuDivider()
        ReaderMenuToggle({
          label: uiText('Show progress'),
          value: this.menuShowProgress,
          onChange: this.onShowProgressChange
        })
        ReaderMenuDivider()
        ReaderMenuToggle({
          label: uiText('Show battery'),
          value: this.menuShowBattery,
          onChange: this.onShowBatteryChange
        })
      }
      .width('100%')
      .padding({ bottom: 8 })
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
  }

  @Builder
  private ImageAdjustmentSettingsTab() {
    Scroll() {
      Column({ space: 0 }) {
        ReaderMenuSelect({
          label: uiText('Moiré reduction'),
          options: ['Off', 'Auto', 'Low', 'Medium', 'High'],
          value: this.menuMoireReduction,
          onChange: this.onMoireReductionChange
        })
        ReaderMenuDivider()
        ReaderMenuToggle({
          label: uiText('Image adjustment'),
          value: this.menuImageAdjustmentEnabled,
          onChange: this.onImageAdjustmentEnabledChange
        })
        if (this.menuImageAdjustmentEnabled) {
          ReaderMenuDivider()
          ReaderMenuSlider({
            label: uiText('Exposure'), value: this.menuImageExposure, min: -100, max: 100, step: 1,
            valueText: exposureValueText, onChange: this.onImageExposureChange
          })
          ReaderMenuDivider()
          ReaderMenuSlider({
            label: uiText('Brightness'), value: this.menuImageBrightness, min: -100, max: 100, step: 1,
            valueText: adjustmentValueText, onChange: this.onImageBrightnessChange
          })
          ReaderMenuDivider()
          ReaderMenuSlider({
            label: uiText('Contrast'), value: this.menuImageContrast, min: -100, max: 100, step: 1,
            valueText: adjustmentValueText, onChange: this.onImageContrastChange
          })
          ReaderMenuDivider()
          ReaderMenuSlider({
            label: uiText('Highlights'), value: this.menuImageHighlights, min: -100, max: 100, step: 1,
            valueText: adjustmentValueText, onChange: this.onImageHighlightsChange
          })
          ReaderMenuDivider()
          ReaderMenuSlider({
            label: uiText('Shadows'), value: this.menuImageShadows, min: -100, max: 100, step: 1,
            valueText: adjustmentValueText, onChange: this.onImageShadowsChange
          })
          ReaderMenuDivider()
          ReaderMenuSlider({
            label: uiText('Clarity'), value: this.menuImageClarity, min: 0, max: 100, step: 1,
            valueText: adjustmentValueText, onChange: this.onImageClarityChange
          })
          ReaderMenuDivider()
          ReaderMenuSlider({
            label: uiText('Sharpening'), value: this.menuImageSharpening, min: 0, max: 100, step: 1,
            valueText: adjustmentValueText, onChange: this.onImageSharpeningChange
          })
          ReaderMenuDivider()
          ReaderMenuSlider({
            label: uiText('Saturation'), value: this.menuImageSaturation, min: -100, max: 100, step: 1,
            valueText: adjustmentValueText, onChange: this.onImageSaturationChange
          })
          ReaderMenuDivider()
          ReaderMenuSlider({
            label: uiText('Vibrance'), value: this.menuImageVibrance, min: -100, max: 100, step: 1,
            valueText: adjustmentValueText, onChange: this.onImageVibranceChange
          })
          ReaderMenuDivider()
          ReaderMenuSlider({
            label: uiText('Hue'), value: this.menuImageHue, min: -180, max: 180, step: 1,
            valueText: degreeValueText, onChange: this.onImageHueChange
          })
          ReaderMenuDivider()
          ReaderMenuSlider({
            label: uiText('Color temperature'), value: this.menuImageTemperature, min: -100, max: 100, step: 1,
            valueText: adjustmentValueText, onChange: this.onImageTemperatureChange
          })
          ReaderMenuDivider()
          ReaderMenuSlider({
            label: uiText('Grayscale'), value: this.menuImageGrayscale, min: 0, max: 100, step: 1,
            valueText: adjustmentValueText, onChange: this.onImageGrayscaleChange
          })
          ReaderMenuDivider()
          Button(uiText('Reset image adjustments'))
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontColor(themeAccentTextColor())
            .backgroundColor(uiReaderOptionControlBackground())
            .systemMaterial(uiReaderOptionButtonMaterial())
            .border({ width: 1, color: uiButtonHighlightBorderColor() })
            .onClick(this.onResetImageAdjustments)
        }
      }
      .width('100%')
      .padding({ bottom: 8 })
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      ReaderPopupBackdrop({
        // 蒙版延伸到半透明设置面板下方，避免明亮的阅读内容透过来淹没文字。
        onDismiss: this.onDismiss
      })
      .zIndex(0)

      Column() {
        Row() {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(22)
              .fontColor([themePrimaryText()])
          }
          .width(36)
          .height(36)
          .backgroundColor(uiReaderOptionControlBackground())
          .systemMaterial(uiReaderOptionButtonMaterial())
          .border({ width: 1, color: uiButtonHighlightBorderColor() })
          .onClick(() => {
            this.onBack();
          })

          if (this.menuShowClock) {
            Text(readerClockText())
              .fontSize(12)
              .fontColor(themePrimaryText())
              .margin({ left: 8 })
          }
          if (this.menuShowProgress) {
            Text(this.progressText)
              .fontSize(12)
              .fontColor(themePrimaryText())
              .margin({ left: 8 })
          }
          if (this.menuShowBattery) {
            Text(this.batteryText)
              .fontSize(12)
              .fontColor(themePrimaryText())
              .margin({ left: 8 })
          }
        }
        .width('100%')
        .height(48)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(Color.Transparent)

        Tabs({ barPosition: BarPosition.Start, index: this.selectedTab }) {
          TabContent() {
            this.ReadingSettingsTab()
          }
          .tabBar(this.readerSettingsTabStyle(uiText('Page layout')))

          TabContent() {
            this.DisplaySettingsTab()
          }
          .tabBar(this.readerSettingsTabStyle(uiText('Screen display')))

          TabContent() {
            this.ControlSettingsTab()
          }
          .tabBar(this.readerSettingsTabStyle(uiText('Reading aids')))

          TabContent() {
            this.ImageAdjustmentSettingsTab()
          }
          .tabBar(this.readerSettingsTabStyle(uiText('Image adjustment')))
        }
        .barMode(BarMode.Fixed)
        .barHeight(uiTabHeight() + 8)
        .barBackgroundColor(Color.Transparent)
        .barBackgroundBlurStyle(BlurStyle.NONE)
        .animationDuration(220)
        .divider({ strokeWidth: 0, color: Color.Transparent })
        .onChange((index: number) => {
          this.selectedTab = index;
          this.onSelectedTabChange(index);
        })
        .width('100%')
        .layoutWeight(1)
      }
      .width('92%')
      .constraintSize({ maxWidth: 520, maxHeight: 640 })
      .backgroundColor(uiPopupEffectBackground(themeSurface()))
      .backgroundEffect(uiReaderMenuBackgroundEffect())
      .borderRadius(uiRadius(20))
      .clip(true)
      .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
      .zIndex(1)
      if (this.presetDialogMode.length > 0) {
        this.PresetDialog()
      }
    }
    .width('100%')
    .height('100%')
  }
}
