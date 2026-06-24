import { ALL_CATEGORY, GalleryCategory } from '../model/GalleryModels';
import { DEFAULT_ADVANCE_SEARCH, ListMode } from '../services/EhUrl';
import { ehTagTranslationStore } from '../services/EhTagTranslationStore';
import { mainContentWidthFallbackVp, rememberMainContentWidthVp } from '../services/EhWindowImmersive';
import { LANGUAGE_REVISION_KEY, categoryColor, uiText } from '../shared/EhShared';
import { themeControlMutedBackground, themeControlNeutralBackground, themeInactiveActionText, themeOnPrimaryText, themePrimaryColor, themePrimaryText, themeSecondaryText, themeShadowColor, themeSurface, themeSurfaceVariant } from '../shared/EhTheme';
import {
  selectArrowModifier,
  themedSelectButtonBackground,
  themedSelectButtonText,
  themedSelectMenuBackground,
  themedSelectOptionBackground,
  themedSelectOptionText,
  themedSelectOutlineColor,
  themedSelectSelectedOptionBackground,
  themedSelectSelectedOptionText
} from '../shared/EhSelectStyle';

export interface SearchSuggestionItem {
  kind: string;
  title: string;
  subtitle: string;
  query: string;
  translated?: string;
  namespace?: string;
}

export interface GalleryUrlMatch {
  gid: number;
  token: string;
}

interface SearchCategoryOption {
  label: string;
  category: number;
}

interface TagNamespaceOption {
  label: string;
  value: string;
}

const searchHistoryKeywords: string[] = [];
const SEARCH_SUGGESTION_RENDER_BATCH: number = 80;
const ACTION_BUBBLE_SIZE: number = 44;
const ACTION_BUBBLE_GAP: number = 8;
const ACTION_BUBBLE_PRIMARY_SIZE: number = 54;
const ACTION_BUBBLE_PRIMARY_GAP: number = 10;
let rememberedSearchCategory: number = GalleryCategory.None;
const TAG_NAMESPACE_OPTIONS: TagNamespaceOption[] = [
  { label: 'Artist', value: 'artist' },
  { label: 'Group', value: 'group' },
  { label: 'Parody', value: 'parody' },
  { label: 'Character', value: 'character' },
  { label: 'Female', value: 'female' },
  { label: 'Male', value: 'male' },
  { label: 'Mixed', value: 'mixed' },
  { label: 'Language', value: 'language' },
  { label: 'Cosplayer', value: 'cosplayer' },
  { label: 'Other', value: 'other' },
  { label: 'Location', value: 'location' },
  { label: 'Rows', value: 'rows' }
];

function activeTagPrefix(keyword: string): string {
  const parts = keyword.trim().split(/\s+/);
  const collected: string[] = [];
  for (let i = parts.length - 1; i >= 0; i--) {
    if (parts[i].indexOf(':') >= 0 || parts[i].indexOf('$') >= 0) {
      break;
    }
    collected.unshift(parts[i]);
  }
  return collected.join(' ').trim();
}

export function applyTagSuggestionToKeyword(keyword: string, tag: string): string {
  const trimmed = keyword.trim();
  if (trimmed.length === 0) {
    return tag;
  }
  const active = activeTagPrefix(trimmed);
  if (active.length === 0) {
    return (trimmed + ' ' + tag).trim();
  }
  const start = trimmed.length - active.length;
  if (start <= 0) {
    return tag;
  }
  return (trimmed.substring(0, start).trim() + ' ' + tag).trim();
}

export function recordSearchHistory(keyword: string): void {
  const trimmed = keyword.trim();
  if (trimmed.length === 0) {
    return;
  }
  for (let i = searchHistoryKeywords.length - 1; i >= 0; i--) {
    if (searchHistoryKeywords[i] === trimmed) {
      searchHistoryKeywords.splice(i, 1);
    }
  }
  searchHistoryKeywords.unshift(trimmed);
  if (searchHistoryKeywords.length > 128) {
    searchHistoryKeywords.splice(128);
  }
}

function parseGalleryUrl(text: string): GalleryUrlMatch | null {
  const match = text.match(/\/g\/(\d+)\/([a-fA-F0-9]+)\/?/);
  if (match === null) {
    return null;
  }
  const gid = Number.parseInt(match[1]);
  if (Number.isNaN(gid) || gid <= 0) {
    return null;
  }
  return { gid: gid, token: match[2] };
}

