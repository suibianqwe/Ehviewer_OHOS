import { ALL_CATEGORY, GalleryCategory, GalleryRoute } from '../model/GalleryModels';
import { DEFAULT_ADVANCE_SEARCH, ListMode } from '../services/EhUrl';
import { APP_THEME_COLOR, LANGUAGE_REVISION_KEY, categoryColor, categoryName, themeSurfaceColor, uiText } from '../shared/EhShared';

interface SearchSuggestionItem {
  kind: string;
  title: string;
  subtitle: string;
  query: string;
}

interface GalleryUrlMatch {
  gid: number;
  token: string;
}

interface SearchCategoryOption {
  label: string;
  category: number;
}

const searchHistoryKeywords: string[] = [];

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

@Component
export struct GallerySearchScene {
  @Prop initialKeyword: string = '';
  @Prop initialMode: ListMode = ListMode.Normal;
  @Prop initialCategory: number = GalleryCategory.None;
  @Prop initialAdvancedEnabled: boolean = false;
  @Prop initialAdvanceSearch: number = DEFAULT_ADVANCE_SEARCH;
  @Prop initialMinRating: number = -1;
  @Prop initialPageFrom: number = -1;
  @Prop initialPageTo: number = -1;
  @Prop sourceRoute: GalleryRoute = GalleryRoute.Home;
  @Prop filterActive: boolean = false;
  onBack: () => void = () => {};
  onOpenGalleryUrl: (gid: number, token: string) => void = (_gid: number, _token: string) => {};
  onOpenPageUrl: (pageUrl: string) => void = (_pageUrl: string) => {};
  onApply: (keyword: string, mode: ListMode, category: number, advancedEnabled: boolean, flags: number,
    minRating: number, pageFrom: number, pageTo: number) => void =
    (_keyword: string, _mode: ListMode, _category: number, _advancedEnabled: boolean, _flags: number,
      _minRating: number, _pageFrom: number, _pageTo: number) => {};

  @State keywordDraft: string = '';
  @State modeDraft: ListMode = ListMode.Normal;
  @State categoryDraft: number = GalleryCategory.None;
  @State advancedEnabledDraft: boolean = false;
  @State advanceSearchDraft: number = DEFAULT_ADVANCE_SEARCH;
  @State minRatingDraft: number = -1;
  @State pageFromDraft: number = -1;
  @State pageToDraft: number = -1;
  @State advancedPanelVisible: boolean = false;
  @State suggestions: SearchSuggestionItem[] = [];
  @StorageProp('statusBarHeight') statusBarHeightPx: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  aboutToAppear(): void {
    this.keywordDraft = this.initialKeyword;
    this.modeDraft = this.initialMode;
    this.categoryDraft = this.initialCategory;
    this.advancedEnabledDraft = this.initialAdvancedEnabled;
    this.advanceSearchDraft = this.initialAdvanceSearch;
    this.minRatingDraft = this.initialMinRating;
    this.pageFromDraft = this.initialPageFrom;
    this.pageToDraft = this.initialPageTo;
    this.refreshSuggestions();
  }

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  private submitSearch(): void {
    this.advancedPanelVisible = false;
    this.onApply(this.keywordDraft, this.modeDraft, this.categoryDraft, this.advancedEnabledDraft,
      this.advanceSearchDraft, this.minRatingDraft, this.pageFromDraft, this.pageToDraft);
  }

  private refreshSuggestions(): void {
    const text = this.keywordDraft.trim();
    const next: SearchSuggestionItem[] = [];
    if (text.length > 0) {
      next.push({
        kind: 'search',
        title: 'Search current text',
        subtitle: text,
        query: text
      });
      next.push({
        kind: 'tag',
        title: 'Specify tag',
        subtitle: text,
        query: text
      });
      next.push({
        kind: 'uploader',
        title: 'Specify uploader',
        subtitle: text,
        query: text
      });
    }
    const galleryUrl = this.parseGalleryUrl(text);
    if (galleryUrl !== null) {
      next.push({
        kind: 'gallery',
        title: 'Open gallery',
        subtitle: galleryUrl.gid.toString() + ' / ' + galleryUrl.token,
        query: text
      });
    }
    const pageUrl = this.parsePageUrl(text);
    if (pageUrl.length > 0) {
      next.push({
        kind: 'page',
        title: 'Open page',
        subtitle: pageUrl,
        query: text
      });
    }
    for (let i = 0; i < searchHistoryKeywords.length && next.length < 10; i++) {
      const history = searchHistoryKeywords[i];
      if (text.length === 0 || history.toLowerCase().indexOf(text.toLowerCase()) >= 0) {
        next.push({
          kind: 'history',
          title: history,
          subtitle: 'Search history',
          query: history
        });
      }
    }
    this.suggestions = next;
  }

