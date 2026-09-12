import {
  DOWNLOAD_LOCATION_APP_FILES,
} from '../services/EhDownloadFileStore';
import {
  TranslationPromptProfile,
  activeTranslationPromptProfile,
  allTranslationPromptProfiles,
  cloneTranslationPromptProfiles,
  createTranslationPromptId,
  findTranslationPromptProfile,
  parseCustomTranslationPromptProfiles,
  serializeCustomTranslationPromptProfiles,
  uniqueTranslationPromptName,
} from '../services/TranslationSupport';
import {
  themeFieldBackground,
  themeDangerBackground,
  themeDangerText,
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
  uiButtonMaterial,
  uiTransparentButtonBackgroundEffect,
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiDialogMaterial,
  uiDialogSurfaceBackground,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow,
  uiMaterialBackground,
  uiMaterialLayerBackground,
  uiMaterialForegroundColor,
  uiButtonHighlightBorderColor,
  uiRadius,
  uiSearchFieldHeight,
  uiSegmentMaterial,
  uiTintedSegmentMaterial,
} from '../shared/EhUiStyle';
import { uiText, uiValue, normalizeProxyOption } from '../shared/EhShared';
import { AppSubToolbar } from './NavigationComponents';
import { SettingsOptionPanel } from './SettingsPanels';


@Component
export struct ProxySettingsOverlay {
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;
  initialType: string = 'System';
  initialHost: string = '';
  initialPort: string = '';
  initialUsername: string = '';
  initialPassword: string = '';
  initialExclusions: string = '';
  initialSocksDns: string = 'Proxy';
  socksSupported: boolean = false;
  @State draftType: string = 'System';
  @State draftHost: string = '';
  @State draftPort: string = '';
  @State draftUsername: string = '';
  @State draftPassword: string = '';
  @State draftExclusions: string = '';
  @State draftSocksDns: string = 'Proxy';
  onCancel: () => void = () => {};
  onSave: (type: string, host: string, port: string, username: string, password: string,
    exclusions: string, socksDns: string) => void = () => {};

  aboutToAppear(): void {
    this.draftType = normalizeProxyOption(this.initialType);
    this.draftHost = this.initialHost;
    this.draftPort = this.initialPort;
    this.draftUsername = this.initialUsername;
    this.draftPassword = this.initialPassword;
    this.draftExclusions = this.initialExclusions;
    this.draftSocksDns = this.initialSocksDns === 'System' ? 'System' : 'Proxy';
  }

  private customProxySelected(): boolean {
    return this.draftType === 'HTTP' || this.draftType === 'SOCKS';
  }

  @Builder
  private typeButton(type: string, label: string) {
    Button(uiText(label), { type: ButtonType.Normal, stateEffect: type !== 'SOCKS' || this.socksSupported })
      .height(42)
      .layoutWeight(1)
      .fontSize(14)
      .fontColor(this.draftType === type ? themeAccentTextColor() : themeSecondaryText())
      .fontWeight(this.draftType === type ? FontWeight.Medium : FontWeight.Normal)
      .backgroundColor(uiMaterialBackground(this.draftType === type ?
        uiMaterialLayerBackground(themeSelectedBackground()) : Color.Transparent))
      .enabled(type !== 'SOCKS' || this.socksSupported)
      .opacity(type === 'SOCKS' && !this.socksSupported ? 0.45 : 1)
      .animation({ duration: 180, curve: Curve.EaseInOut })
      .borderRadius(uiRadius(6))
      .border({ width: this.draftType === type ? 1 : 0,
        color: this.draftType === type ? themePrimaryColor() : Color.Transparent })
      .systemMaterial(this.draftType === type ?
        uiTintedSegmentMaterial(themeSelectedBackground()) : uiSegmentMaterial())
      .onClick(() => {
        this.draftType = type;
      })
  }