export function gallerySuggestionUrl(text: string): GalleryUrlMatch | null {
  return parseGalleryUrl(text);
}

export function buildSearchSuggestions(keyword: string, limit: number = 0,
  namespaces: string[] = []): SearchSuggestionItem[] {
  const text = keyword.trim();
  const next: SearchSuggestionItem[] = [];
  if (text.length === 0) {
    const unlimited = limit <= 0;
    for (let i = 0; i < searchHistoryKeywords.length && (unlimited || next.length < limit); i++) {
      const history = searchHistoryKeywords[i];
      next.push({
        kind: 'history',
        title: history,
        subtitle: 'Search history',
        query: history
      });
    }
    return next;
  }

  const active = activeTagPrefix(text);
  if (active.length === 0) {
    return next;
  }

  const tags = ehTagTranslationStore.suggest(active, limit, namespaces);
  for (let i = 0; i < tags.length; i++) {
    const tag = tags[i];
    next.push({
      kind: 'tag',
      title: tag.translated,
      subtitle: tag.tag,
      query: tag.tag,
      translated: tag.translated,
      namespace: tag.namespace
    });
  }
  return next;
}

@Component
export struct SearchSummaryStrip {
  @Prop selectedTagNamespaces: string[] = [];
  @Prop selectedTagNamespaceKey: string = '';
  @Prop revision: number = 0;
  onToggleTagNamespace: (namespace: string) => void = (_namespace: string) => {};

  build() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(TAG_NAMESPACE_OPTIONS, (option: TagNamespaceOption, index: number) => {
          SearchNamespaceChip({
            label: option.label,
            paletteIndex: index,
            isActive: this.namespaceSelected(option.value),
            revision: this.revision,
            onClickAction: () => {
              this.onToggleTagNamespace(option.value);
            }
          })
        }, (option: TagNamespaceOption) => option.value)
      }
    }
    .width('100%')
    .height(36)
    .padding({ top: 1, bottom: 1 })
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }

  private namespaceSelected(namespace: string): boolean {
    return ('|' + this.selectedTagNamespaceKey + '|').indexOf('|' + namespace + '|') >= 0 ||
      this.selectedTagNamespaces.indexOf(namespace) >= 0;
  }
}

@Component
export struct SearchSuggestionList {
  @Prop suggestions: SearchSuggestionItem[] = [];
  @Prop @Watch('onRevisionChanged') revision: number = 0;
  onSelect: (suggestion: SearchSuggestionItem) => void = (_suggestion: SearchSuggestionItem) => {};
  @State contentWidth: number = 0;
  @State renderLimit: number = SEARCH_SUGGESTION_RENDER_BATCH;

  aboutToAppear(): void {
    this.syncContentWidthFromWindow();
    this.resetRenderLimit();
    setTimeout(() => {
      this.syncContentWidthFromWindow();
    }, 0);
  }

  onRevisionChanged(): void {
    this.resetRenderLimit();
  }

  private resetRenderLimit(): void {
    this.renderLimit = SEARCH_SUGGESTION_RENDER_BATCH;
  }

  private visibleSuggestions(): SearchSuggestionItem[] {
    if (this.suggestions.length <= this.renderLimit) {
      return this.suggestions;
    }
    return this.suggestions.slice(0, this.renderLimit);
  }

  private loadMoreVisibleSuggestions(): void {
    if (this.renderLimit < this.suggestions.length) {
      this.renderLimit = Math.min(this.suggestions.length, this.renderLimit + SEARCH_SUGGESTION_RENDER_BATCH);
    }
  }

  private columnCount(): number {
    if (this.contentWidth <= 0) {
      return 1;
    }
    if (this.contentWidth < 320) {
      return 1;
    }
    if (this.contentWidth < 520) {
      return 2;
    }
    if (this.contentWidth < 760) {
      return 3;
    }
    if (this.contentWidth < 980) {
      return 4;
    }
    return 5;
  }

  private columnsTemplate(): string {
    const columns = this.columnCount();
    let value = '1fr';
    for (let i = 1; i < columns; i++) {
      value += ' 1fr';
    }
    return value;
  }

