import { KeyboardAvoidMode } from '@kit.ArkUI';
import { GallerySite } from '../model/GalleryModels';
import {
  ehMyTagsService,
  MyTagItem,
  MyTagKind,
  MyTagsPage
} from '../services/EhMyTagsService';
import { ehTagTranslationStore, EhTagSuggestion } from '../services/EhTagTranslationStore';
import {
  buildSearchSuggestions,
  SearchSuggestionItem,
  SearchSuggestionList,
  SearchSummaryStrip
} from './GallerySearchScenes';
import { uiText } from '../shared/EhShared';
import {
  themeFieldBackground,
  themeOnPrimaryText,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
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
  @State watchedTags: MyTagItem[] = [];
  @State hiddenTags: MyTagItem[] = [];
  @State watchedSuggestions: SearchSuggestionItem[] = [];
  @State hiddenSuggestions: SearchSuggestionItem[] = [];
  @State watchedTagNamespaces: string[] = [];
  @State hiddenTagNamespaces: string[] = [];
  @State suggestionRevision: number = 0;
  private page: MyTagsPage | null = null;
  private previousKeyboardAvoidMode: KeyboardAvoidMode | null = null;

  aboutToAppear(): void {
    this.setKeyboardAvoidance();
    this.loadTags();
  }

  aboutToDisappear(): void {
    this.restoreKeyboardAvoidance();
  }

  private setKeyboardAvoidance(): void {
    try {
      const uiContext = this.getUIContext();
      this.previousKeyboardAvoidMode = uiContext.getKeyboardAvoidMode();
      uiContext.setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
    } catch (_error) {
      this.previousKeyboardAvoidMode = null;
    }
  }

  private restoreKeyboardAvoidance(): void {
    if (this.previousKeyboardAvoidMode === null) {
      return;
    }
    try {
      this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardAvoidMode);
    } catch (_error) {
    }
    this.previousKeyboardAvoidMode = null;
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

  private deleteWatchedTag(tag: MyTagItem): void {
    this.deleteTag(tag);
  }

  private deleteHiddenTag(tag: MyTagItem): void {
    this.deleteTag(tag);
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

  private deleteTag(tag: MyTagItem): void {
    if (this.saving) {
      return;
    }
    this.saving = true;
    this.statusText = 'Deleting My Tags...';
    ehMyTagsService.deleteTag(this.site, this.page, tag).then((page: MyTagsPage) => {
      this.applyPage(page);
      this.statusText = 'My Tags saved';
    }).catch((error: Error) => {
      this.statusText = 'My Tags save failed: ' + error.message;
    }).finally(() => {
      this.saving = false;
    });
  }

  private applyPage(page: MyTagsPage): void {
    this.page = page;
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
      this.suggestionRevision++;
      return;
    }
    const namespaces = kind === MyTagKind.Watched ? this.watchedTagNamespaces : this.hiddenTagNamespaces;
    const suggestions = buildMyTagSuggestions(text, 0, namespaces);
    console.info('[MyTags] suggestions input="' + text + '" active="' + activeMyTagText(text) +
      '" count=' + suggestions.length.toString());
    if (kind === MyTagKind.Watched) {
      this.watchedSuggestions = cloneSuggestions(suggestions);
    } else {
      this.hiddenSuggestions = cloneSuggestions(suggestions);
    }
    this.suggestionRevision++;
  }

  private selectedWatchedTagNamespaceKey(): string {
    return this.watchedTagNamespaces.slice().sort().join('|');
  }

  private selectedHiddenTagNamespaceKey(): string {
    return this.hiddenTagNamespaces.slice().sort().join('|');
  }

  private toggleWatchedTagNamespace(namespace: string): void {
    this.watchedTagNamespaces = toggleNamespace(this.watchedTagNamespaces, namespace);
    this.refreshSuggestions(this.watchedText, MyTagKind.Watched);
  }

  private toggleHiddenTagNamespace(namespace: string): void {
    this.hiddenTagNamespaces = toggleNamespace(this.hiddenTagNamespaces, namespace);
    this.refreshSuggestions(this.hiddenText, MyTagKind.Hidden);
  }

  private applyWatchedSuggestion(suggestion: SearchSuggestionItem): void {
    this.saveSuggestion(suggestion, MyTagKind.Watched);
  }

  private applyHiddenSuggestion(suggestion: SearchSuggestionItem): void {
    this.saveSuggestion(suggestion, MyTagKind.Hidden);
  }

  private saveSuggestion(suggestion: SearchSuggestionItem, kind: MyTagKind): void {
    if (suggestion.kind !== 'tag') {
      return;
    }
    this.saveTag(suggestion.query, kind);
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          MyTagsColumn({
            title: 'Subscription',
            text: this.watchedText,
            placeholder: 'Tag name',
            tags: this.watchedTags,
            suggestions: this.watchedSuggestions,
            selectedTagNamespaces: this.watchedTagNamespaces,
            selectedTagNamespaceKey: this.selectedWatchedTagNamespaceKey(),
            revision: this.suggestionRevision,
            loading: this.loading || this.saving,
            onTextChange: (value: string) => {
              this.updateWatchedText(value);
            },
            onToggleTagNamespace: (namespace: string) => {
              this.toggleWatchedTagNamespace(namespace);
            },
            onSuggestionSelect: (suggestion: SearchSuggestionItem) => {
              this.applyWatchedSuggestion(suggestion);
            },
            onDelete: (tag: MyTagItem) => {
              this.deleteWatchedTag(tag);
            }
          })

          MyTagsColumn({
            title: 'Blocked',
            text: this.hiddenText,
            placeholder: 'Tag name',
            tags: this.hiddenTags,
            suggestions: this.hiddenSuggestions,
            selectedTagNamespaces: this.hiddenTagNamespaces,
            selectedTagNamespaceKey: this.selectedHiddenTagNamespaceKey(),
            revision: this.suggestionRevision,
            loading: this.loading || this.saving,
            onTextChange: (value: string) => {
              this.updateHiddenText(value);
            },
            onToggleTagNamespace: (namespace: string) => {
              this.toggleHiddenTagNamespace(namespace);
            },
            onSuggestionSelect: (suggestion: SearchSuggestionItem) => {
              this.applyHiddenSuggestion(suggestion);
            },
            onDelete: (tag: MyTagItem) => {
              this.deleteHiddenTag(tag);
            }
          })
        }
        .padding({ left: 12, right: 12, top: 12, bottom: 320 })
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}

