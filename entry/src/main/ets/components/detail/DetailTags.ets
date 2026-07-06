import { GalleryTagGroup, GalleryTagInfo } from '../../model/GalleryModels';
import { ehTagTranslationStore, EhTagSuggestion } from '../../services/EhTagTranslationStore';
import { shouldUseChineseUi, uiText } from '../../shared/EhShared';
import {
  themeFieldBackground,
  themeOnPrimaryText,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSurface,
  themeSurfaceVariant,
  themeTertiaryText
} from '../../shared/EhTheme';
import {
  buildSearchSuggestions,
  SearchSuggestionItem,
  SearchSuggestionList,
  SearchSummaryStrip
} from '../GallerySearchScenes';

@Component
export struct DetailTags {
  @Prop @Watch('onExternalDataChange') renderVersion: number = 0;
  @Prop @Watch('onExternalDataChange') tags: GalleryTagGroup[] = [];
  @Prop @Watch('onExternalDataChange') isDetailLoaded: boolean = false;
  onTagSearch: (namespace: string, tag: string) => void = (_namespace: string, _tag: string) => {};
  onAddTag: (fullTag: string) => void = (_fullTag: string) => {};
  onOpenTagVote: (info: GalleryTagInfo) => void = (_info: GalleryTagInfo) => {};
  @State visibleTags: GalleryTagGroup[] = [];
  @State tagRevision: number = 0;
  @State editMode: boolean = false;
  @State addTagText: string = '';
  @State suggestions: SearchSuggestionItem[] = [];
  @State selectedTagNamespaces: string[] = [];
  @State suggestionRevision: number = 0;

  aboutToAppear(): void {
    this.syncExternalData();
  }

  private onExternalDataChange(): void {
    this.syncExternalData();
  }

  private syncExternalData(): void {
    this.visibleTags = cloneTagGroups(this.tags);
    this.tagRevision++;
    if (!this.isDetailLoaded) {
      this.suggestions = [];
    }
  }

  private selectedNamespaceKey(): string {
    return this.selectedTagNamespaces.slice().sort().join('|');
  }