  private syncContentWidthFromWindow(): void {
    if (this.contentWidth >= 240) {
      return;
    }
    const width = mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value));
    if (width >= 240) {
      this.contentWidth = width;
    }
  }

  build() {
    Grid() {
      ForEach(this.visibleSuggestions(), (suggestion: SearchSuggestionItem) => {
        GridItem() {
          SearchSuggestionTile({
            suggestion: suggestion,
            onSelect: (item: SearchSuggestionItem) => {
              this.onSelect(item);
            }
          })
        }
      }, (suggestion: SearchSuggestionItem) => this.revision.toString() + ':' + suggestion.kind + ':' +
        suggestion.query + ':' + suggestion.subtitle)
    }
    .columnsTemplate(this.columnsTemplate())
    .columnsGap(6)
    .rowsGap(6)
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .onAppear(() => {
      this.syncContentWidthFromWindow();
    })
    .onReachEnd(() => {
      this.loadMoreVisibleSuggestions();
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const width = Math.floor(newArea.width as number);
      if (width > 0 && !Number.isNaN(width) && Math.abs(width - this.contentWidth) >= 1) {
        this.contentWidth = width;
        rememberMainContentWidthVp(width);
      }
    })
  }
}

@Component
struct SearchSuggestionTile {
  @Prop suggestion: SearchSuggestionItem = { kind: '', title: '', subtitle: '', query: '' };
  onSelect: (suggestion: SearchSuggestionItem) => void = (_suggestion: SearchSuggestionItem) => {};

  private iconForKind(kind: string): Resource {
    return kind === 'tag' ? $r('sys.symbol.star') : $r('sys.symbol.clock');
  }

  private tintForKind(kind: string): string {
    return kind === 'tag' ? themePrimaryColor() : themeSecondaryText();
  }

