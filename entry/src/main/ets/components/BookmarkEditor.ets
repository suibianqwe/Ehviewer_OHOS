import { GalleryCategory, GalleryRoute } from '../model/GalleryModels';
import { SearchBookmarkInfo } from '../services/EhBookmarkStore';
import { DEFAULT_ADVANCE_SEARCH, ListMode } from '../services/EhUrl';
import { LANGUAGE_REVISION_KEY, THEME_REVISION_KEY, uiText } from '../shared/EhShared';
import { themeFieldBackground, themeOnPrimaryText, themePrimaryColor, themePrimaryText,
  themeSecondaryText } from '../shared/EhTheme';
import { uiCapsuleButtonBackground, uiRadius, uiSearchFieldHeight, uiSwitchHeight,
  uiSwitchWidth } from '../shared/EhUiStyle';
import { SearchAdvancedPanel } from './GallerySearchScenes';

@Component
export struct BookmarkEditor {
  @Prop bookmark: SearchBookmarkInfo = {
    id: '', name: '', mode: ListMode.Normal, category: GalleryCategory.None, keyword: '',
    advanceSearch: -1, minRating: -1, pageFrom: -1, pageTo: -1,
    filterEnabled: true, location: GalleryRoute.Home, time: 0
  };
  @Prop editing: boolean = false;
  @State nameDraft: string = '';
  @State keywordDraft: string = '';
  @State modeDraft: ListMode = ListMode.Normal;
  @State categoryDraft: number = GalleryCategory.None;
  @State advancedEnabledDraft: boolean = false;
  @State flagsDraft: number = DEFAULT_ADVANCE_SEARCH;
  @State filterEnabledDraft: boolean = true;
  @State minRatingDraft: number = -1;
  @State pageFromDraft: number = -1;
  @State pageToDraft: number = -1;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp(THEME_REVISION_KEY) themeRevision: number = 0;
  onCancel: () => void = () => {};
  onSave: (bookmark: SearchBookmarkInfo) => void = (_bookmark: SearchBookmarkInfo) => {};

  aboutToAppear(): void {
    this.nameDraft = this.bookmark.name;
    this.keywordDraft = this.bookmark.keyword;
    this.modeDraft = this.bookmark.mode;
    this.categoryDraft = this.bookmark.category;
    this.advancedEnabledDraft = this.bookmark.advanceSearch >= 0 || this.bookmark.minRating !== -1 ||
      this.bookmark.pageFrom !== -1 || this.bookmark.pageTo !== -1;
    this.flagsDraft = this.bookmark.advanceSearch >= 0 ? this.bookmark.advanceSearch : DEFAULT_ADVANCE_SEARCH;
    this.filterEnabledDraft = this.bookmark.filterEnabled;
    this.minRatingDraft = this.bookmark.minRating;
    this.pageFromDraft = this.bookmark.pageFrom;
    this.pageToDraft = this.bookmark.pageTo;
  }

  private save(): void {
    // Keep edits local until Save; identity, ordering and origin are never replaced by the form.
    this.onSave({
      id: this.bookmark.id,
      name: this.nameDraft.trim(),
      keyword: this.keywordDraft,
      mode: this.modeDraft,
      category: this.categoryDraft,
      advanceSearch: this.advancedEnabledDraft ? this.flagsDraft : -1,
      minRating: this.advancedEnabledDraft ? this.minRatingDraft : -1,
      pageFrom: this.advancedEnabledDraft ? this.pageFromDraft : -1,
      pageTo: this.advancedEnabledDraft ? this.pageToDraft : -1,
      filterEnabled: this.filterEnabledDraft,
      location: this.bookmark.location,
      time: this.bookmark.time
    });
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text(uiText(this.editing ? 'Edit bookmark' : 'Add bookmark'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .layoutWeight(1)
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([themePrimaryText()])
        }
        .width(38)
        .height(38)
        .backgroundColor(uiCapsuleButtonBackground())
        .onClick(() => this.onCancel())
      }
      .width('100%')
      .flexShrink(0)

      Scroll() {
        Column({ space: 10 }) {
          TextInput({ text: this.nameDraft, placeholder: uiText('Bookmark name') })
            .height(uiSearchFieldHeight())
            .width('100%')
            .fontSize(15)
            .fontColor(themePrimaryText())
            .placeholderColor(themeSecondaryText())
            .backgroundColor(themeFieldBackground())
            .padding({ left: 12, right: 12 })
            .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
            .onChange((value: string) => { this.nameDraft = value; })
          TextInput({ text: this.keywordDraft, placeholder: uiText('Search keyword') })
            .height(uiSearchFieldHeight())
            .width('100%')
            .fontSize(15)
            .fontColor(themePrimaryText())
            .placeholderColor(themeSecondaryText())
            .backgroundColor(themeFieldBackground())
            .padding({ left: 12, right: 12 })
            .borderRadius(uiRadius(uiSearchFieldHeight() / 2))
            .onChange((value: string) => { this.keywordDraft = value; })

          Row() {
            Text(uiText('Filter'))
              .fontSize(14)
              .fontColor(themePrimaryText())
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.filterEnabledDraft })
              .width(uiSwitchWidth())
              .height(uiSwitchHeight())
              .selectedColor(themePrimaryColor())
              .switchPointColor(Color.White)
              .onChange((enabled: boolean) => { this.filterEnabledDraft = enabled; })
          }
          .width('100%')
          .height(42)
          .padding({ left: 12, right: 12 })
          .backgroundColor(uiCapsuleButtonBackground())
          .borderRadius(uiRadius(21))

          SearchAdvancedPanel({
            embedded: true,
            searchModeValue: this.modeDraft,
            searchCategory: this.categoryDraft,
            advancedSearchEnabled: this.advancedEnabledDraft,
            advanceSearch: this.flagsDraft,
            searchFilterEnabled: this.filterEnabledDraft,
            minRating: this.minRatingDraft,
            pageFrom: this.pageFromDraft,
            pageTo: this.pageToDraft,
            onSearchModeChange: (mode: ListMode) => { this.modeDraft = mode; },
            onSearchCategoryChange: (category: number) => { this.categoryDraft = category; },
            onAdvancedEnabledChange: (enabled: boolean) => { this.advancedEnabledDraft = enabled; },
            onAdvanceSearchChange: (flags: number) => { this.flagsDraft = flags; },
            onMinRatingChange: (rating: number) => { this.minRatingDraft = rating; },
            onPageFromChange: (value: number) => { this.pageFromDraft = value; },
            onPageToChange: (value: number) => { this.pageToDraft = value; }
          })
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .clip(true)

      Row({ space: 10 }) {
        Button(uiText('Cancel'), { type: ButtonType.Capsule })
          .height(40)
          .layoutWeight(1)
          .fontSize(14)
          .fontColor(themePrimaryText())
          .backgroundColor(uiCapsuleButtonBackground())
          .onClick(() => this.onCancel())
        Button(uiText(this.editing ? 'Update' : 'Save'), { type: ButtonType.Capsule })
          .height(40)
          .layoutWeight(1)
          .fontSize(14)
          .fontColor(themeOnPrimaryText())
          .backgroundColor(themePrimaryColor())
          .enabled(this.nameDraft.trim().length > 0)
          .onClick(() => this.save())
      }
      .width('100%')
      .flexShrink(0)
    }
    .width('100%')
    .height('100%')
  }
}
