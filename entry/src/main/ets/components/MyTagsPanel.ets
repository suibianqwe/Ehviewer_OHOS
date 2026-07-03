import { GallerySite } from '../model/GalleryModels';
import {
  ehMyTagsService,
  MyTagItem,
  MyTagKind,
  MyTagsPage,
  MyTagSetOption
} from '../services/EhMyTagsService';
import { ehTagTranslationStore, EhTagSuggestion } from '../services/EhTagTranslationStore';
import { buildSearchSuggestions, SearchSuggestionItem, SearchSuggestionList } from './GallerySearchScenes';
import { uiStatusText, uiText } from '../shared/EhShared';
import {
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

@Component
export struct MyTagsPanel {
  site: GallerySite = GallerySite.E;
  @State loading: boolean = false;
  @State saving: boolean = false;
  @State statusText: string = '';
  @State watchedText: string = '';
  @State hiddenText: string = '';
  @State tagsetName: string = '';
  @State tagsetColor: string = '';
  @State tagsetEnabled: boolean = true;
  @State tagsets: MyTagSetOption[] = [];
  @State watchedTags: MyTagItem[] = [];
  @State hiddenTags: MyTagItem[] = [];
  @State watchedSuggestions: SearchSuggestionItem[] = [];
  @State hiddenSuggestions: SearchSuggestionItem[] = [];
  private page: MyTagsPage | null = null;

  aboutToAppear(): void {
    this.loadTags();
  }

  private loadTags(): void {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.statusText = 'Loading My Tags...';
    ehMyTagsService.load(this.site).then((page: MyTagsPage) => {
      this.applyPage(page);
      this.statusText = 'My Tags loaded';
    }).catch((error: Error) => {
      this.statusText = 'My Tags load failed: ' + error.message;
    }).finally(() => {
      this.loading = false;
    });
  }

  private saveWatchedTag(): void {
    this.saveTag(this.watchedText, MyTagKind.Watched);
  }

  private saveHiddenTag(): void {
    this.saveTag(this.hiddenText, MyTagKind.Hidden);
  }

  private saveTagsetSettings(): void {
    if (this.saving) {
      return;
    }
    this.saving = true;
    this.statusText = 'Saving My Tags settings...';
    ehMyTagsService.saveTagsetSettings(this.site, this.page, this.tagsetEnabled, this.tagsetColor)
      .then((page: MyTagsPage) => {
        this.applyPage(page);
        this.statusText = 'My Tags settings saved';
      }).catch((error: Error) => {
        this.statusText = 'My Tags save failed: ' + error.message;
      }).finally(() => {
        this.saving = false;
      });
  }

  private saveTag(text: string, kind: MyTagKind): void {
    const tag = text.trim();
    if (tag.length === 0) {
      this.statusText = 'Enter a tag first';
      return;
    }
    if (this.saving) {
      return;
    }
    this.saving = true;
    this.statusText = 'Saving My Tags...';
    ehMyTagsService.saveTag(this.site, this.page, tag, kind).then((page: MyTagsPage) => {
      this.applyPage(page);
      if (kind === MyTagKind.Watched) {
        this.watchedText = '';
        this.watchedSuggestions = [];
      } else {
        this.hiddenText = '';
        this.hiddenSuggestions = [];
      }
      this.statusText = 'My Tags saved';
    }).catch((error: Error) => {
      this.statusText = 'My Tags save failed: ' + error.message;
    }).finally(() => {
      this.saving = false;
    });
  }

  private applyPage(page: MyTagsPage): void {
    this.page = page;
    this.tagsetName = page.tagsetName;
    this.tagsetColor = page.tagsetColor;
    this.tagsetEnabled = page.tagsetEnabled;
    this.tagsets = cloneTagsets(page.tagsets);
    this.watchedTags = cloneTags(page.watched);
    this.hiddenTags = cloneTags(page.hidden);
  }

  private updateWatchedText(value: string): void {
    this.watchedText = value;
    this.refreshSuggestions(value, MyTagKind.Watched);
  }

  private updateHiddenText(value: string): void {
    this.hiddenText = value;
    this.refreshSuggestions(value, MyTagKind.Hidden);
  }

  private refreshSuggestions(value: string, kind: MyTagKind): void {
    const text = value.trim();
    if (activeMyTagText(text).length < 2) {
      if (kind === MyTagKind.Watched) {
        this.watchedSuggestions = [];
      } else {
        this.hiddenSuggestions = [];
      }
      return;
    }
    const suggestions = buildMyTagSuggestions(text, 12);
    console.info('[MyTags] suggestions input="' + text + '" active="' + activeMyTagText(text) +
      '" count=' + suggestions.length.toString());
    if (kind === MyTagKind.Watched) {
      this.watchedSuggestions = cloneSuggestions(suggestions);
    } else {
      this.hiddenSuggestions = cloneSuggestions(suggestions);
    }
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          Text(uiText('Manage watched and hidden tags for the selected site.'))
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .lineHeight(18)
            .width('100%')

          MyTagsetSettingsCard({
            name: this.tagsetName,
            color: this.tagsetColor,
            tagsetEnabled: this.tagsetEnabled,
            tagsets: this.tagsets,
            loading: this.loading || this.saving,
            onColorChange: (value: string) => {
              this.tagsetColor = value;
            },
            onEnabledChange: (value: boolean) => {
              this.tagsetEnabled = value;
            },
            onSave: () => {
              this.saveTagsetSettings();
            }
          })

          Row({ space: 10 }) {
            MyTagsColumn({
              title: 'Subscription',
              summary: 'Watched tags are used by the subscription page',
              text: this.watchedText,
              placeholder: 'Tag name',
              tags: this.watchedTags,
              suggestions: this.watchedSuggestions,
              loading: this.loading || this.saving,
              onTextChange: (value: string) => {
                this.updateWatchedText(value);
              },
              onSuggestionSelect: (value: string) => {
                this.watchedText = value;
                this.watchedSuggestions = [];
              },
              onSave: () => {
                this.saveWatchedTag();
              }
            })
              .layoutWeight(1)
            MyTagsColumn({
              title: 'Blocked',
              summary: 'Hidden tags are filtered by the account',
              text: this.hiddenText,
              placeholder: 'Tag name',
              tags: this.hiddenTags,
              suggestions: this.hiddenSuggestions,
              loading: this.loading || this.saving,
              onTextChange: (value: string) => {
                this.updateHiddenText(value);
              },
              onSuggestionSelect: (value: string) => {
                this.hiddenText = value;
                this.hiddenSuggestions = [];
              },
              onSave: () => {
                this.saveHiddenTag();
              }
            })
              .layoutWeight(1)
          }
          .alignItems(VerticalAlign.Top)
          .width('100%')

          Row() {
            Button(uiText('Refresh'), { type: ButtonType.Normal, stateEffect: true })
              .fontSize(13)
              .fontColor(themeOnPrimaryText())
              .backgroundColor(themePrimaryColor())
              .borderRadius(6)
              .height(36)
              .enabled(!this.loading && !this.saving)
              .onClick(() => {
                this.loadTags();
              })
            Text(uiStatusText(this.statusText))
              .fontSize(12)
              .fontColor(themeTertiaryText())
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: 10 })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .padding({ left: 12, right: 12, top: 12, bottom: 20 })
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}

@Component
struct MyTagsColumn {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop text: string = '';
  @Prop placeholder: string = '';
  @Prop tags: MyTagItem[] = [];
  @Prop suggestions: SearchSuggestionItem[] = [];
  @Prop loading: boolean = false;
  onTextChange: (value: string) => void = (_value: string) => {};
  onSuggestionSelect: (value: string) => void = (_value: string) => {};
  onSave: () => void = () => {};

  build() {
    Column({ space: 10 }) {
      Text(uiText(this.title))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(themePrimaryText())
        .width('100%')
      Text(uiText(this.summary))
        .fontSize(12)
        .fontColor(themeSecondaryText())
        .lineHeight(18)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Column({ space: 8 }) {
        TextInput({ text: this.text, placeholder: uiText(this.placeholder) })
          .height(38)
          .fontSize(14)
          .fontColor(themePrimaryText())
          .placeholderColor(themeTertiaryText())
          .backgroundColor(themeFieldBackground())
          .borderRadius(6)
          .padding({ left: 10, right: 10 })
          .onChange((value: string) => {
            this.onTextChange(value);
          })
        if (this.suggestions.length > 0) {
          SearchSuggestionList({
            suggestions: this.suggestions,
            revision: this.suggestions.length + this.text.length,
            onSelect: (suggestion: SearchSuggestionItem) => {
              this.onSuggestionSelect(suggestion.query);
            }
          })
          .width('100%')
          .height(this.suggestionListHeight())
        }
        Button(uiText('Save'), { type: ButtonType.Normal, stateEffect: true })
          .fontSize(13)
          .fontColor(themeOnPrimaryText())
          .backgroundColor(themePrimaryColor())
          .borderRadius(6)
          .height(36)
          .width('100%')
          .enabled(!this.loading && this.text.trim().length > 0)
          .onClick(() => {
            this.onSave();
          })
      }
      .width('100%')

      if (this.tags.length === 0) {
        Text(uiText('No tags'))
          .fontSize(12)
          .fontColor(themeTertiaryText())
          .width('100%')
          .padding(10)
          .backgroundColor(themeSurfaceVariant())
          .borderRadius(6)
      } else {
        ForEach(this.tags, (tag: MyTagItem) => {
          MyTagRow({ tag: tag })
        }, (tag: MyTagItem) => tag.id.toString())
      }
    }
    .padding(12)
    .width('100%')
    .backgroundColor(themeSurface())
    .borderRadius(6)
  }

  private suggestionListHeight(): number {
    if (this.suggestions.length <= 2) {
      return 52;
    }
    if (this.suggestions.length <= 6) {
      return 108;
    }
    return 164;
  }
}

@Component
struct MyTagsetSettingsCard {
  @Prop name: string = '';
  @Prop color: string = '';
  @Prop tagsetEnabled: boolean = true;
  @Prop tagsets: MyTagSetOption[] = [];
  @Prop loading: boolean = false;
  onColorChange: (value: string) => void = (_value: string) => {};
  onEnabledChange: (value: boolean) => void = (_value: boolean) => {};
  onSave: () => void = () => {};

  private tagsetSummary(): string {
    if (this.tagsets.length <= 1) {
      return this.name.length > 0 ? this.name : 'Default tagset';
    }
    const names: string[] = [];
    for (let i = 0; i < this.tagsets.length; i++) {
      names.push(this.tagsets[i].selected ? '[' + this.tagsets[i].name + ']' : this.tagsets[i].name);
    }
    return names.join(' / ');
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 3 }) {
          Text(uiText('Website settings'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
          Text(this.tagsetSummary())
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.tagsetEnabled })
          .onChange((isOn: boolean) => {
            this.onEnabledChange(isOn);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        TextInput({ text: this.color, placeholder: uiText('Default color') })
          .height(38)
          .fontSize(14)
          .fontColor(themePrimaryText())
          .placeholderColor(themeTertiaryText())
          .backgroundColor(themeFieldBackground())
          .borderRadius(6)
          .padding({ left: 10, right: 10 })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.onColorChange(value);
          })
        Button(uiText('Save settings'), { type: ButtonType.Normal, stateEffect: true })
          .fontSize(13)
          .fontColor(themeOnPrimaryText())
          .backgroundColor(themePrimaryColor())
          .borderRadius(6)
          .height(38)
          .enabled(!this.loading)
          .onClick(() => {
            this.onSave();
          })
      }
      .width('100%')
    }
    .padding(12)
    .width('100%')
    .backgroundColor(themeSurface())
    .borderRadius(6)
  }
}