  build() {
    Row({ space: 5 }) {
      SymbolGlyph(this.iconForKind(this.suggestion.kind))
        .fontSize(18)
        .fontColor([this.tintForKind(this.suggestion.kind)])
        .width(19)
        .flexShrink(0)
      Column({ space: 1 }) {
        Text(this.suggestion.kind === 'history' ? uiText(this.suggestion.title) : this.suggestion.title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.suggestion.subtitle.length > 0) {
          Text(this.suggestion.subtitle)
            .fontSize(13)
            .fontColor(themeSecondaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height(44)
    .padding({ left: 6, right: 6 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(themeSurface())
    .borderRadius(5)
    .shadow({ radius: 3, color: themeShadowColor(), offsetX: 0, offsetY: 1 })
    .onClick(() => {
      this.onSelect(this.suggestion);
    })
  }
}

@Component
struct SearchNamespaceChip {
  @Prop label: string = '';
  @Prop paletteIndex: number = 0;
  @Prop isActive: boolean = false;
  @Prop revision: number = 0;
  onClickAction: () => void = () => {};

  private activeColor(): string {
    const colors: string[] = ['#245F82', '#5B4EA0', '#955626', '#24704D', '#8F3E66', '#456B9F'];
    return colors[this.paletteIndex % colors.length];
  }

  private softColor(): string {
    const colors: string[] = ['#D9EEF7', '#E8E3F8', '#F5E6D8', '#D8F0E4', '#F4DFEB', '#DEEAF7'];
    return colors[this.paletteIndex % colors.length];
  }

  private textColor(): string {
    const colors: string[] = ['#1E5575', '#4A3D8A', '#7A441D', '#245B40', '#77344F', '#375B86'];
    return colors[this.paletteIndex % colors.length];
  }

  build() {
    Button(uiText(this.label), { type: ButtonType.Normal, stateEffect: true })
      .width(102)
      .height(34)
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.isActive ? themeOnPrimaryText() : this.textColor())
      .backgroundColor(this.isActive ? this.activeColor() : this.softColor())
      .borderRadius(5)
      .padding({ left: 4, right: 4 })
      .opacity(this.isActive ? 1 : 0.72)
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onClick(() => {
        this.onClickAction();
      })
  }
}

@Component
export struct SearchAdvancedPanel {
  @Prop searchModeValue: ListMode = ListMode.Normal;
  @Prop searchCategory: number = GalleryCategory.None;
  @Prop advancedSearchEnabled: boolean = false;
  @Prop advanceSearch: number = DEFAULT_ADVANCE_SEARCH;
  @Prop minRating: number = -1;
  @Prop pageFrom: number = -1;
  @Prop pageTo: number = -1;
  @State modeDraft: ListMode = ListMode.Normal;
  @State categoryDraft: number = GalleryCategory.None;
  @State advancedEnabledDraft: boolean = false;
  @State advanceSearchDraft: number = DEFAULT_ADVANCE_SEARCH;
  @State minRatingDraft: number = -1;
  @State pageFromDraft: number = -1;
  @State pageToDraft: number = -1;
  @State modeLabelDraft: string = '';
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  onSearchModeChange: (mode: ListMode) => void = (_mode: ListMode) => {};
  onSearchCategoryChange: (category: number) => void = (_category: number) => {};
  onAdvancedEnabledChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onAdvanceSearchChange: (flags: number) => void = (_flags: number) => {};
  onMinRatingChange: (rating: number) => void = (_rating: number) => {};
  onPageFromChange: (value: number) => void = (_value: number) => {};
  onPageToChange: (value: number) => void = (_value: number) => {};
  onClose: () => void = () => {};
  onSearch: () => void = () => {};

  aboutToAppear(): void {
    this.modeDraft = this.searchModeValue;
    this.categoryDraft = this.searchCategory === GalleryCategory.None ? rememberedSearchCategory : this.searchCategory;
    this.advancedEnabledDraft = this.advancedSearchEnabled;
    this.advanceSearchDraft = this.advanceSearch;
    this.minRatingDraft = this.minRating;
    this.pageFromDraft = this.pageFrom;
    this.pageToDraft = this.pageTo;
    this.modeLabelDraft = this.modeLabelForIndex(this.searchModeIndex());
  }

  private searchModeOptions(): SelectOption[] {
    return [
      { value: uiText('General search') },
      { value: uiText('Subscription search') },
      { value: uiText('Uploader search') },
      { value: uiText('Tag search') }
    ];
  }
  private categoryOptions(): SearchCategoryOption[] {
    return [
      { label: 'Doujinshi', category: GalleryCategory.Doujinshi },
      { label: 'Manga', category: GalleryCategory.Manga },
      { label: 'Artist CG', category: GalleryCategory.ArtistCg },
      { label: 'Game CG', category: GalleryCategory.GameCg },
      { label: 'Image Set', category: GalleryCategory.ImageSet },
      { label: 'Cosplay', category: GalleryCategory.Cosplay },
      { label: 'Asian Porn', category: GalleryCategory.AsianPorn },
      { label: 'Non-H', category: GalleryCategory.NonH },
      { label: 'Western', category: GalleryCategory.Western },
      { label: 'Misc', category: GalleryCategory.Misc }
    ];
  }

  private searchModeIndex(): number {
    if (this.modeDraft === ListMode.Subscription) {
      return 1;
    }
    if (this.modeDraft === ListMode.Uploader) {
      return 2;
    }
    if (this.modeDraft === ListMode.Tag) {
      return 3;
    }
    return 0;
  }

  private modeLabelForIndex(index: number): string {
    const options = this.searchModeOptions();
    if (index < 0 || index >= options.length) {
      return options[0].value as string;
    }
    return options[index].value as string;
  }

  private selectedCategoryMask(): number {
    if (this.categoryDraft === GalleryCategory.None) {
      return ALL_CATEGORY;
    }
    return this.categoryDraft & ALL_CATEGORY;
  }

  private allCategoriesSelected(): boolean {
    return this.selectedCategoryMask() === ALL_CATEGORY;
  }

  private categorySelected(category: number): boolean {
    return (this.selectedCategoryMask() & category) !== 0;
  }

  private emitCategoryMask(mask: number): void {
    const next = mask === ALL_CATEGORY ? GalleryCategory.None : mask;
    this.categoryDraft = next;
    rememberedSearchCategory = next;
    this.onSearchCategoryChange(next);
  }

  private toggleAllCategories(): void {
    this.emitCategoryMask(this.allCategoriesSelected() ? 0 : ALL_CATEGORY);
  }

  private toggleCategory(category: number): void {
    const mask = this.selectedCategoryMask();
    const next = (mask & category) !== 0 ? (mask & ~category) : (mask | category);
    this.emitCategoryMask(next);
  }

  private modeForIndex(index: number): ListMode {
    if (index === 1) {
      return ListMode.Subscription;
    }
    if (index === 2) {
      return ListMode.Uploader;
    }
    if (index === 3) {
      return ListMode.Tag;
    }
    return ListMode.Normal;
  }

  private ratingLevel(): number {
    if (this.minRatingDraft <= 0) {
      return 1;
    }
    return Math.max(1, Math.min(5, this.minRatingDraft));
  }

  private setRatingLevel(level: number): void {
    const next = level <= 1 ? -1 : level;
    this.minRatingDraft = next;
    this.onMinRatingChange(next);
  }

  private flagOn(flag: number): boolean {
    return (this.advanceSearchDraft & flag) !== 0;
  }

  private setFlag(flag: number, enabled: boolean): void {
    const next = enabled ? (this.advanceSearchDraft | flag) : (this.advanceSearchDraft & ~flag);
    this.advanceSearchDraft = next;
    this.onAdvanceSearchChange(next);
  }

  @Builder
  private sectionTitle(title: string) {
    Text(uiText(title))
      .fontSize(12)
      .fontColor(themeSecondaryText())
      .fontWeight(FontWeight.Medium)
      .margin({ top: 4 })
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 10 }) {
          Row() {
            Select(this.searchModeOptions())
              .id('search-mode-select-' + this.languageRevision.toString() + '-' + this.modeLabelDraft)
              .selected(this.searchModeIndex())
              .value(this.modeLabelDraft.length > 0 ? this.modeLabelDraft : this.modeLabelForIndex(this.searchModeIndex()))
              .height(38)
              .width('100%')
              .fontColor(themedSelectButtonText())
              .backgroundColor(themedSelectButtonBackground())
              .menuBackgroundColor(themedSelectMenuBackground())
              .menuBackgroundBlurStyle(BlurStyle.NONE)
              .optionBgColor(themedSelectOptionBackground())
              .optionFontColor(themedSelectOptionText())
              .optionFont({ size: 13 })
              .selectedOptionBgColor(themedSelectSelectedOptionBackground())
              .selectedOptionFontColor(themedSelectSelectedOptionText())
              .menuOutline({ width: 1, color: themedSelectOutlineColor() })
              .arrowModifier(selectArrowModifier())
              .onSelect((index: number) => {
                const next = this.modeForIndex(index);
                this.modeDraft = next;
                this.modeLabelDraft = this.modeLabelForIndex(index);
                this.onSearchModeChange(next);
              })
          }
          .width('100%')

          this.sectionTitle('Categories')
          Button(uiText('All categories'))
            .height(32)
            .fontSize(14)
            .fontColor(this.allCategoriesSelected() ? themeOnPrimaryText() : themeSecondaryText())
            .backgroundColor(this.allCategoriesSelected() ? themePrimaryColor() : themeSurfaceVariant())
            .borderRadius(4)
            .width('100%')
            .onClick(() => {
              this.toggleAllCategories();
            })
          Column({ space: 8 }) {
            ForEach(this.categoryRows(), (row: SearchCategoryOption[]) => {
              Row({ space: 8 }) {
                ForEach(row, (option: SearchCategoryOption) => {
                  SearchCategoryChip({
                    label: option.label,
                    category: option.category,
                    selected: this.categorySelected(option.category),
                    onToggle: (category: number) => {
                      this.toggleCategory(category);
                    }
                  })
                }, (option: SearchCategoryOption) => option.category.toString())
              }
              .width('100%')
            }, (row: SearchCategoryOption[], index: number) => index.toString() + row.map((option: SearchCategoryOption) => option.category.toString()).join('-'))
          }
          .width('100%')

          Row() {
            Text(uiText('Advanced'))
            .fontSize(14)
            .fontColor(themePrimaryText())
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.advancedEnabledDraft })
              .onChange((isOn: boolean) => {
                this.advancedEnabledDraft = isOn;
                this.onAdvancedEnabledChange(isOn);
              })
          }
          .width('100%')
          .height(42)
          .padding({ left: 10, right: 10 })
          .backgroundColor(themeSurfaceVariant())
          .borderRadius(6)

          if (this.advancedEnabledDraft) {
            this.sectionTitle('Search galleries')
            Row({ space: 8 }) {
              SearchFlagChip({ label: 'Name', isOn: this.flagOn(0x1), onToggle: (isOn: boolean) => { this.setFlag(0x1, isOn); } })
              SearchFlagChip({ label: 'Tags', isOn: this.flagOn(0x2), onToggle: (isOn: boolean) => { this.setFlag(0x2, isOn); } })
            }
            Row({ space: 8 }) {
              SearchFlagChip({ label: 'Description', isOn: this.flagOn(0x4), onToggle: (isOn: boolean) => { this.setFlag(0x4, isOn); } })
              SearchFlagChip({ label: 'Torrent', isOn: this.flagOn(0x8), onToggle: (isOn: boolean) => { this.setFlag(0x8, isOn); } })
            }

            this.sectionTitle('Options')
            Row({ space: 8 }) {
              SearchFlagChip({ label: 'Has torrent', isOn: this.flagOn(0x10), onToggle: (isOn: boolean) => { this.setFlag(0x10, isOn); } })
              SearchFlagChip({ label: 'Low power', isOn: this.flagOn(0x20), onToggle: (isOn: boolean) => { this.setFlag(0x20, isOn); } })
            }
            Row({ space: 8 }) {
              SearchFlagChip({ label: 'Downvoted', isOn: this.flagOn(0x40), onToggle: (isOn: boolean) => { this.setFlag(0x40, isOn); } })
              SearchFlagChip({ label: 'Expunged', isOn: this.flagOn(0x80), onToggle: (isOn: boolean) => { this.setFlag(0x80, isOn); } })
            }

            this.sectionTitle('Disable default filter')
            Row({ space: 8 }) {
              SearchFlagChip({ label: 'No lang filter', isOn: this.flagOn(0x100), onToggle: (isOn: boolean) => { this.setFlag(0x100, isOn); } })
              SearchFlagChip({ label: 'No uploader filter', isOn: this.flagOn(0x200), onToggle: (isOn: boolean) => { this.setFlag(0x200, isOn); } })
            }
            Row({ space: 8 }) {
              SearchFlagChip({ label: 'No tag filter', isOn: this.flagOn(0x400), onToggle: (isOn: boolean) => { this.setFlag(0x400, isOn); } })
              Blank().layoutWeight(1)
            }

            this.sectionTitle('Rating')
            RatingStarBar({
              level: this.ratingLevel(),
              onSelect: (level: number) => {
                this.setRatingLevel(level);
              }
            })
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      }
      .width('100%')
      .constraintSize({ maxHeight: 440 })

      Column() {
        Button(uiText('Search'), { type: ButtonType.Normal, stateEffect: true }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(18)
              .fontColor([themeOnPrimaryText()])
            Text(uiText('Search'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(themeOnPrimaryText())
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .width('100%')
        }
        .height(44)
        .backgroundColor(themePrimaryColor())
        .borderRadius(8)
        .width('100%')
        .onClick(() => {
          this.onSearch();
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(themeSurface())
      .borderRadius({ bottomLeft: 8, bottomRight: 8 })
    }
    .width('100%')
    .backgroundColor(themeSurface())
    .borderRadius(8)
    .clip(true)
    .shadow({ radius: 12, color: themeShadowColor(), offsetX: 0, offsetY: 4 })
  }

  private categoryRows(): SearchCategoryOption[][] {
    const options = this.categoryOptions();
    const rows: SearchCategoryOption[][] = [];
    for (let i = 0; i < options.length; i += 2) {
      rows.push(options.slice(i, i + 2));
    }
    return rows;
  }
}

@Component
export struct QuickActionColumn {
  @Prop expanded: boolean = false;
  @Prop filterActive: boolean = false;
  @Prop canJump: boolean = false;
  @Prop canRandom: boolean = false;
  onToggle: () => void = () => {};
  onFilter: () => void = () => {};
  onJump: () => void = () => {};
  onRefresh: () => void = () => {};
  onRandom: () => void = () => {};
  @State activeActionIndex: number = -1;

  private toggleExpanded(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.onToggle();
    });
  }

  private actionCount(): number {
    return this.expanded ? 4 : 0;
  }

  private primaryIndex(): number {
    return this.actionCount();
  }

  private expandedActionsHeight(): number {
    const count = this.actionCount();
    if (count <= 0) {
      return 0;
    }
    return count * ACTION_BUBBLE_SIZE + (count - 1) * ACTION_BUBBLE_GAP;
  }

  private hitActionIndex(y: number): number {
    const count = this.actionCount();
    if (count > 0) {
      const actionsHeight = this.expandedActionsHeight();
      if (y >= 0 && y <= actionsHeight) {
        const row = Math.floor(y / (ACTION_BUBBLE_SIZE + ACTION_BUBBLE_GAP));
        const rowTop = row * (ACTION_BUBBLE_SIZE + ACTION_BUBBLE_GAP);
        if (row >= 0 && row < count && y >= rowTop && y <= rowTop + ACTION_BUBBLE_SIZE) {
          return row;
        }
      }
      const primaryTop = actionsHeight + ACTION_BUBBLE_PRIMARY_GAP;
      if (y >= primaryTop && y <= primaryTop + ACTION_BUBBLE_PRIMARY_SIZE) {
        return this.primaryIndex();
      }
      return -1;
    }
    if (y >= 0 && y <= ACTION_BUBBLE_PRIMARY_SIZE) {
      return this.primaryIndex();
    }
    return -1;
  }

  private touchY(event: TouchEvent): number {
    if (event.touches.length > 0) {
      return event.touches[0].y;
    }
    return -1;
  }

  private updateActiveAction(event: TouchEvent): void {
    const index = this.hitActionIndex(this.touchY(event));
    if (index !== this.activeActionIndex) {
      this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
        this.activeActionIndex = index;
      });
    }
  }

  private triggerAction(index: number): void {
    if (index < 0) {
      return;
    }
    if (index === this.primaryIndex()) {
      this.toggleExpanded();
      return;
    }
    if (index === 0) {
      this.onFilter();
    } else if (index === 1 && this.canJump) {
      this.onJump();
    } else if (index === 2) {
      this.onRefresh();
    } else if (index === 3 && this.canRandom) {
      this.onRandom();
    }
  }

  private handleToolbarTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      this.updateActiveAction(event);
    } else if (event.type === TouchType.Up) {
      const index = this.hitActionIndex(this.touchY(event));
      this.activeActionIndex = -1;
      this.triggerAction(index);
    } else if (event.type === TouchType.Cancel) {
      this.activeActionIndex = -1;
    }
  }