@Component
struct MyTagsColumn {
  @Prop title: string = '';
  @Prop text: string = '';
  @Prop placeholder: string = '';
  @Prop tags: MyTagItem[] = [];
  @Prop suggestions: SearchSuggestionItem[] = [];
  @Prop selectedTagNamespaces: string[] = [];
  @Prop selectedTagNamespaceKey: string = '';
  @Prop revision: number = 0;
  @Prop loading: boolean = false;
  onTextChange: (value: string) => void = (_value: string) => {};
  onToggleTagNamespace: (namespace: string) => void = (_namespace: string) => {};
  onSuggestionSelect: (suggestion: SearchSuggestionItem) => void = (_suggestion: SearchSuggestionItem) => {};
  onDelete: (tag: MyTagItem) => void = (_tag: MyTagItem) => {};

  build() {
    Column({ space: 10 }) {
      Row() {
        Text(uiText(this.title))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .layoutWeight(1)
      }
        .width('100%')
        .alignItems(VerticalAlign.Center)

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
          .onFocus(() => {
            this.onTextChange(this.text);
          })
        if (this.hasSearchText()) {
          SearchSummaryStrip({
            selectedTagNamespaces: this.selectedTagNamespaces,
            selectedTagNamespaceKey: this.selectedTagNamespaceKey,
            revision: this.revision,
            onToggleTagNamespace: (namespace: string) => {
              this.onToggleTagNamespace(namespace);
            }
          })
        }
        if (this.suggestions.length > 0) {
          SearchSuggestionList({
            suggestions: this.suggestions,
            revision: this.revision,
            onSelect: (suggestion: SearchSuggestionItem) => {
              this.onSuggestionSelect(suggestion);
            }
          })
          .width('100%')
          .height(this.suggestionListHeight())
        }
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
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.tags, (tag: MyTagItem) => {
            MyTagRow({
              tag: tag,
              onDelete: (item: MyTagItem) => {
                this.onDelete(item);
              }
            })
              .margin({ right: 6, bottom: 6 })
          }, (tag: MyTagItem) => tag.id.toString())
        }
        .width('100%')
      }
    }
    .padding(12)
    .width('100%')
    .backgroundColor(themeSurface())
    .borderRadius(6)
  }

  private hasSearchText(): boolean {
    return this.text.trim().length > 0;
  }

  private suggestionListHeight(): number {
    if (this.suggestions.length <= 2) {
      return 56;
    }
    if (this.suggestions.length <= 6) {
      return 154;
    }
    return 260;
  }
}

@Component
struct MyTagRow {
  @Prop tag: MyTagItem = { id: 0, tag: '', watched: false, hidden: false, color: '', weight: '10' };
  onDelete: (tag: MyTagItem) => void = (_tag: MyTagItem) => {};

  build() {
    Row({ space: 4 }) {
      Text(myTagChipLabel(this.tag.tag))
        .fontSize(14)
        .fontColor(themeOnPrimaryText())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 180 })

      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(14)
        .fontColor([themeOnPrimaryText()])
        .width(18)
        .height(18)
        .onClick(() => {
          this.onDelete(this.tag);
        })
    }
    .height(28)
    .padding({ left: 9, right: 6 })
    .backgroundColor(themePrimaryColor())
    .borderRadius(14)
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

function myTagChipLabel(tag: string): string {
  return tag.trim().replace(/\s+/g, ' ');
}

function buildMyTagSuggestions(text: string, limit: number, namespaces: string[]): SearchSuggestionItem[] {
  const trimmed = text.trim();
  const colon = trimmed.indexOf(':');
  if (colon < 0) {
    return buildSearchSuggestions(trimmed, limit, namespaces).filter((item: SearchSuggestionItem) => item.kind === 'tag');
  }
  const namespace = normalizeMyTagNamespace(trimmed.substring(0, colon));
  const keyword = trimmed.substring(colon + 1).trim();
  if (keyword.length < 2) {
    return [];
  }
  const selectedNamespaces = namespace.length > 0 ? [namespace] : namespaces;
  const tags = ehTagTranslationStore.suggest(keyword, limit, selectedNamespaces);
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

function toggleNamespace(values: string[], namespace: string): string[] {
  const next = values.slice();
  const index = next.indexOf(namespace);
  if (index >= 0) {
    next.splice(index, 1);
  } else {
    next.push(namespace);
  }
  return next;
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