@Component
struct MyTagRow {
  @Prop tag: MyTagItem = { id: 0, tag: '', watched: false, hidden: false, color: '', weight: '10' };

  build() {
    Row() {
      Text(this.tag.tag)
        .fontSize(13)
        .fontColor(themePrimaryText())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text('#' + this.tag.id.toString())
        .fontSize(11)
        .fontColor(themeTertiaryText())
        .margin({ left: 6 })
    }
    .width('100%')
    .height(44)
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor(themeSurfaceVariant())
    .borderRadius(6)
  }
}

function cloneTags(tags: MyTagItem[]): MyTagItem[] {
  const result: MyTagItem[] = [];
  for (let i = 0; i < tags.length; i++) {
    result.push({
      id: tags[i].id,
      tag: tags[i].tag,
      watched: tags[i].watched,
      hidden: tags[i].hidden,
      color: tags[i].color,
      weight: tags[i].weight
    });
  }
  return result;
}

function cloneTagsets(tagsets: MyTagSetOption[]): MyTagSetOption[] {
  const result: MyTagSetOption[] = [];
  for (let i = 0; i < tagsets.length; i++) {
    result.push({
      id: tagsets[i].id,
      name: tagsets[i].name,
      count: tagsets[i].count,
      selected: tagsets[i].selected
    });
  }
  return result;
}