  build() {
    Column() {
      if (this.expanded) {
        Column({ space: 8 }) {
          ActionBubble({
            label: this.filterActive ? uiText('Filter On') : uiText('Filter'),
            symbolIcon: $r('sys.symbol.magnifyingglass'),
            isEnabled: true,
            active: this.activeActionIndex === 0,
            directTap: false
          })
          ActionBubble({
            label: uiText('Jump'),
            symbolIcon: $r('sys.symbol.chevron_forward'),
            isEnabled: this.canJump,
            active: this.activeActionIndex === 1,
            directTap: false
          })
          ActionBubble({
            label: uiText('Refresh'),
            symbolIcon: $r('sys.symbol.play_arrow_triangle_2_circlepath'),
            isEnabled: true,
            active: this.activeActionIndex === 2,
            directTap: false
          })
          ActionBubble({
            label: uiText('Random'),
            symbolIcon: $r('sys.symbol.play_fill'),
            isEnabled: this.canRandom,
            active: this.activeActionIndex === 3,
            directTap: false
          })
        }
        .alignItems(HorizontalAlign.End)
        .margin({ bottom: 10 })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: 12 }))
          .animation({ duration: 180, curve: Curve.EaseOut }))
      }

      ActionBubble({
        label: uiText('Actions'),
        symbolIcon: this.expanded ? $r('sys.symbol.xmark') : $r('sys.symbol.more'),
        isEnabled: true,
        primary: true,
        active: this.activeActionIndex === this.primaryIndex(),
        directTap: false
      })
    }
    .alignItems(HorizontalAlign.End)
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .onTouch((event: TouchEvent) => {
      this.handleToolbarTouch(event);
    })
  }
}

