import { common } from '@kit.AbilityKit';
import {
  RemoteStorageProfile,
  REMOTE_STORAGE_KIND_WEBDAV,
  remoteStorageProfileDisplayName,
  remoteStorageProfileSummary,
  remoteStorageProfileStore
} from '../services/RemoteStorageProfiles';
import { RemoteSettingsCandidate, remoteStorageSyncService } from '../services/RemoteStorageSyncService';
import {
  createRemoteStorageProfileId,
  remoteStoragePortFromUrl,
  remoteStorageUrlWithoutPort
} from '../services/RemoteStorageSupport';
import { WebDavClient } from '../services/WebDavClient';
import { getAbilityContext } from '../shared/EhShared';
import { uiText } from '../shared/EhTranslations';
import {
  themeAccentTextColor,
  themeDividerColor,
  themeFieldBackground,
  themeOnPrimaryText,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSurface,
  themeSurfaceVariant,
  themeTertiaryText
} from '../shared/EhTheme';
import {
  uiButtonHighlightBorderColor,
  uiButtonMaterial,
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiDialogMaterial,
  uiDialogSurfaceBackground,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow,
  uiListItemBackground,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiRadius,
  uiSearchFieldHeight,
  uiSwitchHeight,
  uiSwitchWidth,
  uiTransparentButtonBackgroundEffect
} from '../shared/EhUiStyle';
import { PopupScrim } from './PopupScrim';
import { SettingsSubToolbar, SettingsTextBlock } from './SettingsPanels';

@Component
export struct RemoteStoragePanel {
  onBack: () => void = () => {};
  @State profiles: RemoteStorageProfile[] = [];
  @State editorVisible: boolean = false;
  @State editorProfile: RemoteStorageProfile = emptyRemoteStorageProfile();
  @State editorIsNew: boolean = true;
  @State panelStatus: string = '';
  @State settingsPickerVisible: boolean = false;
  @State settingsPickerBusy: boolean = false;
  @State settingsCandidates: RemoteSettingsCandidate[] = [];

  aboutToAppear(): void {
    this.reloadProfiles();
  }