  private setEditMode(value: boolean): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
      this.editMode = value;
      if (!value) {
        this.addTagText = '';
        this.suggestions = [];
      }
    });
  }

  private updateAddTagText(value: string): void {
    this.addTagText = value;
    this.refreshSuggestions();
  }

  private refreshSuggestions(): void {
    const active = activeTagText(this.addTagText);
    if (active.length < 2) {
      this.suggestions = [];
      this.suggestionRevision++;
      return;
    }
    this.suggestions = cloneSuggestions(buildDetailTagSuggestions(this.addTagText, 0, this.selectedTagNamespaces));
    this.suggestionRevision++;
  }

  private toggleTagNamespace(namespace: string): void {
    this.selectedTagNamespaces = toggleNamespace(this.selectedTagNamespaces, namespace);
    this.refreshSuggestions();
  }

  private applySuggestion(suggestion: SearchSuggestionItem): void {
    if (suggestion.kind !== 'tag') {
      return;
    }
    this.submitAddTag(suggestionFullTag(suggestion));
  }

  private submitCurrentTag(): void {
    this.submitAddTag(this.addTagText);
  }

  private submitAddTag(fullTag: string): void {
    const tag = normalizeSubmittedTag(fullTag, this.selectedTagNamespaces);
    if (tag.length === 0) {
      return;
    }
    this.onAddTag(tag);
    this.addTagText = '';
    this.suggestions = [];
    this.suggestionRevision++;
  }

  private selectTag(info: GalleryTagInfo): void {
    if (!this.editMode) {
      this.onTagSearch(info.namespace, info.tag);
      return;
    }
    this.onOpenTagVote(cloneTagInfo(info));
  }

  build() {
    Column() {
        Row() {
          Text(uiText('Tags'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            SymbolGlyph(this.editMode ? $r('sys.symbol.xmark') : $r('sys.symbol.plus'))
              .fontSize(18)
              .fontColor([this.editMode ? themeOnPrimaryText() : themePrimaryColor()])
          }
          .width(34)
          .height(34)
          .borderRadius(17)
          .padding(0)
          .backgroundColor(this.editMode ? themePrimaryColor() : themeSurfaceVariant())
          .enabled(this.isDetailLoaded)
          .onClick(() => {
            this.setEditMode(!this.editMode);
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (!this.isDetailLoaded) {
          Text(uiText('Loading tags...'))
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .margin({ top: 8 })
        } else if (this.visibleTags.length === 0) {
          Text(uiText('No tags parsed'))
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .margin({ top: 8 })
        } else {
          Column({ space: 4 }) {
            ForEach(this.visibleTags, (group: GalleryTagGroup) => {
              TagGroupRow({
                tagRevision: this.tagRevision,
                group: group,
                editMode: this.editMode,
                onSelectTag: (info: GalleryTagInfo) => {
                  this.selectTag(info);
                }
              })
            }, (group: GalleryTagGroup) => group.namespace + ':' + this.tagRevision.toString())
          }
          .width('100%')
          .margin({ top: 8 })
        }

        if (this.editMode && this.isDetailLoaded) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              TextInput({ text: this.addTagText, placeholder: uiText('Enter new tag') })
                .height(38)
                .fontSize(14)
                .fontColor(themePrimaryText())
                .placeholderColor(themeTertiaryText())
                .backgroundColor(themeFieldBackground())
                .borderRadius(6)
                .padding({ left: 10, right: 10 })
                .layoutWeight(1)
                .onChange((value: string) => {
                  this.updateAddTagText(value);
                })
                .onFocus(() => {
                  this.refreshSuggestions();
                })
              Button({ type: ButtonType.Normal, stateEffect: true }) {
                SymbolGlyph($r('sys.symbol.plus'))
                  .fontSize(18)
                  .fontColor([themeOnPrimaryText()])
              }
              .width(42)
              .height(38)
              .borderRadius(6)
              .padding(0)
              .backgroundColor(themePrimaryColor())
              .onClick(() => {
                this.submitCurrentTag();
              })
            }
            .width('100%')

            if (this.addTagText.trim().length > 0) {
              SearchSummaryStrip({
                selectedTagNamespaces: this.selectedTagNamespaces,
                selectedTagNamespaceKey: this.selectedNamespaceKey(),
                revision: this.suggestionRevision,
                onToggleTagNamespace: (namespace: string) => {
                  this.toggleTagNamespace(namespace);
                }
              })
            }

            if (this.suggestions.length > 0) {
              SearchSuggestionList({
                suggestions: this.suggestions,
                revision: this.suggestionRevision,
                onSelect: (suggestion: SearchSuggestionItem) => {
                  this.applySuggestion(suggestion);
                }
              })
              .width('100%')
              .height(this.suggestionListHeight())
            }
          }
          .width('100%')
          .margin({ top: 10 })
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ y: -8 }))
            .animation({ duration: 180, curve: Curve.EaseInOut }))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(16)
      .backgroundColor(themeSurface())
    .width('100%')
  }

  private suggestionListHeight(): number {
    if (this.suggestions.length <= 2) {
      return 58;
    }
    if (this.suggestions.length <= 6) {
      return 158;
    }
    return 260;
  }
}

@Component
export struct TagGroupRow {
  @Prop tagRevision: number = 0;
  @Prop group: GalleryTagGroup = { namespace: '', tags: [] };
  @Prop editMode: boolean = false;
  onSelectTag: (info: GalleryTagInfo) => void = (_info: GalleryTagInfo) => {};

  private tagLabel(tag: string): string {
    if (!shouldUseChineseUi()) {
      return tag;
    }
    const translated = ehTagTranslationStore.translate(this.group.namespace, tag);
    return translated.length > 0 ? translated : tag;
  }

