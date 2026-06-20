import { FilterRule, FILTER_MODE_TITLE, FILTER_MODE_UPLOADER, FILTER_MODE_TAG, FILTER_MODE_TAG_NAMESPACE } from '../services/EhFilterStore';
import { uiStatusText, uiText } from '../shared/EhShared';
import { themeDangerText, themeDividerColor, themeMutedText, themePageBackground, themePrimaryColor, themePrimaryText, themeSecondaryText, themeSelectedBackgroundLight, themeSurface, themeSurfaceVariant } from '../shared/EhTheme';
import { PlaceholderScene } from './GalleryScenes';
import { SettingsSubToolbar } from './SessionSettingsScenes';

@Component
export struct FilterPanel {
  rules: FilterRule[] = [];
  newText: string = '';
  newMode: number = FILTER_MODE_TITLE;
  statusText: string = '';
  onBack: () => void = () => {};
  onNewTextChange: (text: string) => void = () => {};
  onNewModeChange: (mode: number) => void = () => {};
  onAdd: () => void = () => {};
  onRemove: (id: number) => void = () => {};
  onToggle: (id: number) => void = () => {};

  private filterModeName(mode: number): string {
    if (mode === FILTER_MODE_UPLOADER) {
      return uiText('Uploader');
    }
    if (mode === FILTER_MODE_TAG) {
      return uiText('Tag');
    }
    if (mode === FILTER_MODE_TAG_NAMESPACE) {
      return uiText('Tag:Namespace');
    }
    return uiText('Title');
  }

  private cycleMode(): void {
    const next = (this.newMode + 1) % 4;
    this.onNewModeChange(next);
  }

  build() {
    Column() {
      SettingsSubToolbar({
        title: uiText('Filter rules'),
        onBack: this.onBack
      })

      Column() {
        Row() {
          TextInput({ text: this.newText, placeholder: uiText('Filter text') })
            .layoutWeight(1)
            .height(40)
            .onChange((value: string) => {
              this.onNewTextChange(value);
            })
          Button(this.filterModeName(this.newMode))
            .height(40)
            .margin({ left: 8 })
            .onClick(() => {
              this.cycleMode();
            })
          Button(uiText('Add'))
            .height(40)
            .margin({ left: 8 })
            .fontWeight(FontWeight.Bold)
            .onClick(() => {
              this.onAdd();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 4 })

        if (this.statusText.length > 0) {
          Text(uiStatusText(this.statusText))
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .padding({ left: 16, right: 16, bottom: 8 })
            .width('100%')
        }

        Text(uiText('Mode: tap to cycle �� Title / Uploader / Tag / Tag:Namespace'))
          .fontSize(11)
          .fontColor(themeMutedText())
          .padding({ left: 16, right: 16, bottom: 10 })
          .width('100%')
      }
      .backgroundColor(themeSurface())

      if (this.rules.length === 0) {
        PlaceholderScene({
          title: 'No filters',
          detail: 'Add a filter rule above to hide matching galleries from lists.'
        })
      } else {
        List({ space: 0 }) {
          ForEach(this.rules, (rule: FilterRule) => {
            ListItem() {
              Row() {
                Column() {
                  Text(rule.text)
                    .fontSize(14)
                    .fontColor(rule.enabled ? themePrimaryText() : themeMutedText())
                    .fontWeight(rule.enabled ? FontWeight.Medium : FontWeight.Normal)
                  Text(this.filterModeName(rule.mode))
                    .fontSize(11)
                    .fontColor(themeSecondaryText())
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button(rule.enabled ? uiText('On') : uiText('Off'))
                  .height(30)
                  .fontSize(12)
                  .fontColor(rule.enabled ? themePrimaryColor() : themeMutedText())
                  .backgroundColor(rule.enabled ? themeSelectedBackgroundLight() : themeSurfaceVariant())
                  .margin({ left: 8 })
                  .onClick(() => {
                    this.onToggle(rule.id);
                  })
                Button(uiText('Remove'))
                  .height(30)
                  .fontSize(12)
                  .fontColor(themeDangerText())
                  .backgroundColor(themeSurfaceVariant())
                  .margin({ left: 6 })
                  .onClick(() => {
                    this.onRemove(rule.id);
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 12, top: 12, bottom: 12 })
              .backgroundColor(themeSurface())
            }
          }, (rule: FilterRule) => rule.id.toString())
        }
        .divider({ strokeWidth: 1, color: themeDividerColor() })
        .width('100%')
        .height('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}