  @Builder
  private dnsButton(value: string, summary: string) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: 3 }) {
        Text(uiText(value))
          .fontSize(14)
          .fontColor(this.draftSocksDns === value ? themeOnPrimaryText() : themePrimaryText())
        Text(uiText(summary))
          .fontSize(10)
          .fontColor(this.draftSocksDns === value ? themeOnPrimaryText() : themeSecondaryText())
          .maxLines(2)
          .textAlign(TextAlign.Center)
      }
      .justifyContent(FlexAlign.Center)
    }
    .height(58)
    .layoutWeight(1)
    .backgroundColor(uiMaterialBackground(this.draftSocksDns === value ? themePrimaryColor() : themeFieldBackground()))
    .borderRadius(uiRadius(6))
    .systemMaterial(uiSegmentMaterial())
    .onClick(() => {
      this.draftSocksDns = value;
    })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      PopupScrim({
        showCutout: this.popupWidth > 0 && this.popupHeight > 0,
        cutoutWidth: this.popupWidth,
        cutoutHeight: this.popupHeight,
        cutoutRadius: uiDialogSurfaceRadius(),
        onDismiss: this.onCancel
      })

      Column() {
        Row() {
          Text(uiText('Proxy'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
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
          .onClick(this.onCancel)
        }
        .width('100%')

        Scroll() {
          Column({ space: 10 }) {
            Text(uiText('Proxy type'))
              .fontSize(13)
              .fontColor(themeSecondaryText())
              .width('100%')
            Row({ space: 8 }) {
              this.typeButton('Off', 'Direct')
              this.typeButton('System', 'System')
            }
            .width('100%')
            Row({ space: 8 }) {
              this.typeButton('HTTP', 'HTTP')
              this.typeButton('SOCKS', 'SOCKS')
            }
            .width('100%')

            if (!this.socksSupported) {
              Text(uiText('SOCKS5 requires HarmonyOS API 26 or later'))
                .fontSize(12)
                .fontColor(themeTertiaryText())
                .lineHeight(18)
                .width('100%')
            }

            if (this.customProxySelected()) {
              Text(uiText('Proxy host'))
                .fontSize(12)
                .fontColor(themeSecondaryText())
                .width('100%')
              TextInput({ text: this.draftHost, placeholder: uiText('Host or IP address') })
                .height(44)
                .fontSize(14)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
                .onChange((value: string) => {
                  this.draftHost = value;
                })
              Text(uiText('Proxy port'))
                .fontSize(12)
                .fontColor(themeSecondaryText())
                .width('100%')
              TextInput({ text: this.draftPort, placeholder: uiText('Proxy port') })
                .height(44)
                .fontSize(14)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
                .onChange((value: string) => {
                  this.draftPort = value;
                })
              Text(uiText('Proxy username'))
                .fontSize(12)
                .fontColor(themeSecondaryText())
                .width('100%')
              TextInput({ text: this.draftUsername, placeholder: uiText('Optional authentication username') })
                .height(44)
                .fontSize(14)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
                .onChange((value: string) => {
                  this.draftUsername = value;
                })
              Text(uiText('Proxy password'))
                .fontSize(12)
                .fontColor(themeSecondaryText())
                .width('100%')
              TextInput({ text: this.draftPassword, placeholder: uiText('Optional authentication password') })
                .height(44)
                .type(InputType.Password)
                .fontSize(14)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
                .onChange((value: string) => {
                  this.draftPassword = value;
                })
              Text(uiText('Proxy exclusions'))
                .fontSize(12)
                .fontColor(themeSecondaryText())
                .width('100%')
              TextInput({ text: this.draftExclusions,
                placeholder: uiText('Comma-separated hosts that bypass the proxy') })
                .height(44)
                .fontSize(14)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
                .onChange((value: string) => {
                  this.draftExclusions = value;
                })

              if (this.draftType === 'SOCKS') {
                Text(uiText('SOCKS5 DNS'))
                  .fontSize(13)
                  .fontColor(themeSecondaryText())
                  .width('100%')
                  .margin({ top: 2 })
                Row({ space: 8 }) {
                  this.dnsButton('Proxy', 'Resolve target domains through the proxy')
                  this.dnsButton('System', 'Resolve target domains through the system')
                }
                .width('100%')
              }
            }
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)

        Row({ space: 8 }) {
          Button(uiText('Cancel'), { type: ButtonType.Normal, stateEffect: true })
            .height(42)
            .layoutWeight(1)
            .fontSize(14)
            .fontColor(themePrimaryText())
            .backgroundColor(uiMaterialBackground(themeSurfaceVariant()))
            .borderRadius(uiRadius(6))
            .border({ width: 1, color: uiButtonHighlightBorderColor() })
            .backgroundEffect(uiTransparentButtonBackgroundEffect())
            .systemMaterial(uiButtonMaterial())
            .onClick(this.onCancel)
          Button(uiText('Save'), { type: ButtonType.Normal, stateEffect: true })
            .height(42)
            .layoutWeight(1)
            .fontSize(14)
            .fontColor(themeOnPrimaryText())
            .backgroundColor(uiMaterialBackground(themePrimaryColor()))
            .borderRadius(uiRadius(6))
            .border({ width: 1, color: uiButtonHighlightBorderColor() })
            .backgroundEffect(uiTransparentButtonBackgroundEffect())
            .systemMaterial(uiButtonMaterial())
            .onClick(() => {
              this.onSave(this.draftType, this.draftHost, this.draftPort, this.draftUsername,
                this.draftPassword, this.draftExclusions, this.draftSocksDns);
            })
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .width('88%')
      .height('82%')
      .constraintSize({ maxWidth: 460, maxHeight: 650 })
      .padding(18)
      .backgroundColor(uiMaterialBackground(uiDialogSurfaceBackground()))
      .shadow(uiDialogSurfaceShadow())
      .borderRadius(uiDialogSurfaceRadius())
      .backgroundBlurStyle(uiDialogBlurStyle(), uiDialogBlurOptions())
      .systemMaterial(uiDialogMaterial())
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.popupWidth = Number.parseFloat(newArea.width.toString());
        this.popupHeight = Number.parseFloat(newArea.height.toString());
      })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }
}
@Component
export struct DownloadMigrationConfirmOverlay {
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;
  current: string = DOWNLOAD_LOCATION_APP_FILES;
  target: string = DOWNLOAD_LOCATION_APP_FILES;
  onCancel: () => void = () => {};
  onSwitchOnly: () => void = () => {};
  onMigrate: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      PopupScrim({
        showCutout: this.popupWidth > 0 && this.popupHeight > 0,
        cutoutWidth: this.popupWidth,
        cutoutHeight: this.popupHeight,
        cutoutRadius: uiDialogSurfaceRadius(),
        onDismiss: this.onCancel
      })

      Column() {
        Text(uiText('Download location'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .width('100%')
        Text(uiText('Migrate downloaded files to the new location?'))
          .fontSize(14)
          .fontColor(themeSecondaryText())
          .lineHeight(20)
          .width('100%')
          .margin({ top: 10 })
        Text(uiText('Current') + ': ' + uiValue(this.current) + '  ->  ' + uiText('Target') + ': ' +
          uiValue(this.target))
          .fontSize(12)
          .fontColor(themeTertiaryText())
          .lineHeight(18)
          .width('100%')
          .margin({ top: 8 })

        Row({ space: 8 }) {
          Button(uiText('Cancel'), { type: ButtonType.Normal, stateEffect: true })
            .fontSize(14)
            .fontColor(themePrimaryText())
            .backgroundColor(uiMaterialBackground(themeSurfaceVariant()))
            .layoutWeight(1)
            .borderRadius(uiRadius(6))
            .border({ width: 1, color: uiButtonHighlightBorderColor() })
            .backgroundEffect(uiTransparentButtonBackgroundEffect())
            .systemMaterial(uiButtonMaterial())
            .onClick(this.onCancel)
          Button(uiText('Switch only'), { type: ButtonType.Normal, stateEffect: true })
            .fontSize(14)
            .fontColor(themePrimaryText())
            .backgroundColor(uiMaterialBackground(themeSurfaceVariant()))
            .layoutWeight(1)
            .borderRadius(uiRadius(6))
            .border({ width: 1, color: uiButtonHighlightBorderColor() })
            .backgroundEffect(uiTransparentButtonBackgroundEffect())
            .systemMaterial(uiButtonMaterial())
            .onClick(this.onSwitchOnly)
          Button(uiText('Migrate'), { type: ButtonType.Normal, stateEffect: true })
            .fontSize(14)
            .fontColor(themeOnPrimaryText())
            .backgroundColor(uiMaterialBackground(themePrimaryColor()))
            .layoutWeight(1)
            .borderRadius(uiRadius(6))
            .border({ width: 1, color: uiButtonHighlightBorderColor() })
            .backgroundEffect(uiTransparentButtonBackgroundEffect())
            .systemMaterial(uiButtonMaterial())
            .onClick(this.onMigrate)
        }
        .width('100%')
        .margin({ top: 18 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 420 })
      .padding(18)
      .backgroundColor(uiMaterialBackground(uiDialogSurfaceBackground()))
      .shadow(uiDialogSurfaceShadow())
      .borderRadius(uiDialogSurfaceRadius())
      .backgroundBlurStyle(uiDialogBlurStyle(), uiDialogBlurOptions())
      .systemMaterial(uiDialogMaterial())
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.popupWidth = Number.parseFloat(newArea.width.toString());
        this.popupHeight = Number.parseFloat(newArea.height.toString());
      })
    }
    .width('100%')
    .height('100%')
  }
}
@Component
export struct TranslationPromptPanel {
  @Prop selectedId: string = 'preset_faithful';
  @Prop customProfiles: string = '[]';
  @State profiles: TranslationPromptProfile[] = [];
  @State activeId: string = 'preset_faithful';
  @State editingId: string = '';
  @State promptName: string = '';
  @State promptText: string = '';
  @State localCustomProfiles: string = '[]';
  @State profileSelectorVisible: boolean = false;
  onBack: () => void = () => {};
  onSave: (selectedId: string, customProfiles: string, status: string) => void = () => {};

