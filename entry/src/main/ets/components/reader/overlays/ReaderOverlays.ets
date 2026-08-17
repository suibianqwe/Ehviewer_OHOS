import {
  readerClockText,
  uiText,
  uiValue
} from '../../../shared/EhShared';
import { themeOnPrimaryText, themeScrimColor } from '../../../shared/EhTheme';
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
    .borderRadius(10)
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
      .fontColor(Color.White)
      .lineHeight(40)
      .textAlign(TextAlign.Center)
      .textVerticalAlign(TextVerticalAlign.CENTER)
      .width(40)
      .height(40)
      .backgroundColor('#1F2937')
      .borderRadius(20)
      .borderWidth(1)
      .borderColor('#3F4756')
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
        fontColor: '#E5E7EB',
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
        .fontColor([Color.White])
    }
    .width(50)
    .height(50)
    .enabled(this.autoTransferEnabled)
    .backgroundColor(this.autoTransferEnabled ? '#334155' : '#1F2937')
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
    .height(50)
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
    // Slider bar (32) + generous top/bottom padding (10 each) + bottom safe-area inset.
    return 62 + Math.max(0, this.bottomInset);
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
      .padding({ left: 10, right: 10, top: 10, bottom: 20 + Math.max(0, this.bottomInset) })
      .backgroundColor('#CC111827')
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
  @Prop menuScreenRotation: string = 'Default';
  @Prop menuReadingDirection: string = 'Right to left';
  @Prop menuPageScaling: string = 'Fit screen';
  @Prop menuAdaptiveDualPage: boolean = false;
  @Prop menuCropWhiteBorders: boolean = false;
  @Prop menuImageSuperResolution: boolean = false;
  @Prop menuImageSuperResolutionEngine: string = 'Detail enhancer';
  @Prop menuSdrToHdrEnabled: boolean = false;
  @Prop menuStartPosition: string = 'Top right';
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
  @State selectedTab: number = 0;
  @State presetDialogMode: string = '';
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
  onScreenRotationChange: (value: string) => void = (_value: string) => {};
  onReadingDirectionChange: (value: string) => void = (_value: string) => {};
  onPageScalingChange: (value: string) => void = (_value: string) => {};
  onAdaptiveDualPageChange: (value: boolean) => void = (_value: boolean) => {};
  onCropWhiteBordersChange: (value: boolean) => void = (_value: boolean) => {};
  onImageSuperResolutionChange: (value: boolean) => void = (_value: boolean) => {};
  onImageSuperResolutionEngineChange: (value: string) => void = (_value: string) => {};
  onSdrToHdrChange: (value: boolean) => void = (_value: boolean) => {};
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
    Button({ type: ButtonType.Normal, stateEffect: enabled }) {
      Column({ space: 3 }) {
        SymbolGlyph(symbol)
          .fontSize(17)
          .fontColor([enabled ? '#E5E7EB' : '#64748B'])
        Text(uiText(label))
          .fontSize(11)
          .fontColor(enabled ? '#CBD5E1' : '#64748B')
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1)
    .height(48)
    .enabled(enabled)
    .backgroundColor(Color.Transparent)
    .borderRadius(6)
    .onClick(action)
  }

  @Builder
  private PresetActions() {
    Row({ space: 2 }) {
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
    .height(52)
    .padding({ left: 10, right: 10, top: 2, bottom: 2 })
  }

  @Builder
  private PresetDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Stack() {}
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick(() => {
          this.closePresetDialog();
        })

      Column({ space: 14 }) {
        Row() {
          Text(uiText(this.presetDialogMode === 'create' ? 'New reading preset' :
            (this.presetDialogMode === 'rename' ? 'Rename reading preset' : 'Delete reading preset')))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor('#F8FAFC')
            .layoutWeight(1)
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(16)
              .fontColor([Color.White])
          }
          .width(32)
          .height(32)
          .backgroundColor('#334155')
          .onClick(() => {
            this.closePresetDialog();
          })
        }
        .width('100%')

        if (this.presetDialogMode === 'delete') {
          Text(uiText('Delete this reading preset?'))
            .fontSize(14)
            .fontColor('#CBD5E1')
            .width('100%')
        } else {
          Column({ space: 5 }) {
            TextInput({ text: this.presetEditorName, placeholder: uiText('Preset name') })
              .width('100%')
              .height(42)
              .fontSize(14)
              .fontColor('#F8FAFC')
              .placeholderColor('#94A3B8')
              .caretColor('#38BDF8')
              .backgroundColor('#1E293B')
              .borderRadius(6)
              .border({ width: this.presetNameError ? 1 : 0, color: '#F87171' })
              .onChange((value: string) => {
                this.presetEditorName = value;
                this.presetNameError = false;
              })
            if (this.presetNameError) {
              Text(uiText('Preset name is required'))
                .fontSize(11)
                .fontColor('#FCA5A5')
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
            .fontColor('#CBD5E1')
            .backgroundColor('#334155')
            .borderRadius(6)
            .onClick(() => {
              this.closePresetDialog();
            })
          Button(uiText(this.presetDialogMode === 'delete' ? 'Delete' : 'Save'))
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor(this.presetDialogMode === 'delete' ? '#B91C1C' : '#0284C7')
            .borderRadius(6)
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
      .backgroundColor('#F7111827')
      .borderRadius(12)
      .shadow({ radius: 18, color: '#66000000', offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseInOut }))
    .zIndex(2)
  }

  @Builder
  private ReaderSettingsTabBar(label: string, index: number) {
    Column({ space: 3 }) {
      Text(label)
        .fontSize(13)
        .fontWeight(this.selectedTab === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selectedTab === index ? '#FFFFFF' : '#94A3B8')
        .maxLines(1)
      Row()
        .width(this.selectedTab === index ? 28 : 0)
        .height(2)
        .borderRadius(1)
        .backgroundColor('#38BDF8')
    }
    .width('100%')
    .height(40)
    .justifyContent(FlexAlign.Center)
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

  build() {
    Stack({ alignContent: Alignment.Center }) {
      ReaderPopupBackdrop({
        onDismiss: this.onDismiss
      })
      .zIndex(0)

      Column() {
        Row() {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(20)
              .fontColor([Color.White])
          }
          .width(36)
          .height(36)
          .backgroundColor('#334155')
          .onClick(() => {
            this.onBack();
          })

          if (this.menuShowClock) {
            Text(readerClockText())
              .fontSize(12)
              .fontColor('#E5E7EB')
              .margin({ left: 8 })
          }
          if (this.menuShowProgress) {
            Text(this.progressText)
              .fontSize(12)
              .fontColor('#E5E7EB')
              .margin({ left: 8 })
          }
          if (this.menuShowBattery) {
            Text(this.batteryText)
              .fontSize(12)
              .fontColor('#E5E7EB')
              .margin({ left: 8 })
          }
        }
        .width('100%')
        .height(48)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(themeScrimColor())

        Tabs({ barPosition: BarPosition.Start, index: this.selectedTab }) {
          TabContent() {
            this.ReadingSettingsTab()
          }
          .tabBar(this.ReaderSettingsTabBar(uiText('Page layout'), 0))

          TabContent() {
            this.DisplaySettingsTab()
          }
          .tabBar(this.ReaderSettingsTabBar(uiText('Screen display'), 1))

          TabContent() {
            this.ControlSettingsTab()
          }
          .tabBar(this.ReaderSettingsTabBar(uiText('Reading aids'), 2))
        }
        .barMode(BarMode.Fixed)
        .barHeight(40)
        .animationDuration(180)
        .divider({ strokeWidth: 1, color: '#334155' })
        .onChange((index: number) => {
          this.selectedTab = index;
        })
        .width('100%')
        .layoutWeight(1)
      }
      .width('70%')
      .constraintSize({ maxWidth: 400, maxHeight: '70%' })
      .backgroundColor('#EE111827')
      .borderRadius(12)
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