@Component
export struct ActionBubble {
  @Prop label: string = '';
  @Prop symbolIcon: Resource = $r('sys.symbol.plus');
  @Prop isEnabled: boolean = true;
  @Prop active: boolean = false;
  primary: boolean = false;
  directTap: boolean = true;
  onTapAction: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      if (this.active && this.label.length > 0) {
        Text(this.label)
          .fontSize(12)
          .fontColor(themePrimaryText())
          .textAlign(TextAlign.End)
          .backgroundColor(themeSurface())
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(14)
          .shadow({ radius: 8, color: themeShadowColor(), offsetX: 0, offsetY: 2 })
          .maxLines(1)
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ x: 8 }))
            .animation({ duration: 140, curve: Curve.EaseOut }))
      }

      Column() {
        SymbolGlyph(this.symbolIcon)
          .fontSize(this.primary ? 26 : 20)
          .fontColor([this.isEnabled ? themeOnPrimaryText() : themeInactiveActionText()])
      }
      .width(this.primary ? 54 : 44)
      .height(this.primary ? 54 : 44)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius(this.primary ? 27 : 22)
      .backgroundColor(this.isEnabled ? (this.primary ? themePrimaryColor() : themeControlNeutralBackground()) :
        themeControlMutedBackground())
      .shadow({ radius: this.primary ? 14 : 8, color: themeShadowColor(), offsetX: 0, offsetY: 3 })
      .scale({ x: this.active ? 0.92 : 1, y: this.active ? 0.92 : 1 })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onClick(() => {
        if (this.directTap && this.isEnabled) {
          this.onTapAction();
        }
      })
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.End)
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 12 }))
      .animation({ duration: 160, curve: Curve.EaseOut }))
  }
}