  aboutToAppear(): void {
    this.localCustomProfiles = this.customProfiles;
    this.profiles = allTranslationPromptProfiles(this.localCustomProfiles);
    const active = activeTranslationPromptProfile(this.selectedId, this.localCustomProfiles);
    this.activeId = active.id;
    this.loadProfile(active);
  }

  private loadProfile(profile: TranslationPromptProfile): void {
    this.editingId = profile.id;
    this.promptName = profile.builtIn ? uiText(profile.name) : profile.name;
    this.promptText = profile.prompt;
    this.activeId = profile.id;
  }

  private chooseProfile(profile: TranslationPromptProfile): void {
    this.loadProfile(profile);
    this.profileSelectorVisible = false;
    this.onSave(profile.id, this.localCustomProfiles, 'Prompt selected');
  }

  private profileDisplayName(profile: TranslationPromptProfile): string {
    return profile.builtIn ? uiText(profile.name) : profile.name;
  }

  private profileNames(): string[] {
    const names: string[] = [];
    for (let i = 0; i < this.profiles.length; i++) {
      const base = this.profileDisplayName(this.profiles[i]);
      let candidate = base;
      let suffix = 2;
      while (names.indexOf(candidate) >= 0) {
        candidate = base + ' (' + suffix.toString() + ')';
        suffix++;
      }
      names.push(candidate);
    }
    return names;
  }

