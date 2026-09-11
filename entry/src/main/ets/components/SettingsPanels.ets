import { webview } from '@kit.ArkWeb';
import {
  SettingEntry,
} from '../services/EhSettingsStore';
import {
  MAIN_CONTENT_WIDTH_VP_KEY,
} from '../services/EhWindowImmersive';
import {
  STATUS_BAR_HEIGHT_KEY,
} from '../shared/EhShared';
import {
  themeDividerColor,
  themeFieldBackground,
  themeOnPrimaryText,
  themePageBackground,
  themeAccentTextColor,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSelectedBackground,
  themeSurface,
  themeSurfaceVariant,
  themeTertiaryText,
} from '../shared/EhTheme';
import { PopupScrim } from './PopupScrim';
import {
  uiAdaptiveToolbarHeight,
  uiButtonMaterial,
  uiTransparentButtonBackgroundEffect,
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow,
  uiListItemBackground,
  uiListItemSelectedBackground,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiButtonHighlightBorderColor,
  uiRadius,
  uiSearchFieldHeight,
  uiSelectDialogMaterial,
  uiSelectPopupBackground,
  uiSwitchHeight,
  uiSwitchWidth,
  uiPageHorizontalPadding,
} from '../shared/EhUiStyle';
import { SettingsHeaderItem, SettingsRowItem, SettingsPanel, SETTINGS_HEADERS, uiText, uiValue, settingsPanelTitle, settingsRowsForPanel } from '../shared/EhShared';
import { AppSubToolbar, AppToolbar } from './NavigationComponents';
import {
  EH_WEB_COMPATIBILITY_SCRIPTS,
  loadEhWebUrlWithAndroidCompatibility,
} from '../services/EhWebRuntime';
import {
  settingsRowActionText,
  isSecretSettingKey,
  isDirectTranslationApiKey,
  settingsSliderNumberValue,
  settingsSliderMin,
  settingsSliderMax,
  settingsSliderTextValue,
  settingsSliderDisplayText,
  settingsRowRenderKey,
} from './SettingsSupport';