@Component
export struct SearchFlagChip {
  label: string = '';
  @Prop isOn: boolean = false;
  onToggle: (isOn: boolean) => void = (_isOn: boolean) => {};

  build() {
    Button(uiText(this.label))
      .height(30)
      .fontSize(13)
      .fontColor(this.isOn ? themeOnPrimaryText() : themeSecondaryText())
      .backgroundColor(this.isOn ? themePrimaryColor() : themeSurfaceVariant())
      .borderRadius(4)
      .layoutWeight(1)
      .onClick(() => {
        this.onToggle(!this.isOn);
      })
  }
}

@Component
export struct SearchCategoryChip {
  label: string = '';
  category: number = GalleryCategory.Unknown;
  @Prop selected: boolean = false;
  onToggle: (category: number) => void = (_category: number) => {};

  private softColor(): string {
    switch (this.category) {
      case GalleryCategory.Doujinshi:
        return '#F4E0C6';
      case GalleryCategory.Manga:
        return '#E5DFF5';
      case GalleryCategory.ArtistCg:
        return '#D8E9EF';
      case GalleryCategory.GameCg:
        return '#E9DEC8';
      case GalleryCategory.ImageSet:
        return '#D8EADF';
      case GalleryCategory.Cosplay:
        return '#F1D8E1';
      case GalleryCategory.AsianPorn:
        return '#ECDCCD';
      case GalleryCategory.NonH:
        return '#DDE8F2';
      case GalleryCategory.Western:
        return '#E0E8D2';
      case GalleryCategory.Misc:
        return '#E5E7EB';
      default:
        return themeSurfaceVariant();
    }
  }