  private async reloadProfiles(): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    await remoteStorageProfileStore.ensureLoaded(context);
    this.profiles = remoteStorageProfileStore.getProfiles();
  }

  private openNewProfile(): void {
    this.editorProfile = emptyRemoteStorageProfile();
    this.editorIsNew = true;
    this.editorVisible = true;
  }

  private openProfile(profile: RemoteStorageProfile): void {
    this.editorProfile = profile;
    this.editorIsNew = false;
    this.editorVisible = true;
  }

  private closeEditor(): void {
    this.editorVisible = false;
  }

  private async saveProfile(profile: RemoteStorageProfile): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      this.panelStatus = uiText('Sign in is required');
      return;
    }
    const saved = await remoteStorageProfileStore.upsert(context, profile);
    if (saved === null) {
      this.panelStatus = uiText('Enter a valid server URL');
      return;
    }
    this.editorVisible = false;
    this.panelStatus = uiText('Saved');
    await this.reloadProfiles();
    remoteStorageSyncService.refreshConfiguration();
  }

  private async removeProfile(profile: RemoteStorageProfile): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    if (await remoteStorageProfileStore.remove(context, profile.id)) {
      this.editorVisible = false;
      this.panelStatus = uiText('Removed');
      await this.reloadProfiles();
      remoteStorageSyncService.refreshConfiguration();
    }
  }

  private purposeSummary(profile: RemoteStorageProfile): string {
    const labels: string[] = [];
    if (profile.useForBackup) {
      labels.push(uiText('Backup'));
    }
    if (profile.useForSync) {
      labels.push(uiText('Sync'));
    }
    if (profile.useForDownloads) {
      labels.push(uiText('Downloads'));
    }
    return labels.join(' · ');
  }

  private async openSettingsPicker(): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      this.panelStatus = uiText('Sign in is required');
      return;
    }
    this.settingsCandidates = [];
    this.settingsPickerBusy = true;
    this.settingsPickerVisible = true;
    try {
      this.settingsCandidates = await remoteStorageSyncService.listRemoteSettings(context);
    } catch (error) {
      this.settingsCandidates = [];
    } finally {
      this.settingsPickerBusy = false;
    }
  }

  private async applyRemoteSettings(file: string): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    this.settingsPickerBusy = true;
    const applied = await remoteStorageSyncService.applyRemoteSettings(context, file);
    this.settingsPickerBusy = false;
    this.settingsPickerVisible = false;
    this.panelStatus = applied ? uiText('Settings restored') : uiText('Restore failed');
  }

  private profileRowTitle(profile: RemoteStorageProfile): string {
    return remoteStorageProfileDisplayName(profile);
  }

  private profileRowSummary(profile: RemoteStorageProfile): string {
    const purposes = this.purposeSummary(profile);
    if (profile.name.length > 0) {
      return purposes.length > 0 ?
        remoteStorageProfileSummary(profile) + ' · ' + purposes : remoteStorageProfileSummary(profile);
    }
    return purposes;
  }

  @Builder
  private profileRow(profile: RemoteStorageProfile, index: number) {
    Column() {
      Row() {
        SettingsTextBlock({
          title: this.profileRowTitle(profile),
          summary: this.profileRowSummary(profile)
        })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([themeTertiaryText()])
      }
      .width('100%')
      .padding(14)
      .onClick(() => {
        this.openProfile(profile);
      })
      if (index < this.profiles.length - 1) {
        Divider()
          .color(themeDividerColor())
          .strokeWidth(0.5)
          .margin({ left: 14, right: 14 })
      }
    }
    .width('100%')
    .backgroundColor(uiListItemBackground(themeSurface()))
    .borderRadius({
      topLeft: index === 0 ? uiRadius(16) : 0,
      topRight: index === 0 ? uiRadius(16) : 0,
      bottomLeft: index === this.profiles.length - 1 ? uiRadius(16) : 0,
      bottomRight: index === this.profiles.length - 1 ? uiRadius(16) : 0
    })
    .clip(true)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        SettingsSubToolbar({
          title: uiText('Remote storage'),
          showAction: true,
          actionIcon: $r('sys.symbol.plus'),
          onBack: () => {
            this.onBack();
          },
          onAction: () => {
            this.openNewProfile();
          }
        })

        List({ space: 0 }) {
          ListItem() {
            Row() {
              SettingsTextBlock({
                title: uiText('Restore device settings'),
                summary: uiText('Choose a device backup saved on the server')
              })
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(16)
                .fontColor([themeTertiaryText()])
            }
            .width('100%')
            .padding(14)
            .backgroundColor(uiListItemBackground(themeSurface()))
            .borderRadius(uiRadius(16))
            .onClick(() => {
              this.openSettingsPicker();
            })
          }
          .margin({ bottom: 8 })
          if (this.profiles.length === 0) {
            ListItem() {
              Column({ space: 6 }) {
                Text(uiText('No remote storage profiles'))
                  .fontSize(15)
                  .fontColor(themeSecondaryText())
                Text(uiText('Add a WebDAV server to back up or sync app data'))
                  .fontSize(12)
                  .fontColor(themeTertiaryText())
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .padding({ top: 60, bottom: 40 })
            }
          } else {
            ForEach(this.profiles, (profile: RemoteStorageProfile, index: number) => {
              ListItem() {
                this.profileRow(profile, index)
              }
            }, (profile: RemoteStorageProfile): string => profile.id)
          }
          if (this.panelStatus.length > 0) {
            ListItem() {
              Text(this.panelStatus)
                .fontSize(12)
                .fontColor(themeSecondaryText())
                .padding({ left: 4, top: 12, bottom: 4 })
                .width('100%')
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .padding({ left: 12, right: 12, top: 12, bottom: 16 })
      }
      .width('100%')
      .height('100%')

      if (this.editorVisible) {
        RemoteStorageEditorOverlay({
          profile: this.editorProfile,
          isNew: this.editorIsNew,
          onCancel: () => {
            this.closeEditor();
          },
          onSave: (profile: RemoteStorageProfile) => {
            this.saveProfile(profile);
          },
          onRemove: (profile: RemoteStorageProfile) => {
            this.removeProfile(profile);
          }
        })
          .width('100%')
          .height('100%')
          .zIndex(20)
      }

      if (this.settingsPickerVisible) {
        RemoteSettingsPickerOverlay({
          candidates: this.settingsCandidates,
          busy: this.settingsPickerBusy,
          onCancel: () => {
            this.settingsPickerVisible = false;
          },
          onPick: (file: string) => {
            this.applyRemoteSettings(file);
          }
        })
          .width('100%')
          .height('100%')
          .zIndex(21)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}

@Component
// eslint-disable-next-line @performance/avoid-overusing-custom-component-check
struct RemoteSettingsPickerOverlay {
  @Prop candidates: RemoteSettingsCandidate[] = [];
  @Prop busy: boolean = false;
  onCancel: () => void = () => {};
  onPick: (file: string) => void = (_file: string) => {};
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;

  private timeText(timestamp: number): string {
    if (timestamp <= 0) {
      return '';
    }
    const date = new Date(timestamp);
    const pad = (value: number): string => value < 10 ? '0' + value.toString() : value.toString();
    return date.getFullYear().toString() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate()) + ' ' +
      pad(date.getHours()) + ':' + pad(date.getMinutes());
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
          Text(uiText('Restore device settings'))
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

        if (this.busy) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(themeSecondaryText())
            Text(uiText('Loading…'))
              .fontSize(13)
              .fontColor(themeSecondaryText())
          }
          .width('100%')
          .padding({ top: 18, bottom: 18 })
        } else if (this.candidates.length === 0) {
          Text(uiText('No saved settings'))
            .fontSize(13)
            .fontColor(themeSecondaryText())
            .width('100%')
            .padding({ top: 18, bottom: 18 })
        } else {
          Scroll() {
            Column({ space: 0 }) {
              ForEach(this.candidates, (candidate: RemoteSettingsCandidate) => {
                Row() {
                  Column({ space: 2 }) {
                    Text(candidate.deviceName)
                      .fontSize(14)
                      .fontColor(themePrimaryText())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                    Text(this.timeText(candidate.updatedAt))
                      .fontSize(11)
                      .fontColor(themeSecondaryText())
                      .width('100%')
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([themeTertiaryText()])
                }
                .width('100%')
                .padding(12)
                .onClick(() => {
                  this.onPick(candidate.file);
                })
              }, (candidate: RemoteSettingsCandidate): string => candidate.file)
            }
            .width('100%')
          }
          .constraintSize({ maxHeight: 360 })
          .scrollBar(BarState.Auto)
        }
      }
      .width('88%')
      .constraintSize({ maxWidth: 460 })
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
struct RemoteStorageEditorOverlay {
  profile: RemoteStorageProfile = emptyRemoteStorageProfile();
  isNew: boolean = true;
  onCancel: () => void = () => {};
  onSave: (profile: RemoteStorageProfile) => void = (_profile: RemoteStorageProfile) => {};
  onRemove: (profile: RemoteStorageProfile) => void = (_profile: RemoteStorageProfile) => {};
  @State draftName: string = '';
  @State draftUrl: string = '';
  @State draftPort: string = '';
  @State draftUsername: string = '';
  @State draftPassword: string = '';
  @State draftBasePath: string = '';
  @State draftUseForBackup: boolean = false;
  @State draftUseForSync: boolean = false;
  @State draftUseForDownloads: boolean = false;
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;
  @State busy: boolean = false;
  @State statusText: string = '';

  aboutToAppear(): void {
    this.draftName = this.profile.name;
    this.draftUrl = this.profile.url;
    this.draftPort = this.profile.port;
    if (this.draftPort.length === 0) {
      const extractedPort = remoteStoragePortFromUrl(this.draftUrl);
      if (extractedPort.length > 0) {
        this.draftPort = extractedPort;
        this.draftUrl = remoteStorageUrlWithoutPort(this.draftUrl);
      }
    }
    this.draftUsername = this.profile.username;
    this.draftPassword = this.profile.password;
    this.draftBasePath = this.profile.basePath;
    this.draftUseForBackup = this.profile.useForBackup;
    this.draftUseForSync = this.profile.useForSync;
    this.draftUseForDownloads = this.profile.useForDownloads;
  }

  private currentDraft(): RemoteStorageProfile {
    return {
      id: this.profile.id.length > 0 ? this.profile.id : createRemoteStorageProfileId(),
      name: this.draftName,
      kind: REMOTE_STORAGE_KIND_WEBDAV,
      url: this.draftUrl,
      port: this.draftPort,
      username: this.draftUsername,
      password: this.draftPassword,
      basePath: this.draftBasePath,
      useForBackup: this.draftUseForBackup,
      useForSync: this.draftUseForSync,
      useForDownloads: this.draftUseForDownloads,
      updatedAt: Date.now()
    };
  }

  private showFloating(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private localizedRemoteMessage(message: string): string {
    const prefix = 'Remote connection failed';
    if (message.startsWith(prefix)) {
      return uiText(prefix) + message.substring(prefix.length);
    }
    return uiText(message);
  }

  private async testConnection(): Promise<void> {
    this.busy = true;
    this.statusText = uiText('Testing connection...');
    this.showFloating(this.statusText);
    const client = new WebDavClient(this.currentDraft());
    const result = await client.testConnection();
    this.busy = false;
    this.statusText = result.ok ? uiText('Connection OK') : this.localizedRemoteMessage(result.message);
    this.showFloating(this.statusText);
  }

  @Builder
  private fieldLabel(title: string) {
    Text(uiText(title))
      .fontSize(13)
      .fontColor(themeSecondaryText())
      .width('100%')
  }

  @Builder
  private switchRow(title: string, summary: string, value: boolean, onChange: (value: boolean) => void) {
    Row() {
      SettingsTextBlock({ title: uiText(title), summary: uiText(summary) })
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .width(uiSwitchWidth())
        .height(uiSwitchHeight())
        .selectedColor(themeAccentTextColor())
        .switchPointColor(Color.White)
        .margin({ left: 12 })
        .onChange((isOn: boolean) => {
          onChange(isOn);
        })
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
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
          Text(uiText(this.isNew ? 'Add remote storage' : 'Edit remote storage'))
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
          Column({ space: 8 }) {
            this.fieldLabel('Name')
            TextInput({ text: this.draftName, placeholder: uiText('Display name') })
              .height(44)
              .fontSize(14)
              .fontColor(themePrimaryText())
              .backgroundColor(themeFieldBackground())
              .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
              .onChange((value: string) => {
                this.draftName = value;
              })

            this.fieldLabel('Server URL')
            TextInput({ text: this.draftUrl, placeholder: 'http://dav.example.com/remote.php/dav/files/user' })
              .height(44)
              .fontSize(14)
              .fontColor(themePrimaryText())
              .backgroundColor(themeFieldBackground())
              .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
              .onChange((value: string) => {
                this.draftUrl = value;
              })

            this.fieldLabel('Port')
            TextInput({ text: this.draftPort, placeholder: uiText('Optional, for example 5005') })
              .height(44)
              .fontSize(14)
              .type(InputType.Number)
              .fontColor(themePrimaryText())
              .backgroundColor(themeFieldBackground())
              .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
              .onChange((value: string) => {
                this.draftPort = value;
              })

            this.fieldLabel('Username')
            TextInput({ text: this.draftUsername, placeholder: uiText('Optional') })
              .height(44)
              .fontSize(14)
              .fontColor(themePrimaryText())
              .backgroundColor(themeFieldBackground())
              .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
              .onChange((value: string) => {
                this.draftUsername = value;
              })

            this.fieldLabel('Password')
            TextInput({ text: this.draftPassword, placeholder: uiText('Optional') })
              .height(44)
              .fontSize(14)
              .type(InputType.Password)
              .fontColor(themePrimaryText())
              .backgroundColor(themeFieldBackground())
              .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
              .onChange((value: string) => {
                this.draftPassword = value;
              })

            this.fieldLabel('Remote folder')
            TextInput({ text: this.draftBasePath, placeholder: uiText('Folder created for EhViewer data') })
              .height(44)
              .fontSize(14)
              .fontColor(themePrimaryText())
              .backgroundColor(themeFieldBackground())
              .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
              .onChange((value: string) => {
                this.draftBasePath = value;
              })

            this.switchRow('Use for backup', 'Write app data backups to this server', this.draftUseForBackup,
              (value: boolean) => {
                this.draftUseForBackup = value;
              })
            this.switchRow('Use for sync', 'Continuously sync settings, history and bookmarks', this.draftUseForSync,
              (value: boolean) => {
                this.draftUseForSync = value;
              })
            this.switchRow('Backup downloaded galleries', 'Mirror downloaded galleries to this server; local copies are kept', this.draftUseForDownloads,
              (value: boolean) => {
                this.draftUseForDownloads = value;
              })

            if (this.statusText.length > 0) {
              Text(this.statusText)
                .fontSize(12)
                .fontColor(themeSecondaryText())
                .width('100%')
                .lineHeight(18)
            }
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)

        Row({ space: 8 }) {
          if (!this.isNew) {
            Button(uiText('Remove'), { type: ButtonType.Capsule, stateEffect: true })
              .height(42)
              .layoutWeight(1)
              .fontSize(14)
              .fontColor(themePrimaryText())
              .backgroundColor(uiMaterialBackground(themeSurfaceVariant()))
              .borderRadius(uiRadius(21))
              .border({ width: 1, color: uiButtonHighlightBorderColor() })
              .backgroundEffect(uiTransparentButtonBackgroundEffect())
              .systemMaterial(uiButtonMaterial())
              .onClick(() => {
                this.onRemove(this.currentDraft());
              })
          }
          Button(uiText(this.busy ? 'Testing connection...' : 'Test'), { type: ButtonType.Capsule, stateEffect: true })
            .height(42)
            .layoutWeight(1)
            .fontSize(14)
            .fontColor(themePrimaryText())
            .backgroundColor(uiMaterialBackground(themeSurfaceVariant()))
            .borderRadius(uiRadius(21))
            .border({ width: 1, color: uiButtonHighlightBorderColor() })
            .backgroundEffect(uiTransparentButtonBackgroundEffect())
            .systemMaterial(uiButtonMaterial())
            .enabled(!this.busy)
            .onClick(() => {
              this.testConnection();
            })
          Button(uiText('Save'), { type: ButtonType.Capsule, stateEffect: true })
            .height(42)
            .layoutWeight(1)
            .fontSize(14)
            .fontColor(uiMaterialForegroundColor(themeOnPrimaryText()))
            .backgroundColor(uiMaterialBackground(themePrimaryColor()))
            .borderRadius(uiRadius(21))
            .border({ width: 1, color: uiButtonHighlightBorderColor() })
            .backgroundEffect(uiTransparentButtonBackgroundEffect())
            .systemMaterial(uiButtonMaterial())
            .onClick(() => {
              this.onSave(this.currentDraft());
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

function emptyRemoteStorageProfile(): RemoteStorageProfile {
  return {
    id: '',
    name: '',
    kind: REMOTE_STORAGE_KIND_WEBDAV,
    url: '',
    port: '5005',
    username: '',
    password: '',
    basePath: 'ehviewer',
    useForBackup: true,
    useForSync: false,
    useForDownloads: false,
    updatedAt: 0
  };
}