  private parseGalleryUrl(text: string): GalleryUrlMatch | null {
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

  private parsePageUrl(text: string): string {
    const match = text.match(/https?:\/\/(?:exhentai\.org|e-hentai\.org)\/s\/[A-Za-z0-9]+\/\d+-\d+/);
    return match === null ? '' : match[0];
  }

  private applySuggestion(suggestion: SearchSuggestionItem): void {
    if (suggestion.kind === 'search') {
      this.keywordDraft = suggestion.query;
      this.submitSearch();
      return;
    }
    if (suggestion.kind === 'tag') {
      this.keywordDraft = suggestion.query;
      this.modeDraft = ListMode.Tag;
      this.refreshSuggestions();
      return;
    }
    if (suggestion.kind === 'uploader') {
      this.keywordDraft = suggestion.query;
      this.modeDraft = ListMode.Uploader;
      this.refreshSuggestions();
      return;
    }
    if (suggestion.kind === 'gallery') {
      const galleryUrl = this.parseGalleryUrl(suggestion.query);
      if (galleryUrl !== null) {
        this.onOpenGalleryUrl(galleryUrl.gid, galleryUrl.token);
      }
      return;
    }
    if (suggestion.kind === 'page') {
      const pageUrl = this.parsePageUrl(suggestion.query);
      if (pageUrl.length > 0) {
        this.onOpenPageUrl(pageUrl);
      }
      return;
    }
    this.keywordDraft = suggestion.query;
    this.refreshSuggestions();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Column()
          .height(this.statusBarVp())
          .width('100%')
          .backgroundColor(APP_THEME_COLOR)

        Row({ space: 8 }) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(22)
              .fontColor([Color.White])
          }
          .width(40)
          .height(40)
          .backgroundColor('rgba(255,255,255,0.14)')
          .flexShrink(0)
          .onClick(() => {
            this.onBack();
          })

          TextInput({ text: this.keywordDraft, placeholder: uiText('Search galleries') })
            .height(38)
            .layoutWeight(1)
            .backgroundColor(themeSurfaceColor())
            .borderRadius(19)
            .placeholderColor('#5D7183')
            .fontColor('#17202A')
            .caretColor(APP_THEME_COLOR)
            .padding({ left: 16, right: 16 })
            .onChange((value: string) => {
              this.keywordDraft = value;
              this.refreshSuggestions();
            })
            .onSubmit(() => {
              this.submitSearch();
            })

          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(20)
              .fontColor([Color.White])
          }
          .width(40)
          .height(40)
          .backgroundColor(this.advancedPanelVisible || this.advancedEnabledDraft ? 'rgba(255,255,255,0.28)' :
            'rgba(255,255,255,0.14)')
          .flexShrink(0)
          .onClick(() => {
            this.advancedPanelVisible = !this.advancedPanelVisible;
          })
        }
        .width('100%')
        .height(56)
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor(APP_THEME_COLOR)

        Column() {
          SearchSummaryStrip({
            mode: this.modeDraft,
            category: this.categoryDraft,
            advancedEnabled: this.advancedEnabledDraft,
            filterActive: this.filterActive
          })
          if (this.suggestions.length > 0) {
            SearchSuggestionList({
              suggestions: this.suggestions,
              onSelect: (suggestion: SearchSuggestionItem) => {
                this.applySuggestion(suggestion);
              }
            })
              .margin({ top: 10 })
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12 })
        .layoutWeight(1)
        .backgroundColor($r('app.color.page_background'))
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      if (this.advancedPanelVisible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.18)')
          .onClick(() => {
            this.advancedPanelVisible = false;
          })

        SearchAdvancedPanel({
          searchModeValue: this.modeDraft,
          searchCategory: this.categoryDraft,
          advancedSearchEnabled: this.advancedEnabledDraft,
          advanceSearch: this.advanceSearchDraft,
          minRating: this.minRatingDraft,
          pageFrom: this.pageFromDraft,
          pageTo: this.pageToDraft,
          onSearchModeChange: (mode: ListMode) => {
            this.modeDraft = mode;
          },
          onSearchCategoryChange: (category: number) => {
            this.categoryDraft = category;
          },
          onAdvancedEnabledChange: (enabled: boolean) => {
            this.advancedEnabledDraft = enabled;
          },
          onAdvanceSearchChange: (flags: number) => {
            this.advanceSearchDraft = flags;
          },
          onMinRatingChange: (rating: number) => {
            this.minRatingDraft = rating;
          },
          onPageFromChange: (value: number) => {
            this.pageFromDraft = value;
          },
          onPageToChange: (value: number) => {
            this.pageToDraft = value;
          },
          onClose: () => {
            this.advancedPanelVisible = false;
          },
          onSearch: () => {
            this.submitSearch();
          }
        })
          .margin({ top: this.statusBarVp() + 62, left: 10, right: 10 })
          .transition(TransitionEffect.move(TransitionEdge.TOP)
            .animation({ duration: 180, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}

@Component
export struct SearchSummaryStrip {
  @Prop mode: ListMode = ListMode.Normal;
  @Prop category: number = GalleryCategory.None;
  @Prop advancedEnabled: boolean = false;
  @Prop filterActive: boolean = false;

  private modeLabel(): string {
    if (this.mode === ListMode.Subscription) {
      return 'Subscription';
    }
    if (this.mode === ListMode.Uploader) {
      return 'Uploader';
    }
    if (this.mode === ListMode.Tag) {
      return 'Tag';
    }
    return 'Normal';
  }

  build() {
    Row({ space: 8 }) {
      SearchStatusChip({ label: this.modeLabel(), isActive: true })
      SearchStatusChip({ label: this.categoryLabel(), isActive: false })
      if (this.advancedEnabled) {
        SearchStatusChip({ label: 'Advanced', isActive: true })
      }
      if (this.filterActive) {
        SearchStatusChip({ label: 'Filter', isActive: true })
      }
    }
    .width('100%')
    .height(34)
    .alignItems(VerticalAlign.Center)
  }

  private categoryLabel(): string {
    if (this.category === GalleryCategory.None || this.category === ALL_CATEGORY) {
      return 'All categories';
    }
    if (this.category === 0) {
      return 'No categories';
    }
    return categoryName(this.category);
  }
}

@Component
export struct SearchSuggestionList {
  @Prop suggestions: SearchSuggestionItem[] = [];
  onSelect: (suggestion: SearchSuggestionItem) => void = (_suggestion: SearchSuggestionItem) => {};

  private iconForKind(kind: string): Resource {
    if (kind === 'gallery' || kind === 'page') {
      return $r('sys.symbol.doc_plaintext');
    }
    if (kind === 'tag') {
      return $r('sys.symbol.star');
    }
    if (kind === 'uploader') {
      return $r('sys.symbol.open_sidebar');
    }
    if (kind === 'search') {
      return $r('sys.symbol.magnifyingglass');
    }
    return $r('sys.symbol.clock');
  }

  private tintForKind(kind: string): string {
    if (kind === 'gallery' || kind === 'page') {
      return APP_THEME_COLOR;
    }
    return '#6B7C8C';
  }

  build() {
    Column() {
      ForEach(this.suggestions, (suggestion: SearchSuggestionItem, index: number) => {
        Column() {
          Row({ space: 10 }) {
            SymbolGlyph(this.iconForKind(suggestion.kind))
              .fontSize(18)
              .fontColor([this.tintForKind(suggestion.kind)])
              .width(24)
            Column({ space: 2 }) {
              Text(uiText(suggestion.title))
                .fontSize(14)
                .fontColor('#17202A')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (suggestion.subtitle.length > 0) {
                Text(uiText(suggestion.subtitle))
                  .fontSize(11)
                  .fontColor('#667085')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .height(50)
          .padding({ left: 8, right: 8 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.onSelect(suggestion);
          })

          if (index < this.suggestions.length - 1) {
            Divider()
              .strokeWidth(1)
              .color('#E2E8EE')
              .margin({ left: 42 })
          }
        }
      }, (suggestion: SearchSuggestionItem) => suggestion.kind + ':' + suggestion.query)
    }
    .width('100%')
    .backgroundColor(Color.White)
    .borderRadius(6)
    .shadow({ radius: 6, color: '#16000000', offsetX: 0, offsetY: 2 })
  }
}

@Component
export struct SearchStatusChip {
  label: string = '';
  isActive: boolean = false;

  build() {
    Text(uiText(this.label))
      .fontSize(12)
      .fontColor(this.isActive ? Color.White : '#40566F')
      .backgroundColor(this.isActive ? APP_THEME_COLOR : '#E7EEF3')
      .borderRadius(4)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
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
  onSearchModeChange: (mode: ListMode) => void = (_mode: ListMode) => {};
  onSearchCategoryChange: (category: number) => void = (_category: number) => {};
  onAdvancedEnabledChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onAdvanceSearchChange: (flags: number) => void = (_flags: number) => {};
  onMinRatingChange: (rating: number) => void = (_rating: number) => {};
  onPageFromChange: (value: number) => void = (_value: number) => {};
  onPageToChange: (value: number) => void = (_value: number) => {};
  onClose: () => void = () => {};
  onSearch: () => void = () => {};

  private searchModeOptions(): SelectOption[] {
    return [
      { value: uiText('一般搜索') },
      { value: uiText('订阅搜索') },
      { value: uiText('指定上传者') },
      { value: uiText('标签搜索') }
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
    if (this.searchModeValue === ListMode.Subscription) {
      return 1;
    }
    if (this.searchModeValue === ListMode.Uploader) {
      return 2;
    }
    if (this.searchModeValue === ListMode.Tag) {
      return 3;
    }
    return 0;
  }

  private selectedCategoryMask(): number {
    if (this.searchCategory === GalleryCategory.None) {
      return ALL_CATEGORY;
    }
    return this.searchCategory & ALL_CATEGORY;
  }

  private allCategoriesSelected(): boolean {
    return this.selectedCategoryMask() === ALL_CATEGORY;
  }

  private categorySelected(category: number): boolean {
    return (this.selectedCategoryMask() & category) !== 0;
  }

  private emitCategoryMask(mask: number): void {
    this.onSearchCategoryChange(mask === ALL_CATEGORY ? GalleryCategory.None : mask);
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
    if (this.minRating <= 0) {
      return 1;
    }
    return Math.max(1, Math.min(5, this.minRating));
  }

  private setRatingLevel(level: number): void {
    this.onMinRatingChange(level <= 1 ? -1 : level);
  }

  private flagOn(flag: number): boolean {
    return (this.advanceSearch & flag) !== 0;
  }

  private setFlag(flag: number, enabled: boolean): void {
    const next = enabled ? (this.advanceSearch | flag) : (this.advanceSearch & ~flag);
    this.onAdvanceSearchChange(next);
  }

  @Builder
  private sectionTitle(title: string) {
    Text(uiText(title))
      .fontSize(12)
      .fontColor('#667085')
      .fontWeight(FontWeight.Medium)
      .margin({ top: 4 })
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 10 }) {
          Row() {
            Select(this.searchModeOptions())
              .selected(this.searchModeIndex())
              .height(38)
              .width('100%')
              .onSelect((index: number) => {
                this.onSearchModeChange(this.modeForIndex(index));
              })
          }
          .width('100%')

          this.sectionTitle('Categories')
          Button(uiText('All categories'))
            .height(32)
            .fontSize(12)
            .fontColor(this.allCategoriesSelected() ? Color.White : '#40566F')
            .backgroundColor(this.allCategoriesSelected() ? APP_THEME_COLOR : '#EEF2F6')
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
              .fontColor('#17202A')
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.advancedSearchEnabled })
              .onChange((isOn: boolean) => {
                this.onAdvancedEnabledChange(isOn);
              })
          }
          .width('100%')
          .height(42)
          .padding({ left: 10, right: 10 })
          .backgroundColor('#F3F6F8')
          .borderRadius(6)

          if (this.advancedSearchEnabled) {
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

      Button(uiText('Search'))
        .height(40)
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor(APP_THEME_COLOR)
        .borderRadius(4)
        .width('100%')
        .margin({ left: 12, right: 12, bottom: 12 })
        .onClick(() => {
          this.onSearch();
        })
    }
    .width('100%')
    .backgroundColor(Color.White)
    .borderRadius(8)
    .shadow({ radius: 12, color: '#33000000', offsetX: 0, offsetY: 4 })
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

  build() {
    Column() {
      if (this.expanded) {
        Column({ space: 8 }) {
          ActionBubble({
            label: this.filterActive ? uiText('Filter On') : uiText('Filter'),
            symbolIcon: $r('sys.symbol.magnifyingglass'),
            isEnabled: true,
            onTapAction: () => {
              this.onFilter();
            }
          })
          ActionBubble({
            label: uiText('Jump'),
            symbolIcon: $r('sys.symbol.chevron_forward'),
            isEnabled: this.canJump,
            onTapAction: () => {
              this.onJump();
            }
          })
          ActionBubble({
            label: uiText('Refresh'),
            symbolIcon: $r('sys.symbol.play_arrow_triangle_2_circlepath'),
            isEnabled: true,
            onTapAction: () => {
              this.onRefresh();
            }
          })
          ActionBubble({
            label: uiText('Random'),
            symbolIcon: $r('sys.symbol.play_fill'),
            isEnabled: this.canRandom,
            onTapAction: () => {
              this.onRandom();
            }
          })
        }
        .alignItems(HorizontalAlign.End)
        .margin({ bottom: 10 })
      }

      ActionBubble({
        label: '',
        symbolIcon: this.expanded ? $r('sys.symbol.xmark') : $r('sys.symbol.more'),
        isEnabled: true,
        primary: true,
        onTapAction: () => {
          this.onToggle();
        }
      })
    }
    .alignItems(HorizontalAlign.End)
  }
}

@Component
export struct ActionBubble {
  @Prop label: string = '';
  @Prop symbolIcon: Resource = $r('sys.symbol.plus');
  @Prop isEnabled: boolean = true;
  primary: boolean = false;
  onTapAction: () => void = () => {};

  build() {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph(this.symbolIcon)
          .fontSize(this.primary ? 26 : 20)
          .fontColor([this.isEnabled ? Color.White : '#A0BFCC'])
      }
      .width(this.primary ? 54 : 44)
      .height(this.primary ? 54 : 44)
      .enabled(this.isEnabled)
      .backgroundColor(this.isEnabled ? (this.primary ? '#2F6F8F' : '#5A8FA8') : '#A8C0CC')
      .shadow({ radius: this.primary ? 14 : 8, color: '#33000000', offsetX: 0, offsetY: 3 })
      .onClick(() => {
        this.onTapAction();
      })

      if (!this.primary && this.label.length > 0) {
        Text(this.label)
          .fontSize(10)
          .fontColor('#2F6F8F')
          .textAlign(TextAlign.Center)
          .backgroundColor('#DEEAF2')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8)
          .maxLines(1)
      }
    }
    .alignItems(HorizontalAlign.Center)
  }
}

@Component
export struct SearchFlagChip {
  label: string = '';
  isOn: boolean = false;
  onToggle: (isOn: boolean) => void = (_isOn: boolean) => {};

  build() {
    Button(uiText(this.label))
      .height(30)
      .fontSize(11)
      .fontColor(this.isOn ? Color.White : '#40566F')
      .backgroundColor(this.isOn ? APP_THEME_COLOR : '#EEF2F6')
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
  selected: boolean = false;
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
        return '#EEF2F6';
    }
  }

  build() {
    Button(uiText(this.label))
      .height(32)
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.selected ? Color.White : categoryColor(this.category))
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
  level: number = 1;
  onSelect: (level: number) => void = (_level: number) => {};

  private starActive(index: number): boolean {
    return index <= this.level;
  }

  private labelText(): string {
    return this.level <= 1 ? '不限制' : this.level.toString() + ' 星以上';
  }

  build() {
    Row({ space: 8 }) {
      ForEach([1, 2, 3, 4, 5], (index: number) => {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph(this.starActive(index) ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
            .fontSize(22)
            .fontColor([this.starActive(index) ? '#D28A1E' : '#9AA8B4'])
        }
        .width(36)
        .height(36)
        .backgroundColor(this.starActive(index) ? '#FFF0D4' : '#EEF2F6')
        .onClick(() => {
          this.onSelect(index);
        })
      }, (index: number) => index.toString())
      Text(uiText(this.labelText()))
        .fontSize(12)
        .fontColor('#40566F')
        .layoutWeight(1)
        .maxLines(1)
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
  }
}
