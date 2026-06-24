import {
  readerClockText,
  uiStatusText,
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
  showProgress: boolean = true;
  showClock: boolean = true;
  showBattery: boolean = true;
  progressText: string = '';
  clockText: string = '';
  batteryText: string = '';
  top: number = 0;
  right: number = 12;

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
        Text(this.progressText)
          .fontSize(14)
          .fontColor(themeOnPrimaryText())
          .lineHeight(16)
          .maxLines(1)
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
      .fontColor('#FFFFFF')
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
      Text(this.text)
        .fontSize(14)
        .fontColor('#E5E7EB')
        .maxLines(1)
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
  onSaveToAlbum: () => void = () => {};
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
  statusText: string = '';
  menuShowClock: boolean = true;
  menuShowProgress: boolean = true;
  progressText: string = '';
  menuScreenRotation: string = 'Default';
  menuReadingDirection: string = 'Right to left';
  menuPageScaling: string = 'Fit screen';
  menuStartPosition: string = 'Top right';
  menuAutoTransferTime: string = '5s';
  menuKeepScreenOn: boolean = false;
  menuShowBattery: boolean = true;
  menuReadingFullscreen: boolean = true;
  menuVolumePage: boolean = false;
  menuCustomBrightness: boolean = false;
  menuBrightnessLevel: string = '50%';
  menuUltraDarkMode: boolean = false;
  menuUltraDarkBrightness: string = '50%';
  screenRotationOptions: string[] = [];
  pageScalingOptions: string[] = [];
  onDismiss: () => void = () => {};
  onBack: () => void = () => {};
  onScreenRotationChange: (value: string) => void = (_value: string) => {};
  onReadingDirectionChange: (value: string) => void = (_value: string) => {};
  onPageScalingChange: (value: string) => void = (_value: string) => {};
  onStartPositionChange: (value: string) => void = (_value: string) => {};
  onAutoTransferTimeChange: (value: string) => void = (_value: string) => {};
  onKeepScreenOnChange: (value: boolean) => void = (_value: boolean) => {};
  onShowClockChange: (value: boolean) => void = (_value: boolean) => {};
  onShowProgressChange: (value: boolean) => void = (_value: boolean) => {};
  onShowBatteryChange: (value: boolean) => void = (_value: boolean) => {};
  onReadingFullscreenChange: (value: boolean) => void = (_value: boolean) => {};
  onVolumePageChange: (value: boolean) => void = (_value: boolean) => {};
  onCustomBrightnessChange: (value: boolean) => void = (_value: boolean) => {};
  onBrightnessLevelChange: (value: string) => void = (_value: string) => {};
  onUltraDarkModeChange: (value: boolean) => void = (_value: boolean) => {};
  onUltraDarkBrightnessChange: (value: string) => void = (_value: string) => {};

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

          Text(uiStatusText(this.statusText))
            .fontSize(12)
            .fontColor('#E5E7EB')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 10 })
            .layoutWeight(1)
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
        }
        .width('100%')
        .height(48)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(themeScrimColor())

        Scroll() {
          Column({ space: 0 }) {
            ReaderMenuSelect({
              label: uiText('Screen rotation'),
              options: this.screenRotationOptions,
              value: this.menuScreenRotation,
              onChange: this.onScreenRotationChange
            })
            ReaderMenuDivider()

            ReaderMenuSelect({
              label: uiText('Reading direction'),
              options: ['Left to right', 'Right to left', 'Top to bottom'],
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

            ReaderMenuSelect({
              label: uiText('Start position'),
              options: ['Top left', 'Top right', 'Bottom left', 'Bottom right', 'Center'],
              value: this.menuStartPosition,
              onChange: this.onStartPositionChange
            })
            ReaderMenuDivider()

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
              label: uiText('Keep screen on'),
              value: this.menuKeepScreenOn,
              onChange: this.onKeepScreenOnChange
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
            ReaderMenuDivider()

            ReaderMenuToggle({
              label: uiText('Reading fullscreen'),
              value: this.menuReadingFullscreen,
              onChange: this.onReadingFullscreenChange
            })
            ReaderMenuDivider()

            ReaderMenuToggle({
              label: uiText('Volume page'),
              value: this.menuVolumePage,
              onChange: this.onVolumePageChange
            })
            ReaderMenuDivider()

            ReaderMenuToggle({
              label: uiText('Custom brightness'),
              value: this.menuCustomBrightness,
              onChange: this.onCustomBrightnessChange
            })

            if (this.menuCustomBrightness) {
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
              value: this.menuUltraDarkMode,
              onChange: this.onUltraDarkModeChange
            })

            if (this.menuUltraDarkMode) {
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
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)
        .width('100%')
        .layoutWeight(1)
      }
      .width('92%')
      .constraintSize({ maxWidth: 520, maxHeight: '76%' })
      .backgroundColor('#EE111827')
      .borderRadius(12)
      .clip(true)
      .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
      .zIndex(1)
    }
    .width('100%')
    .height('100%')
  }
}