@Component
export struct SettingsHomePanel {
  onMenu: () => void = () => {};
  onOpen: (panel: SettingsPanel) => void = () => {};
  initialScrollOffset: number = 0;
  onScrollPositionChange: (offset: number) => void = (_offset: number) => {};
  @StorageProp(MAIN_CONTENT_WIDTH_VP_KEY) contentWidth: number = 360;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  private settingsScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const offset = Math.max(0, this.initialScrollOffset);
    if (offset > 0) {
      setTimeout(() => {
        this.settingsScroller.scrollTo({ xOffset: 0, yOffset: offset });
      }, 0);
    }
  }

  private totalBarHeight(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx) + uiAdaptiveToolbarHeight(this.contentWidth);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      List({ space: 0, scroller: this.settingsScroller }) {
        ListItem() {
          Row()
            .height(this.totalBarHeight() + 12)
        }
        ForEach(SETTINGS_HEADERS, (item: SettingsHeaderItem, index: number) => {
          ListItem() {
            SettingsHeaderRow({
              item: item,
              firstInGroup: index === 0,
              lastInGroup: index === SETTINGS_HEADERS.length - 1,
              onTap: () => {
                this.onOpen(item.panel);
              }
            })
          }
        }, (item: SettingsHeaderItem) => item.panel)
        ListItem() {
          Row()
            .height(12)
        }
      }
      .width('100%')
      .height('100%')
      .cachedCount(3)
      .padding({ left: uiPageHorizontalPadding(this.contentWidth),
        right: uiPageHorizontalPadding(this.contentWidth) })
      .edgeEffect(EdgeEffect.None)
      .onDidScroll((_scrollOffset: number, _scrollState: ScrollState) => {
        this.onScrollPositionChange(Math.max(0, this.settingsScroller.currentOffset().yOffset));
      })
      .onScrollStop(() => {
        this.onScrollPositionChange(Math.max(0, this.settingsScroller.currentOffset().yOffset));
      })

      AppToolbar({
        title: 'Settings',
        subtitle: '',
        translateY: 0,
        onMenu: this.onMenu
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}

@Component
export struct SettingsAccountWebPanel {
  title: string = '';
  url: string = '';
  onBack: () => void = () => {};
  onPageEnd: (url: string) => void = (_url: string) => {};
  private webViewController: webview.WebviewController = new webview.WebviewController();

  build() {
    Column() {
      SettingsSubToolbar({
        title: uiText(this.title),
        onBack: this.onBack
      })
      Web({ src: '', controller: this.webViewController, incognitoMode: false })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .javaScriptOnDocumentStart(EH_WEB_COMPATIBILITY_SCRIPTS)
        .backgroundColor(Color.Transparent)
        .onControllerAttached(() => {
          loadEhWebUrlWithAndroidCompatibility(this.webViewController, this.url);
        })
        .onPageEnd((event: OnPageEndEvent) => {
          this.onPageEnd(event.url);
        })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}

@Component
export struct SettingsSubToolbar {
  title: string = '';
  showAction: boolean = false;
  actionIcon: Resource = $r('sys.symbol.share');
  onBack: () => void = () => {};
  onAction: () => void = () => {};

  build() {
    AppSubToolbar({
      title: this.title,
      showAction: this.showAction,
      actionIcon: this.actionIcon,
      translateY: 0,
      showBottomFade: false,
      onBack: this.onBack,
      onAction: this.onAction
    })
  }
}

@Component
export struct SettingsHeaderRow {
  item: SettingsHeaderItem = { panel: SettingsPanel.Eh, title: '', icon: '', summary: '' };
  firstInGroup: boolean = false;
  lastInGroup: boolean = false;
  onTap: () => void = () => {};

  build() {
    Column() {
      Row() {
        SettingsTextBlock({ title: uiText(this.item.title), summary: uiText(this.item.summary) })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([themeTertiaryText()])
      }
      .width('100%')
      .padding(14)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.onTap();
      })
      if (!this.lastInGroup) {
        Divider()
          .color(themeDividerColor())
          .strokeWidth(0.5)
          .margin({ left: 14, right: 14 })
      }
    }
    .width('100%')
    .backgroundColor(uiListItemBackground(themeSurface()))
    .borderRadius({
      topLeft: this.firstInGroup ? uiRadius(16) : 0,
      topRight: this.firstInGroup ? uiRadius(16) : 0,
      bottomLeft: this.lastInGroup ? uiRadius(16) : 0,
      bottomRight: this.lastInGroup ? uiRadius(16) : 0
    })
    .clip(true)
  }
}

@Component
export struct SettingsTextBlock {
  title: string = '';
  summary: string = '';
  isEnabled: boolean = true;

  build() {
    Column() {
      Text(this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isEnabled ? themePrimaryText() : themeTertiaryText())
      Text(this.summary)
        .fontSize(12)
        .fontColor(themeSecondaryText())
        .lineHeight(18)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct SettingsDetailPanel {
  @Prop panel: SettingsPanel = SettingsPanel.Eh;
  @Prop signedIn: boolean = false;
  @Prop themeName: string = 'Light';
  @Prop renderRevision: number = 0;
  @Prop settingEntries: SettingEntry[] = [];
  onBack: () => void = () => {};
  onOpenSession: () => void = () => {};
  onSignOut: () => void = () => {};
  onCycleSetting: (row: SettingsRowItem) => void = () => {};
  onSetSetting: (key: string, value: string) => void = () => {};
  onTextDraftChange: (key: string, value: string) => void = () => {};
  initialScrollOffset: number = 0;
  onScrollPositionChange: (offset: number) => void = (_offset: number) => {};
  @StorageProp(MAIN_CONTENT_WIDTH_VP_KEY) contentWidth: number = 360;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  private settingsScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const offset = Math.max(0, this.initialScrollOffset);
    if (offset > 0) {
      setTimeout(() => {
        this.settingsScroller.scrollTo({ xOffset: 0, yOffset: offset });
      }, 0);
    }
  }

  private totalBarHeight(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx) + uiAdaptiveToolbarHeight(this.contentWidth);
  }

  private settingsRows(): SettingsRowItem[] {
    return settingsRowsForPanel(this.panel, this.themeName, this.settingEntries);
  }

  private isFirstSettingsRow(index: number): boolean {
    const rows = this.settingsRows();
    return index === 0 || rows[index - 1].type === 'section';
  }

  private isLastSettingsRow(index: number): boolean {
    const rows = this.settingsRows();
    return index === rows.length - 1 || rows[index + 1].type === 'section';
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      List({ space: 0, scroller: this.settingsScroller }) {
        ListItem() {
          Row()
            .height(this.totalBarHeight() + 12)
        }
        if (this.panel === SettingsPanel.Eh) {
          ListItem() {
            SettingsActionRow({
              title: this.signedIn ? uiText('Account session') : uiText('Sign in'),
              summary: this.signedIn ? uiText('Cookie session is available. Open to replace or inspect cookies.') :
                uiText('Open password, WebView or Cookie sign-in and manage the current session.'),
              value: this.signedIn ? uiText('Signed in') : uiText('Tourist'),
              navigation: true,
              firstInGroup: true,
              lastInGroup: false,
              onTap: this.onOpenSession
            })
          }
          .reuseId('settings-session-action')
          ListItem() {
            SettingsActionRow({
              title: uiText('Sign out'),
              summary: uiText('Clear the persisted identity cookies'),
              value: this.signedIn ? uiText('Available') : uiText('No session'),
              isEnabled: this.signedIn,
              firstInGroup: false,
              lastInGroup: false,
              onTap: this.onSignOut
            })
          }
          .reuseId('settings-signout-action')
          ForEach(this.settingsRows(), (row: SettingsRowItem, index: number) => {
            ListItem() {
              SettingsStaticRow({
                row: row,
                renderRevision: this.renderRevision,
                firstInGroup: false,
                lastInGroup: this.isLastSettingsRow(index),
                onTextChange: (key: string, value: string) => {
                  this.onSetSetting(key, value);
                },
                onTextDraftChange: this.onTextDraftChange,
                onSwitchChange: (key: string, isOn: boolean) => {
                  this.onSetSetting(key, isOn ? 'On' : 'Off');
                },
                onOptionSelect: (key: string, value: string) => {
                  this.onSetSetting(key, value);
                },
                onTap: () => {
                  this.onCycleSetting(row);
                }
              })
            }
            .reuseId('settings-static-row')
          }, (row: SettingsRowItem) => settingsRowRenderKey(row))
        } else {
          ForEach(this.settingsRows(), (row: SettingsRowItem, index: number) => {
            ListItem() {
              SettingsStaticRow({
                row: row,
                renderRevision: this.renderRevision,
                firstInGroup: this.isFirstSettingsRow(index),
                lastInGroup: this.isLastSettingsRow(index),
                onTextChange: (key: string, value: string) => {
                  this.onSetSetting(key, value);
                },
                onTextDraftChange: this.onTextDraftChange,
                onSwitchChange: (key: string, isOn: boolean) => {
                  this.onSetSetting(key, isOn ? 'On' : 'Off');
                },
                onOptionSelect: (key: string, value: string) => {
                  this.onSetSetting(key, value);
                },
                onTap: () => {
                  this.onCycleSetting(row);
                }
              })
            }
            .reuseId('settings-static-row')
          }, (row: SettingsRowItem) => settingsRowRenderKey(row))
        }
        ListItem() {
          Row()
            .height(12)
        }
      }
      .edgeEffect(EdgeEffect.None)
      .onDidScroll((_scrollOffset: number, _scrollState: ScrollState) => {
        this.onScrollPositionChange(Math.max(0, this.settingsScroller.currentOffset().yOffset));
      })
      .onScrollStop(() => {
        this.onScrollPositionChange(Math.max(0, this.settingsScroller.currentOffset().yOffset));
      })
      .width('100%')
      .height('100%')
      .cachedCount(4)
      .padding({ left: uiPageHorizontalPadding(this.contentWidth),
        right: uiPageHorizontalPadding(this.contentWidth) })

      AppSubToolbar({
        title: uiText(settingsPanelTitle(this.panel)),
        translateY: 0,
        onBack: this.onBack
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}


@Component
export struct SettingsOptionPanel {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop value: string = '';
  @Prop options: string[] = [];
  @Prop optionDescriptions: string[] = [];
  @Prop allowCustomInput: boolean = false;
  @State customValue: string = '';
  @State viewportHeight: number = 640;
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;
  onBack: () => void = () => {};
  onSelect: (value: string) => void = () => {};

  private estimatedOptionRowHeight(index: number): number {
    if (index < this.optionDescriptions.length && this.optionDescriptions[index].length > 0) {
      return 64;
    }
    return 52;
  }

  private optionListContentHeight(): number {
    if (this.options.length === 0) {
      return 64;
    }
    let height = 0;
    for (let index = 0; index < this.options.length; index++) {
      height += this.estimatedOptionRowHeight(index);
    }
    return height;
  }

  private panelChromeHeight(): number {
    let height = 66;
    if (this.summary.length > 0) {
      height += this.summary.length > 40 ? 56 : 37;
    }
    if (this.allowCustomInput) {
      height += 52;
    }
    return height;
  }

  private availablePanelHeight(): number {
    const statusBarHeight = this.getUIContext().px2vp(this.statusBarHeightPx);
    const verticalMargin = Math.max(16, statusBarHeight + 8);
    return Math.max(96, this.viewportHeight - verticalMargin * 2);
  }

  private panelHeight(): number {
    return Math.min(this.availablePanelHeight(), this.panelChromeHeight() + this.optionListContentHeight());
  }

  private optionListHeight(): number {
    return Math.max(64, this.panelHeight() - this.panelChromeHeight());
  }

  private optionListNeedsScroll(): boolean {
    return this.optionListContentHeight() > this.optionListHeight() + 0.5;
  }

  @Builder
  private optionRow(option: string, index: number) {
    Row() {
      Column() {
        Text(uiValue(option))
          .fontSize(15)
          .fontWeight(option === this.value ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(option === this.value ? themeAccentTextColor() : themePrimaryText())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (index < this.optionDescriptions.length && this.optionDescriptions[index].length > 0) {
          Text(uiText(this.optionDescriptions[index]))
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 3 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (option === this.value) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([themeAccentTextColor()])
          .margin({ left: 12 })
      }
    }
    .width('100%')
    .height(this.estimatedOptionRowHeight(index))
    .padding({ left: 14, right: 14 })
    .backgroundColor(option === this.value ? uiListItemSelectedBackground(themeSelectedBackground()) :
      Color.Transparent)
    .border({ width: { bottom: index === this.options.length - 1 ? 0 : 0.5 },
      color: themeDividerColor() })
    .onClick(() => {
      this.onSelect(option);
    })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      PopupScrim({
        showCutout: this.popupWidth > 0 && this.popupHeight > 0,
        cutoutWidth: this.popupWidth,
        cutoutHeight: this.popupHeight,
        cutoutRadius: uiDialogSurfaceRadius(),
        onDismiss: this.onBack
      })

      Column() {
        Row() {
          Text(uiText(this.title))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([uiMaterialForegroundColor(themePrimaryText())])
          }
          .width(40)
          .height(40)
          .backgroundColor(uiMaterialBackground(themeSurfaceVariant()))
          .border({ width: 1, color: uiButtonHighlightBorderColor() })
          .backgroundEffect(uiTransparentButtonBackgroundEffect())
          .systemMaterial(uiButtonMaterial())
          .onClick(this.onBack)
        }
        .width('100%')

        if (this.summary.length > 0) {
          Text(uiText(this.summary))
            .fontSize(13)
            .fontColor(themeSecondaryText())
            .lineHeight(19)
            .width('100%')
            .margin({ top: 6, bottom: 12 })
        }

        Column() {
          if (this.optionListNeedsScroll()) {
            List({ space: 0 }) {
              ForEach(this.options, (option: string, index: number) => {
                ListItem() {
                  this.optionRow(option, index)
                }
                .reuseId('settings-option-row')
              }, (option: string) => option)
            }
            .width('100%')
            .height('100%')
            .cachedCount(4)
            .scrollBar(BarState.Auto)
          } else {
            ForEach(this.options, (option: string, index: number) => {
              this.optionRow(option, index)
            }, (option: string) => option)
          }
        }
        .width('100%')
        .height(this.optionListHeight())
        .backgroundColor(Color.Transparent)
        .borderRadius(uiRadius(16))
        .clip(true)

        if (this.allowCustomInput) {
          Row({ space: 8 }) {
            TextInput({ text: this.customValue, placeholder: uiText('Enter a model name') })
              .height(uiSearchFieldHeight())
              .layoutWeight(1)
              .fontSize(14)
              .fontColor(themePrimaryText())
              .backgroundColor(themeFieldBackground())
              .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
              .onChange((value: string) => {
                this.customValue = value;
              })
              .onSubmit(() => {
                const value = this.customValue.trim();
                if (value.length > 0) {
                  this.onSelect(value);
                }
              })
            Button(uiText('Use custom value'))
              .height(40)
              .fontSize(13)
              .fontColor(uiMaterialForegroundColor(themeOnPrimaryText()))
              .backgroundColor(uiMaterialBackground(themePrimaryColor()))
              .border({ width: 1, color: uiButtonHighlightBorderColor() })
              .backgroundEffect(uiTransparentButtonBackgroundEffect())
              .systemMaterial(uiButtonMaterial())
              .onClick(() => {
                const value = this.customValue.trim();
                if (value.length > 0) {
                  this.onSelect(value);
                }
              })
          }
          .width('100%')
          .margin({ top: 12 })
        }
      }
      .width('86%')
      .height(this.panelHeight())
      .constraintSize({ maxWidth: 420 })
      .padding({ left: 18, right: 18, top: 18, bottom: 8 })
      .backgroundColor(uiMaterialBackground(uiSelectPopupBackground(themeSurface())))
      .shadow(uiDialogSurfaceShadow())
      .clip(true)
      .borderRadius(uiDialogSurfaceRadius())
      .backgroundBlurStyle(uiDialogBlurStyle(), uiDialogBlurOptions())
      .systemMaterial(uiSelectDialogMaterial())
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.popupWidth = Number.parseFloat(newArea.width.toString());
        this.popupHeight = Number.parseFloat(newArea.height.toString());
      })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const height = newArea.height as number;
      if (height > 0 && !Number.isNaN(height) && Math.abs(this.viewportHeight - height) >= 1) {
        this.viewportHeight = height;
      }
    })
  }
}

@Component
export struct SettingsActionRow {
  title: string = '';
  summary: string = '';
  value: string = '';
  isEnabled: boolean = true;
  navigation: boolean = false;
  firstInGroup: boolean = false;
  lastInGroup: boolean = false;
  onTap: () => void = () => {};

  build() {
    Row() {
      SettingsTextBlock({
        title: this.title,
        summary: this.summary,
        isEnabled: this.isEnabled
      })
      .layoutWeight(1)
      if (this.navigation) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([themeTertiaryText()])
          .margin({ left: 12 })
      } else {
        Text(this.value)
          .fontSize(13)
          .fontColor(this.isEnabled ? themeSecondaryText() : themeTertiaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 12 })
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(uiListItemBackground(themeSurface()))
    .border({ width: { bottom: this.lastInGroup ? 0 : 0.5 }, color: themeDividerColor() })
    .borderRadius({
      topLeft: this.firstInGroup ? uiRadius(16) : 0,
      topRight: this.firstInGroup ? uiRadius(16) : 0,
      bottomLeft: this.lastInGroup ? uiRadius(16) : 0,
      bottomRight: this.lastInGroup ? uiRadius(16) : 0
    })
    .onClick(() => {
      if (this.isEnabled) {
        this.onTap();
      }
    })
  }
}

@Component
export struct SettingsStaticRow {
  row: SettingsRowItem = { title: '', summary: '', value: '', type: '' };
  @Prop renderRevision: number = 0;
  @State inputValue: string = '';
  firstInGroup: boolean = false;
  lastInGroup: boolean = false;
  onTap: () => void = () => {};
  onTextChange: (key: string, value: string) => void = () => {};
  onTextDraftChange: (key: string, value: string) => void = () => {};
  onSwitchChange: (key: string, isOn: boolean) => void = () => {};
  onOptionSelect: (key: string, value: string) => void = () => {};
  private committedInputValue: string = '';

  aboutToAppear(): void {
    this.inputValue = this.row.value;
    this.committedInputValue = this.row.value;
  }

  private commitInputValue(): void {
    if (this.row.key === undefined) {
      return;
    }
    const value = isSecretSettingKey(this.row.key) ? this.inputValue : this.inputValue.trim();
    if (value === this.committedInputValue) {
      return;
    }
    this.committedInputValue = value;
    this.onTextChange(this.row.key, value);
  }

  build() {
    Column() {
      Row() {
        SettingsTextBlock({
          title: uiText(this.row.title),
          summary: uiText(this.row.summary)
        })
        .layoutWeight(1)
        if (this.row.type === 'input') {
          TextInput({ text: this.inputValue, placeholder: uiText(this.row.summary) })
            .width(150)
            .height(uiSearchFieldHeight())
            .type(isSecretSettingKey(this.row.key) ? InputType.Password : InputType.Normal)
            .fontSize(13)
            .fontColor(themePrimaryText())
            .placeholderColor(themeSecondaryText())
            .backgroundColor(themeFieldBackground())
            .margin({ left: 12 })
            .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
            .onChange((value: string) => {
              this.inputValue = value;
              if (this.row.key !== undefined && isDirectTranslationApiKey(this.row.key)) {
                this.onTextDraftChange(this.row.key, value);
              }
            })
            .onSubmit(() => {
              this.commitInputValue();
            })
            .onBlur(() => {
              this.commitInputValue();
            })
        } else if (this.row.type === 'switch') {
          Toggle({ type: ToggleType.Switch, isOn: this.row.value === 'On' })
            .width(uiSwitchWidth())
            .height(uiSwitchHeight())
            .selectedColor(themeAccentTextColor())
            .switchPointColor(Color.White)
            .margin({ left: 12 })
            .onChange((isOn: boolean) => {
              if (this.row.key !== undefined) {
                this.onSwitchChange(this.row.key, isOn);
              }
            })
        } else if (this.row.type === 'slider') {
          SettingsInlineSlider({
            row: this.row,
            onOptionSelect: this.onOptionSelect
          })
            .margin({ left: 12 })
        } else if ((this.row.type === 'list' && this.row.options !== undefined && this.row.options.length > 0) ||
          this.row.type === 'model' || this.row.type === 'dialog') {
          Row({ space: 6 }) {
            Text(uiValue(this.row.value))
              .fontSize(13)
              .fontColor(themeSecondaryText())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(14)
              .fontColor([themeTertiaryText()])
          }
          .constraintSize({ maxWidth: 190 })
          .margin({ left: 12 })
          .hitTestBehavior(HitTestMode.None)
        } else if (this.row.type === 'navigation') {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([themeTertiaryText()])
            .margin({ left: 12 })
        } else if (this.row.type === 'section') {
          Row()
            .width(0)
        } else if (this.row.type === 'info') {
          Text(uiValue(this.row.value))
            .fontSize(12)
            .fontColor(uiMaterialForegroundColor(themeSecondaryText()))
            .maxLines(2)
            .textAlign(TextAlign.End)
            .margin({ left: 12 })
        } else {
          Row({ space: 6 }) {
            Text(settingsRowActionText(this.row))
              .fontSize(13)
              .fontColor(themeAccentTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(14)
              .fontColor([themeTertiaryText()])
          }
            .margin({ left: 12 })
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(this.row.type === 'section' ? { left: 4, right: 4, top: 12, bottom: 2 } :
      { left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(this.row.type === 'section' ? themePageBackground() : uiListItemBackground(themeSurface()))
    .border({ width: { bottom: this.row.type === 'section' || this.lastInGroup ? 0 : 0.5 },
      color: themeDividerColor() })
    .borderRadius({
      topLeft: this.row.type !== 'section' && this.firstInGroup ? uiRadius(16) : 0,
      topRight: this.row.type !== 'section' && this.firstInGroup ? uiRadius(16) : 0,
      bottomLeft: this.row.type !== 'section' && this.lastInGroup ? uiRadius(16) : 0,
      bottomRight: this.row.type !== 'section' && this.lastInGroup ? uiRadius(16) : 0
    })
    .onClick(() => {
      if (this.row.type !== 'input' && this.row.type !== 'switch' && this.row.type !== 'info' &&
        this.row.type !== 'slider' && this.row.type !== 'section') {
        this.onTap();
      }
    })
  }
}

@Component
struct SettingsInlineSlider {
  row: SettingsRowItem = { title: '', summary: '', value: '', type: '' };
  onOptionSelect: (key: string, value: string) => void = () => {};
  @State liveValue: number = 0;

  aboutToAppear(): void {
    this.liveValue = settingsSliderNumberValue(this.row);
  }

  build() {
    Row() {
      Slider({
        value: this.liveValue,
        min: settingsSliderMin(this.row),
        max: settingsSliderMax(this.row),
        step: 1
      })
        .width(150)
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.liveValue = Math.round(value);
          if (this.row.key !== undefined) {
            this.onOptionSelect(this.row.key, settingsSliderTextValue(this.row, this.liveValue));
          }
        })
      Text(settingsSliderDisplayText(this.row, this.liveValue))
        .fontSize(12)
        .fontColor(themeAccentTextColor())
        .width(42)
        .textAlign(TextAlign.End)
    }
    .alignItems(VerticalAlign.Center)
  }
}