  build() {
    Button(uiText(this.label))
      .height(32)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.selected ? themeOnPrimaryText() : categoryColor(this.category))
      .backgroundColor(this.selected ? categoryColor(this.category) : this.softColor())
      .borderRadius(4)
      .layoutWeight(1)
      .onClick(() => {
        this.onToggle(this.category);
      })
  }
}

@Component
export struct RatingStarBar {
  @Prop level: number = 1;
  onSelect: (level: number) => void = (_level: number) => {};

  private starActive(index: number): boolean {
    return index <= this.level;
  }

  private labelText(): string {
    return this.level <= 1 ? 'No rating limit' : this.level.toString() + ' stars and up';
  }
  build() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        ForEach([1, 2, 3, 4, 5], (index: number) => {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph(this.starActive(index) ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
              .fontSize(22)
              .fontColor([this.starActive(index) ? '#D28A1E' : '#9AA8B4'])
          }
          .width(36)
          .height(36)
          .backgroundColor(this.starActive(index) ? '#6E521F' : themeSurfaceVariant())
          .onClick(() => {
            this.onSelect(index);
          })
        }, (index: number) => index.toString())
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      Text(uiText(this.labelText()))
        .fontSize(13)
        .fontColor(themeSecondaryText())
        .maxLines(1)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
