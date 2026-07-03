import {
  FilterRule,
  FILTER_MODE_RATING,
  FILTER_MODE_TAG,
  FILTER_MODE_TAG_NAMESPACE,
  FILTER_MODE_TITLE,
  FILTER_MODE_UPLOADER
} from '../services/EhFilterStore';
import { uiStatusText, uiText } from '../shared/EhShared';
import { themeDangerText, themeDividerColor, themeMutedText, themeOnPrimaryText, themePageBackground, themePrimaryColor, themePrimaryText, themeSecondaryText, themeSelectedBackgroundLight, themeSurface, themeSurfaceVariant } from '../shared/EhTheme';
import { ArrayDataSource } from '../shared/ListDataSource';
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
      return uiText('Namespaced tag');
    }
    if (mode === FILTER_MODE_RATING) {
      return uiText('Rating');
    }
    return uiText('Title');
  }

  private inputPlaceholder(): string {
    if (this.newMode === FILTER_MODE_UPLOADER) {
      return uiText('Uploader');
    }
    if (this.newMode === FILTER_MODE_TAG) {
      return uiText('Tag');
    }
    if (this.newMode === FILTER_MODE_TAG_NAMESPACE) {
      return 'female:yuri';
    }
    if (this.newMode === FILTER_MODE_RATING) {
      return '2-5';
    }
    return uiText('Title');
  }

  build() {
    Column() {
      SettingsSubToolbar({
        title: uiText('Filter rules'),
        onBack: this.onBack
      })

      Column() {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            FilterModeButton({
              label: this.filterModeName(FILTER_MODE_TITLE),
              selected: this.newMode === FILTER_MODE_TITLE,
              onTap: () => { this.onNewModeChange(FILTER_MODE_TITLE); }
            })
            FilterModeButton({
              label: this.filterModeName(FILTER_MODE_UPLOADER),
              selected: this.newMode === FILTER_MODE_UPLOADER,
              onTap: () => { this.onNewModeChange(FILTER_MODE_UPLOADER); }
            })
            FilterModeButton({
              label: this.filterModeName(FILTER_MODE_TAG),
              selected: this.newMode === FILTER_MODE_TAG,
              onTap: () => { this.onNewModeChange(FILTER_MODE_TAG); }
            })
          }
          .width('100%')

          Row({ space: 8 }) {
            FilterModeButton({
              label: this.filterModeName(FILTER_MODE_TAG_NAMESPACE),
              selected: this.newMode === FILTER_MODE_TAG_NAMESPACE,
              onTap: () => { this.onNewModeChange(FILTER_MODE_TAG_NAMESPACE); }
            })
            FilterModeButton({
              label: this.filterModeName(FILTER_MODE_RATING),
              selected: this.newMode === FILTER_MODE_RATING,
              onTap: () => { this.onNewModeChange(FILTER_MODE_RATING); }
            })
          }
          .width('100%')

          Row() {
            TextInput({ text: this.newText, placeholder: this.inputPlaceholder() })
              .layoutWeight(1)
              .height(40)
              .onChange((value: string) => {
                this.onNewTextChange(value);
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

      }
      .backgroundColor(themeSurface())

      if (this.rules.length === 0) {
        PlaceholderScene({
          title: uiText('No filters'),
          detail: uiText('Add a filter rule above to hide matching galleries from lists.')
        })
      } else {
        List({ space: 0 }) {
          LazyForEach(new ArrayDataSource<FilterRule>(this.rules), (rule: FilterRule) => {
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
            .reuseId('filter-rule')
          }, (rule: FilterRule) => rule.id.toString())
        }
        .divider({ strokeWidth: 1, color: themeDividerColor() })
        .cachedCount(4)
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

@Component
struct FilterModeButton {
  label: string = '';
  selected: boolean = false;
  onTap: () => void = () => {};

  build() {
    Button(this.label)
      .height(32)
      .fontSize(12)
      .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.selected ? themeOnPrimaryText() : themeSecondaryText())
      .backgroundColor(this.selected ? themePrimaryColor() : themeSurfaceVariant())
      .borderRadius(8)
      .padding({ left: 12, right: 12 })
      .onClick(() => {
        this.onTap();
      })
  }
}