  private selectedProfileName(): string {
    const names = this.profileNames();
    const profiles = this.profiles;
    const activeId = this.activeId;
    for (let i = 0; i < profiles.length; i++) {
      if (profiles[i].id === activeId) {
        return names[i];
      }
    }
    return '';
  }

  private chooseProfileByName(name: string): void {
    const names = this.profileNames();
    for (let i = 0; i < names.length; i++) {
      if (names[i] === name) {
        this.chooseProfile(this.profiles[i]);
        return;
      }
    }
  }

  private savePrompt(): void {
    const name = this.promptName.trim();
    const prompt = this.promptText.trim();
    if (name.length === 0 || prompt.length === 0) {
      this.onSave(this.activeId, this.localCustomProfiles, 'Prompt name and content are required');
      return;
    }
    const allProfiles = allTranslationPromptProfiles(this.localCustomProfiles);
    const current = findTranslationPromptProfile(allProfiles, this.editingId);
    const customProfiles = cloneTranslationPromptProfiles(parseCustomTranslationPromptProfiles(this.localCustomProfiles));
    let id = this.editingId;
    if (current === null || current.builtIn) {
      id = createTranslationPromptId();
      customProfiles.push({
        id: id,
        name: uniqueTranslationPromptName(allProfiles, name),
        prompt: prompt,
        builtIn: false
      });
    } else {
      const saved = findTranslationPromptProfile(customProfiles, current.id);
      if (saved === null) {
        id = createTranslationPromptId();
        customProfiles.push({
          id: id,
          name: uniqueTranslationPromptName(allProfiles, name),
          prompt: prompt,
          builtIn: false
        });
      } else {
        saved.name = uniqueTranslationPromptName(allProfiles, name, saved.id);
        saved.prompt = prompt;
      }
    }
    this.localCustomProfiles = serializeCustomTranslationPromptProfiles(customProfiles);
    this.profiles = allTranslationPromptProfiles(this.localCustomProfiles);
    const selected = findTranslationPromptProfile(this.profiles, id);
    if (selected !== null) {
      this.loadProfile(selected);
    }
    this.onSave(id, this.localCustomProfiles, 'Prompt saved');
  }

