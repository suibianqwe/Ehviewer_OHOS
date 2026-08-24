import {
  activeReaderPresetProfile,
  allReaderPresetProfiles,
  deleteCustomReaderPreset,
  ReaderPresetProfile,
  ReaderPresetSaveResult,
  readerPresetValuesFromSettings,
  saveCustomReaderPreset
} from '../services/ReaderPresetSupport';
import { uiText } from '../shared/EhShared';
import {
  themeAccentTextColor,
  themeDangerBackground,
  themeDangerText,
  themeFieldBackground,
  themeOnPrimaryText,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSelectedBackground,
  themeSurface,
  themeTertiaryText
} from '../shared/EhTheme';
import {
  uiButtonMaterial,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiRadius,
  uiSearchFieldHeight,
  uiSearchMaterial
} from '../shared/EhUiStyle';
import { AppSubToolbar } from './NavigationComponents';

@Component
export struct ReaderPresetPanel {
  @Prop customProfiles: string = '[]';
  @State profiles: ReaderPresetProfile[] = [];
  @State activeId: string = '';
  @State presetName: string = '';
  @State localCustomProfiles: string = '[]';
  onBack: () => void = () => {};
  onApply: (profileId: string) => void = (_profileId: string) => {};
  onSave: (customProfiles: string, status: string) => void = (_customProfiles: string, _status: string) => {};

  aboutToAppear(): void {
    this.localCustomProfiles = this.customProfiles;
    this.reloadProfiles();
  }

  private reloadProfiles(): void {
    this.profiles = allReaderPresetProfiles(this.localCustomProfiles);
    const active = activeReaderPresetProfile(this.profiles, readerPresetValuesFromSettings());
    this.activeId = active === null ? '' : active.id;
  }

  private applyProfile(profile: ReaderPresetProfile): void {
    this.activeId = profile.id;
    this.onApply(profile.id);
  }

  private saveCurrentPreset(): void {
    const preferred = this.presetName.trim();
    const nameError = this.presetNameError(preferred);
    if (nameError.length > 0) {
      this.onSave(this.localCustomProfiles, nameError);
      return;
    }
    const result: ReaderPresetSaveResult = saveCustomReaderPreset(this.localCustomProfiles, '', preferred,
      readerPresetValuesFromSettings());
    if (result.profile === null) {
      this.onSave(this.localCustomProfiles, result.error.length > 0 ? result.error : 'Save failed');
      return;
    }
    const profile = result.profile;
    this.localCustomProfiles = result.raw;
    this.presetName = '';
    this.reloadProfiles();
    this.activeId = profile.id;
    this.onSave(this.localCustomProfiles, 'Reading preset saved');
  }

  private presetNameError(name: string): string {
    const normalized = name.trim().toLowerCase();
    if (normalized.length === 0) {
      return 'Preset name is required';
    }
    if (normalized === 'current settings' || normalized === uiText('Current settings').trim().toLowerCase()) {
      return 'Preset name is reserved';
    }
    for (let i = 0; i < this.profiles.length; i++) {
      if (this.profiles[i].name.trim().toLowerCase() === normalized ||
        uiText(this.profiles[i].name).trim().toLowerCase() === normalized) {
        return 'Preset name already exists';
      }
    }
    return '';
  }

  private deleteProfile(profile: ReaderPresetProfile): void {
    if (profile.builtIn) {
      return;
    }
    this.localCustomProfiles = deleteCustomReaderPreset(this.localCustomProfiles, profile.id);
    this.reloadProfiles();
    this.onSave(this.localCustomProfiles, 'Reading preset deleted');
  }

  @Builder
  private PresetRow(profile: ReaderPresetProfile) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(profile.builtIn ? uiText(profile.name) : profile.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(profile.id === this.activeId ? themeAccentTextColor() : themePrimaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (profile.id === this.activeId) {
            Text(uiText('In use'))
              .fontSize(11)
              .fontColor(themeOnPrimaryText())
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(themePrimaryColor())
              .borderRadius(uiRadius(10))
          }
        }
        .width('100%')

        Text(uiText(profile.summary))
          .fontSize(12)
          .fontColor(themeSecondaryText())
          .lineHeight(17)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (!profile.builtIn) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(17)
            .fontColor([uiMaterialForegroundColor(themeDangerText())])
        }
        .width(38)
        .height(38)
        .backgroundColor(themeDangerBackground())
        .systemMaterial(uiButtonMaterial())
        .onClick(() => {
          this.deleteProfile(profile);
        })
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(15)
          .fontColor([themeTertiaryText()])
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 72 })
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(profile.id === this.activeId ? themeSelectedBackground() : themeSurface())
    .borderRadius(uiRadius(8))
    .onClick(() => {
      this.applyProfile(profile);
    })
  }

  build() {
    Column() {
      AppSubToolbar({
        title: uiText('Reading presets'),
        onBack: this.onBack
      })

      Column({ space: 8 }) {
        Text(uiText('Save and quickly apply groups of page layout and image processing settings'))
          .fontSize(13)
          .fontColor(themeSecondaryText())
          .lineHeight(19)
          .width('100%')

        List({ space: 8 }) {
          ForEach(this.profiles, (profile: ReaderPresetProfile) => {
            ListItem() {
              this.PresetRow(profile)
            }
          }, (profile: ReaderPresetProfile) => profile.id)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)

        Column({ space: 8 }) {
          Text(uiText('Save current settings'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .width('100%')
          Row({ space: 8 }) {
            TextInput({ text: this.presetName, placeholder: uiText('Preset name') })
              .height(uiSearchFieldHeight())
              .layoutWeight(1)
              .fontSize(14)
              .fontColor(uiMaterialForegroundColor(themePrimaryText()))
              .placeholderColor(themeSecondaryText())
              .caretColor(themeAccentTextColor())
              .backgroundColor(uiMaterialBackground(themeFieldBackground()))
              .systemMaterial(uiSearchMaterial())
              .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
              .onChange((value: string) => {
                this.presetName = value;
              })
            Button(uiText('Save'))
              .height(42)
              .fontSize(14)
              .fontColor(uiMaterialForegroundColor(themeOnPrimaryText()))
              .backgroundColor(themePrimaryColor())
              .systemMaterial(uiButtonMaterial())
              .borderRadius(uiRadius(6))
              .onClick(() => {
                this.saveCurrentPreset();
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(12)
        .backgroundColor(themeSurface())
        .borderRadius(uiRadius(8))
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}