function cloneSuggestions(suggestions: SearchSuggestionItem[]): SearchSuggestionItem[] {
  const result: SearchSuggestionItem[] = [];
  for (let i = 0; i < suggestions.length; i++) {
    result.push({
      kind: suggestions[i].kind,
      title: suggestions[i].title,
      subtitle: suggestions[i].subtitle,
      query: suggestions[i].query,
      translated: suggestions[i].translated,
      namespace: suggestions[i].namespace
    });
  }
  return result;
}

function buildMyTagSuggestions(text: string, limit: number): SearchSuggestionItem[] {
  const trimmed = text.trim();
  const colon = trimmed.indexOf(':');
  if (colon < 0) {
    return buildSearchSuggestions(trimmed, limit).filter((item: SearchSuggestionItem) => item.kind === 'tag');
  }
  const namespace = normalizeMyTagNamespace(trimmed.substring(0, colon));
  const keyword = trimmed.substring(colon + 1).trim();
  if (keyword.length < 2) {
    return [];
  }
  const tags = ehTagTranslationStore.suggest(keyword, limit, namespace.length > 0 ? [namespace] : []);
  const result: SearchSuggestionItem[] = [];
  for (let i = 0; i < tags.length; i++) {
    const tag: EhTagSuggestion = tags[i];
    result.push({
      kind: 'tag',
      title: tag.translated,
      subtitle: tag.tag,
      query: tag.tag,
      translated: tag.translated,
      namespace: tag.namespace
    });
  }
  return result;
}

function activeMyTagText(text: string): string {
  const trimmed = text.trim();
  const colon = trimmed.indexOf(':');
  return colon < 0 ? trimmed : trimmed.substring(colon + 1).trim();
}

function normalizeMyTagNamespace(namespace: string): string {
  const value = namespace.trim().toLowerCase();
  if (value === 'a' || value === 'art' || value === 'artist') {
    return 'artist';
  }
  if (value === 'f' || value === 'female') {
    return 'female';
  }
  if (value === 'm' || value === 'male') {
    return 'male';
  }
  if (value === 'p' || value === 'parody') {
    return 'parody';
  }
  if (value === 'c' || value === 'char' || value === 'character') {
    return 'character';
  }
  if (value === 'g' || value === 'group') {
    return 'group';
  }
  if (value === 'l' || value === 'lang' || value === 'language') {
    return 'language';
  }
  if (value === 'o' || value === 'other') {
    return 'other';
  }
  if (value === 'cos' || value === 'cosplayer') {
    return 'cosplayer';
  }
  if (value === 'loc' || value === 'location') {
    return 'location';
  }
  if (value === 'x' || value === 'mix' || value === 'mixed') {
    return 'mixed';
  }
  return value;
}