  private deletePrompt(): void {
    const current = findTranslationPromptProfile(this.profiles, this.editingId);
    if (current === null || current.builtIn) {
      return;
    }
    const customProfiles = cloneTranslationPromptProfiles(parseCustomTranslationPromptProfiles(this.localCustomProfiles));
    for (let i = customProfiles.length - 1; i >= 0; i--) {
      if (customProfiles[i].id === current.id) {
        customProfiles.splice(i, 1);
      }
    }
    this.localCustomProfiles = serializeCustomTranslationPromptProfiles(customProfiles);
    this.profiles = allTranslationPromptProfiles(this.localCustomProfiles);
    const fallback = this.profiles[0];
    if (fallback !== undefined) {
      this.loadProfile(fallback);
      this.onSave(fallback.id, this.localCustomProfiles, 'Prompt deleted');
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        AppSubToolbar({
          title: uiText('System prompts'),
          translateY: 0,
          onBack: this.onBack
        })

        Column({ space: 10 }) {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row() {
              Text(uiText('Prompt preset'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(themePrimaryText())
                .layoutWeight(1)
              Text(this.selectedProfileName())
                .fontSize(14)
                .fontColor(themeSecondaryText())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ left: 12, right: 8 })
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(16)
                .fontColor([themeSecondaryText()])
            }
            .width('100%')
          }
          .width('100%')
          .height(52)
          .padding({ left: 14, right: 14 })
          .backgroundColor(uiMaterialBackground(themeSurface()))
          .borderRadius(uiRadius(6))
          .border({ width: 1, color: uiButtonHighlightBorderColor() })
          .backgroundEffect(uiTransparentButtonBackgroundEffect())
          .systemMaterial(uiButtonMaterial())
          .onClick(() => {
            this.profileSelectorVisible = true;
          })

          Text(uiText('Prompt name'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .width('100%')
            .margin({ top: 6 })
          TextInput({ text: this.promptName, placeholder: uiText('Name used in the prompt list') })
            .height(44)
            .width('100%')
            .fontSize(14)
            .fontColor(themePrimaryText())
            .placeholderColor(themeSecondaryText())
            .caretColor(themeAccentTextColor())
            .backgroundColor(themeFieldBackground())
            .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
            .onChange((value: string) => {
              this.promptName = value;
            })

          Text(uiText('System prompt'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .width('100%')
          TextArea({ text: this.promptText, placeholder: uiText('Instructions sent to the AI translation service') })
            .layoutWeight(1)
            .constraintSize({ minHeight: 80 })
            .width('100%')
            .fontSize(13)
            .fontColor(themePrimaryText())
            .placeholderColor(themeSecondaryText())
            .caretColor(themeAccentTextColor())
            .backgroundColor(themeFieldBackground())
            .borderRadius(uiRadius(18))
            .onChange((value: string) => {
              this.promptText = value;
            })

          Row({ space: 10 }) {
            if (findTranslationPromptProfile(this.profiles, this.editingId)?.builtIn === false) {
              Button(uiText('Delete'))
                .height(44)
                .fontSize(14)
                .fontColor(themeDangerText())
                .backgroundColor(uiMaterialBackground(themeDangerBackground()))
                .borderRadius(uiRadius(6))
                .border({ width: 1, color: uiButtonHighlightBorderColor() })
                .backgroundEffect(uiTransparentButtonBackgroundEffect())
                .systemMaterial(uiButtonMaterial())
                .onClick(() => {
                  this.deletePrompt();
                })
            }
            Button(uiText('Save'))
              .height(44)
              .layoutWeight(1)
              .fontSize(14)
              .fontColor(themeOnPrimaryText())
              .backgroundColor(uiMaterialBackground(themePrimaryColor()))
              .borderRadius(uiRadius(6))
              .border({ width: 1, color: uiButtonHighlightBorderColor() })
              .backgroundEffect(uiTransparentButtonBackgroundEffect())
              .systemMaterial(uiButtonMaterial())
              .onClick(() => {
                this.savePrompt();
              })
          }
          .width('100%')
          .margin({ bottom: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12, top: 12 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(themePageBackground())

      if (this.profileSelectorVisible) {
        SettingsOptionPanel({
          title: uiText('Prompt preset'),
          value: this.selectedProfileName(),
          options: this.profileNames(),
          onBack: () => {
            this.profileSelectorVisible = false;
          },
          onSelect: (value: string) => {
            this.chooseProfileByName(value);
          }
        })
          .zIndex(20)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}