  private tagInfo(tag: string): GalleryTagInfo {
    const infos = this.group.tagInfos;
    if (infos !== undefined) {
      for (let i = 0; i < infos.length; i++) {
        if (infos[i].tag === tag || infos[i].fullTag === this.group.namespace + ':' + tag) {
          return cloneTagInfo(infos[i]);
        }
      }
    }
    return {
      id: 0,
      namespace: this.group.namespace,
      tag: tag,
      fullTag: this.group.namespace + ':' + tag
    };
  }

  build() {
    Row() {
      Text(this.group.namespace)
        .fontSize(14)
        .fontColor(themeSecondaryText())
        .width(80)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.group.tags, (tag: string) => {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              if (this.editMode) {
                SymbolGlyph($r('sys.symbol.arrow_up_circle'))
                  .fontSize(12)
                  .fontColor([themePrimaryColor()])
              }
              Text(this.tagLabel(tag))
                .fontSize(12)
                .fontColor(themePrimaryText())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .height(26)
          .backgroundColor(this.editMode ? '#E4F3F8' : themeSurfaceVariant())
          .borderRadius(4)
          .padding({ left: 8, right: 8 })
          .margin({ right: 6, bottom: 6 })
          .onClick(() => {
            this.onSelectTag(this.tagInfo(tag));
          })
        }, (tag: string) => this.group.namespace + ':' + tag)
      }
      .clip(true)
      .layoutWeight(1)
    }
    .width('100%')
  }
}

function cloneTagGroups(groups: GalleryTagGroup[]): GalleryTagGroup[] {
  const result: GalleryTagGroup[] = [];
  for (let i = 0; i < groups.length; i++) {
    result.push({
      namespace: groups[i].namespace,
      tags: groups[i].tags.slice(),
      tagInfos: cloneTagInfoList(groups[i].tagInfos)
    });
  }
  return result;
}

function cloneTagInfoList(infos: GalleryTagInfo[] | undefined): GalleryTagInfo[] | undefined {
  if (infos === undefined) {
    return undefined;
  }
  const result: GalleryTagInfo[] = [];
  for (let i = 0; i < infos.length; i++) {
    result.push(cloneTagInfo(infos[i]));
  }
  return result;
}

function cloneTagInfo(info: GalleryTagInfo): GalleryTagInfo {
  return {
    id: info.id,
    namespace: info.namespace,
    tag: info.tag,
    fullTag: info.fullTag,
    voteUpEd: info.voteUpEd,
    voteDownEd: info.voteDownEd
  };
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

function buildDetailTagSuggestions(text: string, limit: number, namespaces: string[]): SearchSuggestionItem[] {
  const trimmed = text.trim();
  const colon = trimmed.indexOf(':');
  if (colon < 0) {
    return buildSearchSuggestions(trimmed, limit, namespaces).filter((item: SearchSuggestionItem) => item.kind === 'tag');
  }
  const namespace = normalizeTagNamespace(trimmed.substring(0, colon));
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

function activeTagText(text: string): string {
  const trimmed = text.trim();
  const colon = trimmed.indexOf(':');
  return colon < 0 ? trimmed : trimmed.substring(colon + 1).trim();
}

function suggestionFullTag(suggestion: SearchSuggestionItem): string {
  const tag = suggestion.query.trim().replace(/\s+/g, ' ');
  const namespace = suggestion.namespace === undefined ? '' : suggestion.namespace.trim();
  if (tag.length === 0 || tag.indexOf(':') >= 0 || namespace.length === 0) {
    return tag;
  }
  return namespace + ':' + tag;
}

function normalizeSubmittedTag(tag: string, namespaces: string[]): string {
  const normalized = tag.trim().replace(/\s+/g, ' ');
  if (normalized.length === 0 || normalized.indexOf(':') >= 0 || namespaces.length !== 1) {
    return normalized;
  }
  return namespaces[0] + ':' + normalized;
}

function normalizeTagNamespace(namespace: string): string {
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
