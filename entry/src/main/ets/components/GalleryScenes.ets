import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { ALL_CATEGORY, GalleryCategory, GalleryDetail, GalleryInfo, GalleryRoute, GallerySite } from '../model/GalleryModels';
import { SearchBookmarkInfo, ehBookmarkStore } from '../services/EhBookmarkStore';
import { ehCookieStore } from '../services/EhCookieStore';
import {
  EhHttpClient,
  GalleryListLoadResult,
} from '../services/EhHttpClient';
import { DEFAULT_ADVANCE_SEARCH, EhUrl, FavListUrlBuilder, ListMode, ListUrlBuilder, buildJumpSeekUrl } from '../services/EhUrl';
import { ehFilterStore } from '../services/EhFilterStore';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehLocalFavoritesStore } from '../services/EhLocalFavoritesStore';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { ehTagTranslationStore } from '../services/EhTagTranslationStore';
import { DetailSearchRequest } from '../services/GalleryDetailActionSupport';
import {
  createGalleryDetailLink,
  createGalleryDetailLinkFromGallery,
  createEmptyGalleryDetailLink,
  GalleryDetailLink,
  initialDetailForLink
} from '../services/GalleryDetailModule';
import { FavoriteCategoryInfo } from '../services/GalleryListParser';
import { LocalGallerySearchOptions } from '../services/LocalGallerySearch';
import {
  applyAppChromeImmersiveMode,
  isEmbeddedReaderActive,
  leaveEmbeddedReaderFullscreen,
  mainContentWidthFallbackVp,
  rememberMainContentWidthVp
} from '../services/EhWindowImmersive';
import { LANGUAGE_REVISION_KEY, runDetailBackHandler } from '../shared/EhShared';
import {
  themeFieldBackground,
  themeDangerText,
  themeOnPrimaryActionBackground,
  themeOnPrimaryActionStrongBackground,
  themeOnPrimaryText,
  themePageBackground,
  themePlaceholderColor,
  themePrimaryColor,
  themePrimaryText,
  themeScrimColor,
  themeSecondaryText,
  themeSelectedBackground,
  themeSelectedBackgroundLight,
  themeSelectedText,
  themeShadowColor,
  themeSurface,
  themeSurfaceVariant,
  themeTertiaryText,
  themeTransparentColor
} from '../shared/EhTheme';
import { EhNavBar } from '../components/NavigationComponents';
import { CategoryBadge, GalleryListRow, GalleryThumb, GalleryThumbCard } from './GalleryCards';
import { GalleryDetailHostScene } from './GalleryDetailHostScene';
import { ReaderSessionScene } from './ReaderHostScene';
import {
  areaDimensionToVp,
  saveSplitPaneRatio,
  SPLIT_PANE_BREAKPOINT,
  SPLIT_PANE_RATIO_REVISION_KEY,
  splitPaneCurrentRatio,
  SplitPaneDivider,
  splitPaneListWidth,
  splitPaneModeEnabled,
  splitPaneRatioForWidth,
  splitPaneSideWidth,
  splitPaneWidthFromDrag
} from './SplitPaneSupport';
import {
  addSearchTagToken,
  buildSearchSuggestions,
  composeSearchKeywordWithInput,
  gallerySuggestionUrl,
  QuickActionColumn,
  removeSearchTagToken,
  SearchAdvancedPanel,
  SearchSuggestionItem,
  SearchSuggestionList,
  SearchSummaryStrip,
  searchKeywordForRequest,
  searchKeywordWithoutTagTokens,
  searchTagTokenLabel,
  searchTagTokens,
  recordSearchHistory
} from './GallerySearchScenes';
import {
  uiText,
  uiStatusText,
  setActiveBackHandler,
  createEmptyGallery,
  createEmptyDetail,
  cloneGalleryDetail,
  cloneGalleryInfos,
  cloneGalleryInfo,
  applyGalleryFilters,
  getAbilityContext,
  immersiveChromeHeightFromOffset,
  nextFloatingToolbarOffset,
  saveGalleryToHistory,
  listModeForRoute,
  routeUsesKeyword,
  defaultKeywordForRoute,
  gallerySearchTitle,
  effectiveListSite,
  galleryListFailureMessage,
  galleryListMode,
  categoryName,
  galleryDisplayTitle,
  galleryThumbWidth,
  galleryThumbHeight,
  toggleGalleryDownload,
  downloadButtonText,
  shouldShowTagTranslations
} from '../shared/EhShared';

export { CategoryBadge, GalleryListRow, GalleryTagChip, GalleryThumb, GalleryThumbCard } from './GalleryCards';

export { GalleryDetailOverlayScene, GalleryDetailScene } from './GalleryDetailScenes';

export { ActionBubble,
  QuickActionColumn,
  SearchAdvancedPanel,
  SearchFlagChip,
  SearchSuggestionList,
  SearchSummaryStrip } from './GallerySearchScenes';

export { CommentsScene,
  PlaceholderScene,
  ReaderNavButton,
  ReaderPageState,
  ReaderScene,
  ReaderToolButton } from './ReaderScenes';

interface GalleryListSceneCache {
  keyword: string;
  statusText: string;
  requestUrl: string;
  activeSite: GallerySite;
  pageIndex: number;
  totalPages: number;
  nextUrl: string;
  resultCount: string;
  galleries: GalleryInfo[];
  favoriteCat: number;
  favoriteCategories: FavoriteCategoryInfo[];
  hasFirstRefresh: boolean;
  filterActive: boolean;
  accountFilterEnabled: boolean;
  searchMode: ListMode;
  searchCategory: number;
  advancedSearchEnabled: boolean;
  advanceSearch: number;
  minRating: number;
  pageFrom: number;
  pageTo: number;
  imagePath?: string;
  imageUseSimilarityScan?: boolean;
  imageOnlySearchCovers?: boolean;
  imageShowExpunged?: boolean;
  searchFilterEnabled: boolean;
  searchAdvancedPanelOpened: boolean;
  searchSubmitted: boolean;
  listScrollOffset: number;
  appendExhausted?: boolean;
}

interface GalleryRowData {
  index: number;
  key: string;
  items: GalleryInfo[];
}

interface SearchResultDraft {
  keyword: string;
  mode: ListMode;
  category: number;
  advancedEnabled: boolean;
  advanceSearch: number;
  minRating: number;
  pageFrom: number;
  pageTo: number;
  filterActive: boolean;
  searchFilterEnabled: boolean;
  searchAdvancedPanelOpened: boolean;
  submitted: boolean;
  sourceRoute: GalleryRoute;
  imagePath: string;
  imageUseSimilarityScan: boolean;
  imageOnlySearchCovers: boolean;
  imageShowExpunged: boolean;
}

interface GalleryListNavigationCache {
  showSearchResultScene: boolean;
  searchResultDraft: SearchResultDraft;
  localSearchBarVisible: boolean;
  showDetail: boolean;
  restoreDetailWithFade: boolean;
  detailLink: GalleryDetailLink;
  detail: GalleryDetail;
  detailStatus: string;
  detailRequestUrl: string;
  detailScrollOffset: number;
  fabExpanded: boolean;
}

const galleryListSceneCache: Map<string, GalleryListSceneCache> = new Map();
const galleryListNavigationCache: Map<string, GalleryListNavigationCache> = new Map();
let recentFavoriteCat: number = FavListUrlBuilder.FAV_CAT_ALL;
const ACCOUNT_DEFAULT_FILTER_DISABLE_FLAGS: number = 0x100 | 0x200 | 0x400;
const IMAGE_SEARCH_FILE_SUFFIXES: string[] = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];

function createEmptySearchResultDraft(): SearchResultDraft {
  return {
    keyword: '',
    mode: ListMode.Normal,
    category: GalleryCategory.None,
    advancedEnabled: false,
    advanceSearch: DEFAULT_ADVANCE_SEARCH,
    minRating: -1,
    pageFrom: -1,
    pageTo: -1,
    filterActive: false,
    searchFilterEnabled: true,
    searchAdvancedPanelOpened: false,
    submitted: false,
    sourceRoute: GalleryRoute.Home,
    imagePath: '',
    imageUseSimilarityScan: false,
    imageOnlySearchCovers: false,
    imageShowExpunged: false
  };
}

function cloneSearchResultDraft(draft: SearchResultDraft): SearchResultDraft {
  return {
    keyword: draft.keyword,
    mode: draft.mode,
    category: draft.category,
    advancedEnabled: draft.advancedEnabled,
    advanceSearch: draft.advanceSearch,
    minRating: draft.minRating,
    pageFrom: draft.pageFrom,
    pageTo: draft.pageTo,
    filterActive: draft.filterActive,
    searchFilterEnabled: draft.searchFilterEnabled,
    searchAdvancedPanelOpened: draft.searchAdvancedPanelOpened,
    submitted: draft.submitted,
    sourceRoute: draft.sourceRoute,
    imagePath: draft.imagePath,
    imageUseSimilarityScan: draft.imageUseSimilarityScan,
    imageOnlySearchCovers: draft.imageOnlySearchCovers,
    imageShowExpunged: draft.imageShowExpunged
  };
}

function cloneFavoriteCategories(categories: FavoriteCategoryInfo[]): FavoriteCategoryInfo[] {
  const cloned: FavoriteCategoryInfo[] = [];
  for (let i = 0; i < categories.length; i++) {
    cloned.push({
      favCat: categories[i].favCat,
      name: categories[i].name,
      count: categories[i].count
    });
  }
  return cloned;
}

function mergeFavoriteGalleries(local: GalleryInfo[], remote: GalleryInfo[]): GalleryInfo[] {
  const merged: GalleryInfo[] = [];
  for (let i = 0; i < local.length; i++) {
    if (!galleryListHasGid(merged, local[i].gid)) {
      merged.push(cloneGalleryInfo(local[i]));
    }
  }
  for (let i = 0; i < remote.length; i++) {
    if (!galleryListHasGid(merged, remote[i].gid)) {
      merged.push(cloneGalleryInfo(remote[i]));
    }
  }
  return merged;
}

function galleryListHasGid(galleries: GalleryInfo[], gid: number): boolean {
  for (let i = 0; i < galleries.length; i++) {
    if (galleries[i].gid === gid) {
      return true;
    }
  }
  return false;
}

function mergedFavoriteResultCount(remoteText: string, localCount: number): string {
  const localText = localCount.toString() + ' local favorites';
  return remoteText.length > 0 ? remoteText + ' + ' + localText : localText;
}

function cloneGalleryDetailLink(link: GalleryDetailLink): GalleryDetailLink {
  return {
    gid: link.gid,
    token: link.token,
    url: link.url,
    referer: link.referer,
    site: link.site,
    seed: cloneGalleryInfo(link.seed)
  };
}

async function copyImageSearchSourceToCache(sourceUri: string): Promise<string> {
  const context = getAbilityContext();
  if (context === undefined || sourceUri.length === 0) {
    return '';
  }
  const targetPath = context.cacheDir + '/image_search_' + Date.now().toString() + imageSearchExtension(sourceUri);
  let sourceFd = -1;
  let targetFd = -1;
  try {
    const sourceFile = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
    sourceFd = sourceFile.fd;
    const stat = fs.statSync(sourceFd);
    const buffer = new ArrayBuffer(stat.size);
    fs.readSync(sourceFd, buffer);
    const targetFile = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    targetFd = targetFile.fd;
    fs.writeSync(targetFd, buffer);
    return targetPath;
  } catch (error) {
    return '';
  } finally {
    if (sourceFd >= 0) {
      try {
        fs.closeSync(sourceFd);
      } catch (error) {
      }
    }
    if (targetFd >= 0) {
      try {
        fs.closeSync(targetFd);
      } catch (error) {
      }
    }
  }
}

function imageSearchExtension(value: string): string {
  const lower = value.toLowerCase();
  const queryIndex = lower.indexOf('?');
  const clean = queryIndex >= 0 ? lower.substring(0, queryIndex) : lower;
  for (let i = 0; i < IMAGE_SEARCH_FILE_SUFFIXES.length; i++) {
    if (clean.endsWith(IMAGE_SEARCH_FILE_SUFFIXES[i])) {
      return IMAGE_SEARCH_FILE_SUFFIXES[i];
    }
  }
  return '.jpg';
}

function updateGalleryListScrollCache(key: string, offset: number): void {
  const cache = galleryListSceneCache.get(key);
  if (cache === undefined) {
    return;
  }
  cache.listScrollOffset = normalizeGalleryListScrollOffset(offset);
}

function normalizeGalleryListScrollOffset(offset: number): number {
  if (offset <= 1 || Number.isNaN(offset)) {
    return 0;
  }
  return offset;
}

export { HomeGalleryScene } from './HomeGalleryScene';

export { SubscriptionGalleryScene } from './SubscriptionGalleryScene';

export { HotGalleryScene } from './HotGalleryScene';

export { FavoriteGalleryScene } from './FavoriteGalleryScene';

interface FavoriteCategoryOption {
  favCat: number;
  name: string;
  count: number;
}

function favoriteCategoryOptions(categories: FavoriteCategoryInfo[], localFavoriteCount: number): FavoriteCategoryOption[] {
  const options: FavoriteCategoryOption[] = [];
  let total = 0;
  for (let i = 0; i < categories.length; i++) {
    total += Math.max(0, categories[i].count);
  }
  options.push({
    favCat: FavListUrlBuilder.FAV_CAT_LOCAL,
    name: 'Local Favorites',
    count: localFavoriteCount
  });
  options.push({
    favCat: FavListUrlBuilder.FAV_CAT_ALL,
    name: 'All favorites',
    count: categories.length > 0 || localFavoriteCount >= 0 ? total + Math.max(0, localFavoriteCount) : -1
  });
  for (let i = 0; i < 10; i++) {
    const parsed = findFavoriteCategory(i, categories);
    options.push({
      favCat: i,
      name: parsed === null ? 'Favorites ' + i.toString() : parsed.name,
      count: parsed === null ? -1 : parsed.count
    });
  }
  return options;
}

function findFavoriteCategory(favCat: number, categories: FavoriteCategoryInfo[]): FavoriteCategoryInfo | null {
  for (let i = 0; i < categories.length; i++) {
    if (categories[i].favCat === favCat) {
      return categories[i];
    }
  }
  return null;
}

function favoriteCategoryName(favCat: number, categories: FavoriteCategoryInfo[]): string {
  if (favCat === FavListUrlBuilder.FAV_CAT_ALL) {
    return 'Favourite';
  }
  if (favCat === FavListUrlBuilder.FAV_CAT_LOCAL) {
    return 'Local Favorites';
  }
  const parsed = findFavoriteCategory(favCat, categories);
  return parsed === null ? 'Favorites ' + favCat.toString() : parsed.name;
}

function favoriteCategoryCountText(count: number): string {
  return count >= 0 ? count.toString() : '';
}

@Component
export struct FavoriteCategoryDrawer {
  @Prop statusBarHeight: number = 0;
  @Prop selectedFavCat: number = FavListUrlBuilder.FAV_CAT_ALL;
  @Prop categories: FavoriteCategoryInfo[] = [];
  @Prop localFavoriteCount: number = -1;
  onSelect: (favCat: number) => void = (_favCat: number) => {};
  onClose: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  private options(): FavoriteCategoryOption[] {
    return favoriteCategoryOptions(this.categories, this.localFavoriteCount);
  }

  build() {
    Column() {
      Column()
        .width('100%')
        .height(this.statusBarHeight)
        .backgroundColor(themePrimaryColor())

      Row() {
        Text(uiText('Favorite folders'))
          .fontSize(19)
          .fontWeight(FontWeight.Medium)
          .fontColor(themeOnPrimaryText())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([themeOnPrimaryText()])
        }
        .width(40)
        .height(40)
        .backgroundColor(themeOnPrimaryActionBackground())
        .onClick(() => {
          this.onClose();
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 18, right: 12 })
      .backgroundColor(themePrimaryColor())
      .alignItems(VerticalAlign.Center)

      List() {
        ForEach(this.options(), (item: FavoriteCategoryOption) => {
          ListItem() {
            FavoriteCategoryDrawerRow({
              item: item,
              selected: item.favCat === this.selectedFavCat,
              onTap: () => {
                this.onSelect(item.favCat);
              }
            })
          }
          .reuseId('favorite-category-drawer-row')
        }, (item: FavoriteCategoryOption) => item.favCat.toString() + ':' + item.name + ':' + item.count.toString())
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .cachedCount(4)
    }
    .width(288)
    .height('100%')
    .backgroundColor(themeSurface())
  }
}

@Component
export struct FavoriteCategoryDrawerRow {
  item: FavoriteCategoryOption = { favCat: FavListUrlBuilder.FAV_CAT_ALL, name: 'All favorites', count: -1 };
  selected: boolean = false;
  onTap: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    Row() {
      Column() {
        SymbolGlyph(this.item.favCat === FavListUrlBuilder.FAV_CAT_ALL ? $r('sys.symbol.heart') : $r('sys.symbol.folder'))
          .fontSize(21)
          .fontColor([this.selected ? themeSelectedText() : themeSecondaryText()])
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius(10)
      .backgroundColor(this.selected ? themeSelectedBackgroundLight() : themeSurfaceVariant())

      Column() {
        Text(uiText(this.item.name))
          .fontSize(15)
          .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.selected ? themeSelectedText() : themePrimaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.item.count >= 0) {
          Text(favoriteCategoryCountText(this.item.count))
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })

      if (this.selected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([themeSelectedText()])
      }
    }
    .width('100%')
    .height(62)
    .padding({ left: 14, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.selected ? themeSelectedBackground() : themeTransparentColor())
    .onClick(() => {
      this.onTap();
    })
  }
}

function bookmarkModeLabel(mode: ListMode): string {
  if (mode === ListMode.Uploader) {
    return 'Specify uploader';
  }
  if (mode === ListMode.Tag) {
    return 'Specify tag';
  }
  if (mode === ListMode.Subscription) {
    return 'Subscription';
  }
  if (mode === ListMode.WhatsHot) {
    return 'Whats Hot';
  }
  if (mode === ListMode.Filter) {
    return 'Filter';
  }
  if (mode === ListMode.TopList) {
    return 'Toplists';
  }
  return 'General';
}

function bookmarkLocationLabel(route: GalleryRoute): string {
  if (route === GalleryRoute.Subscription) {
    return 'Subscription';
  }
  if (route === GalleryRoute.WhatsHot) {
    return 'Whats Hot';
  }
  return 'All site';
}

function bookmarkInputFocusId(id: string): string {
  return 'bookmark-input-' + id;
}

function bookmarkSummary(item: SearchBookmarkInfo): string {
  const parts: string[] = [uiText(bookmarkLocationLabel(item.location)), uiText(bookmarkModeLabel(item.mode))];
  if (item.keyword.length > 0) {
    parts.push(item.keyword);
  }
  if (item.category !== GalleryCategory.None) {
    parts.push('cat=' + item.category.toString());
  }
  if (item.advanceSearch !== -1 || item.minRating !== -1 || item.pageFrom !== -1 || item.pageTo !== -1) {
    parts.push(uiText('Advanced'));
  }
  if (!item.filterEnabled) {
    parts.push(uiText('Filter Off'));
  }
  return parts.join(' · ');
}

@Component
export struct SearchBookmarkDrawer {
  @Prop statusBarHeight: number = 0;
  @Prop bookmarks: SearchBookmarkInfo[] = [];
  onSelect: (bookmark: SearchBookmarkInfo) => void = (_bookmark: SearchBookmarkInfo) => {};
  onAdd: () => void = () => {};
  onDelete: (bookmark: SearchBookmarkInfo) => void = (_bookmark: SearchBookmarkInfo) => {};
  onSettings: () => void = () => {};
  onClose: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    Column() {
      Column()
        .width('100%')
        .height(this.statusBarHeight)
        .backgroundColor(themePrimaryColor())

      Row() {
        Text(uiText('Bookmarks'))
          .fontSize(19)
          .fontWeight(FontWeight.Medium)
          .fontColor(themeOnPrimaryText())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(20)
            .fontColor([themeOnPrimaryText()])
        }
        .width(40)
        .height(40)
        .backgroundColor(themeOnPrimaryActionBackground())
        .margin({ right: 6 })
        .onClick(() => {
          this.onSettings();
        })

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(20)
            .fontColor([themeOnPrimaryText()])
        }
        .width(40)
        .height(40)
        .backgroundColor(themeOnPrimaryActionBackground())
        .margin({ right: 6 })
        .onClick(() => {
          this.onAdd();
        })

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([themeOnPrimaryText()])
        }
        .width(40)
        .height(40)
        .backgroundColor(themeOnPrimaryActionBackground())
        .onClick(() => {
          this.onClose();
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 18, right: 12 })
      .backgroundColor(themePrimaryColor())
      .alignItems(VerticalAlign.Center)

      if (this.bookmarks.length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.bookmark'))
            .fontSize(34)
            .fontColor([themeTertiaryText()])
          Text(uiText('No bookmarks'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
          Text(uiText('Tap plus to bookmark the current gallery list'))
            .fontSize(13)
            .fontColor(themeSecondaryText())
            .textAlign(TextAlign.Center)
            .padding({ left: 22, right: 22 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.bookmarks, (item: SearchBookmarkInfo) => {
            ListItem() {
              SearchBookmarkDrawerRow({
                item: item,
                onTap: () => {
                  this.onSelect(item);
                },
                onDelete: () => {
                  this.onDelete(item);
                }
              })
            }
            .reuseId('search-bookmark-drawer-row')
          }, (item: SearchBookmarkInfo) => item.id + ':' + item.time.toString())
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .cachedCount(6)
      }
    }
    .width(288)
    .height('100%')
    .backgroundColor(themeSurface())
  }
}

@Component
export struct SearchBookmarkDrawerRow {
  item: SearchBookmarkInfo = {
    id: '',
    name: '',
    mode: ListMode.Normal,
    category: GalleryCategory.None,
    keyword: '',
    advanceSearch: -1,
    minRating: -1,
    pageFrom: -1,
    pageTo: -1,
    filterEnabled: true,
    location: GalleryRoute.Home,
    time: 0
  };
  onTap: () => void = () => {};
  onDelete: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    Row() {
      Column() {
        SymbolGlyph($r('sys.symbol.bookmark'))
          .fontSize(21)
          .fontColor([themePrimaryColor()])
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius(10)
      .backgroundColor(themeSelectedBackgroundLight())

      Column() {
        Text(this.item.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(bookmarkSummary(this.item))
          .fontSize(12)
          .fontColor(themeSecondaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .wordBreak(WordBreak.BREAK_ALL)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .onClick(() => {
        this.onTap();
      })

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(17)
          .fontColor([themeSecondaryText()])
      }
      .width(36)
      .height(36)
      .backgroundColor(themeSurfaceVariant())
      .margin({ left: 4 })
      .onClick(() => {
        this.onDelete();
      })
    }
    .width('100%')
    .height(60)
    .padding({ left: 14, right: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(themeTransparentColor())
  }
}

@Component
export struct SearchBookmarkManagerScene {
  @Prop bookmarks: SearchBookmarkInfo[] = [];
  @Prop statusBarHeight: number = 0;
  onBack: () => void = () => {};
  onRename: (bookmark: SearchBookmarkInfo, name: string) => void = (_bookmark: SearchBookmarkInfo, _name: string) => {};
  onMoveIndex: (from: number, to: number) => void = (_from: number, _to: number) => {};
  onDelete: (bookmark: SearchBookmarkInfo) => void = (_bookmark: SearchBookmarkInfo) => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @State editingBookmarkId: string = '';

  build() {
    Column() {
      Column()
        .width('100%')
        .height(this.statusBarHeight)
        .backgroundColor(themePrimaryColor())

      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([themeOnPrimaryText()])
        }
        .width(40)
        .height(40)
        .backgroundColor(themeOnPrimaryActionBackground())
        .onClick(() => {
          this.onBack();
        })

        Text(uiText('Bookmark settings'))
          .fontSize(19)
          .fontWeight(FontWeight.Medium)
          .fontColor(themeOnPrimaryText())
          .layoutWeight(1)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
      .backgroundColor(themePrimaryColor())
      .alignItems(VerticalAlign.Center)

      if (this.bookmarks.length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.bookmark'))
            .fontSize(34)
            .fontColor([themeTertiaryText()])
          Text(uiText('No bookmarks'))
            .fontSize(16)
            .fontColor(themeSecondaryText())
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 8 }) {
          ListItem() {
            Row()
              .height(0)
          }

          ForEach(this.bookmarks, (item: SearchBookmarkInfo, index: number) => {
            ListItem() {
              SearchBookmarkManagerRow({
                item: item,
                index: index,
                total: this.bookmarks.length,
                editing: this.editingBookmarkId === item.id,
                onStartEdit: (bookmark: SearchBookmarkInfo) => {
                  this.editingBookmarkId = bookmark.id;
                  const focusId = bookmarkInputFocusId(bookmark.id);
                  setTimeout(() => {
                    focusControl.requestFocus(focusId);
                  }, 0);
                },
                onFinishEdit: (bookmark: SearchBookmarkInfo) => {
                  if (this.editingBookmarkId === bookmark.id) {
                    this.editingBookmarkId = '';
                  }
                },
                onRename: (bookmark: SearchBookmarkInfo, name: string) => {
                  this.onRename(bookmark, name);
                },
                onDelete: (bookmark: SearchBookmarkInfo) => {
                  this.onDelete(bookmark);
                }
              })
            }
            .reuseId('search-bookmark-manager-row')
          }, (item: SearchBookmarkInfo) => item.id)
            .onMove((from: number, to: number) => {
              this.onMoveIndex(from, to);
            })

          ListItem() {
            Row()
              .height(0)
          }
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .padding({ left: 10, right: 10 })
        .clip(false)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}

@Component
export struct SearchBookmarkManagerRow {
  @Prop @Watch('onItemChanged') item: SearchBookmarkInfo = {
    id: '',
    name: '',
    mode: ListMode.Normal,
    category: GalleryCategory.None,
    keyword: '',
    advanceSearch: -1,
    minRating: -1,
    pageFrom: -1,
    pageTo: -1,
    filterEnabled: true,
    location: GalleryRoute.Home,
    time: 0
  };
  @Prop index: number = 0;
  @Prop total: number = 0;
  @Prop editing: boolean = false;
  onStartEdit: (bookmark: SearchBookmarkInfo) => void = (_bookmark: SearchBookmarkInfo) => {};
  onFinishEdit: (bookmark: SearchBookmarkInfo) => void = (_bookmark: SearchBookmarkInfo) => {};
  onRename: (bookmark: SearchBookmarkInfo, name: string) => void = (_bookmark: SearchBookmarkInfo, _name: string) => {};
  onDelete: (bookmark: SearchBookmarkInfo) => void = (_bookmark: SearchBookmarkInfo) => {};
  @State draftName: string = '';
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  aboutToAppear(): void {
    this.draftName = this.item.name;
  }

  onItemChanged(): void {
    this.draftName = this.item.name;
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Column() {
          Text('≡')
            .fontSize(22)
            .fontColor(themeSecondaryText())
        }
        .width(38)
        .height(38)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(themeSurfaceVariant())
        .borderRadius(19)

        if (this.editing) {
          TextInput({ text: this.draftName, placeholder: uiText('Bookmark name') })
            .id(bookmarkInputFocusId(this.item.id))
            .defaultFocus(true)
            .onAppear(() => {
              focusControl.requestFocus(bookmarkInputFocusId(this.item.id));
            })
            .height(38)
            .layoutWeight(1)
            .fontSize(14)
            .fontColor(themePrimaryText())
            .backgroundColor(themeFieldBackground())
            .borderRadius(8)
            .padding({ left: 10, right: 10 })
            .onChange((value: string) => {
              this.draftName = value;
              this.onRename(this.item, value);
            })
            .onSubmit(() => {
              this.onRename(this.item, this.draftName);
              this.onFinishEdit(this.item);
            })
            .onBlur(() => {
              this.onRename(this.item, this.draftName);
              this.onFinishEdit(this.item);
            })
        } else {
          Row() {
            Text(this.draftName.length > 0 ? this.draftName : uiText('Bookmark name'))
              .fontSize(14)
              .fontColor(this.draftName.length > 0 ? themePrimaryText() : themeSecondaryText())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .height(38)
          .layoutWeight(1)
          .padding({ left: 10, right: 10 })
          .backgroundColor(themeFieldBackground())
          .borderRadius(8)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.onStartEdit(this.item);
          })
        }

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(18)
            .fontColor([themeDangerText()])
        }
        .width(38)
        .height(38)
        .backgroundColor(themeSurfaceVariant())
        .onClick(() => {
          this.onDelete(this.item);
        })
      }
      .width('100%')

      Text(bookmarkSummary(this.item))
        .fontSize(12)
        .fontColor(themeSecondaryText())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

    }
    .width('100%')
    .padding(12)
    .backgroundColor(themeSurface())
    .borderRadius(8)
  }
}

@Component
export struct GalleryListScene {
  private client: EhHttpClient = new EhHttpClient();
  sceneTitle: string = 'Homepage';
  listMode: string = 'Search';
  sourceRoute: GalleryRoute = GalleryRoute.Home;
  follow: string = '';
  initialKeyword: string = '';
  initialSearchMode: ListMode = ListMode.Normal;
  initialSearchCategory: number = GalleryCategory.None;
  initialAdvancedSearchEnabled: boolean = false;
  initialAdvanceSearch: number = DEFAULT_ADVANCE_SEARCH;
  initialMinRating: number = -1;
  initialPageFrom: number = -1;
  initialPageTo: number = -1;
  initialSearchFilterEnabled: boolean = true;
  initialSearchSubmitted: boolean = false;
  initialSearchAdvancedPanelOpened: boolean = false;
  initialImagePath: string = '';
  initialImageUseSimilarityScan: boolean = false;
  initialImageOnlySearchCovers: boolean = false;
  initialImageShowExpunged: boolean = false;
  isSearchResultScene: boolean = false;
  @Prop @Watch('onResetVersionChanged') resetVersion: number = 0;
  useForcedMode: boolean = false;
  forcedMode: ListMode = ListMode.Normal;
  useLocalProvider: boolean = false;
  localPageSize: number = 25;
  localProvider: (keyword: string, pageIndex: number, pageSize: number,
    options: LocalGallerySearchOptions) => Promise<GalleryListLoadResult> =
    (_keyword: string, _pageIndex: number, _pageSize: number,
      _options: LocalGallerySearchOptions): Promise<GalleryListLoadResult> => {
      const result: GalleryListLoadResult = {
        ok: true,
        url: '',
        statusCode: 200,
        message: '',
        pages: 0,
        nextPage: -1,
        nextUrl: '',
        resultCount: '',
        galleries: []
      };
      return Promise.resolve(result);
    };
  onMenu: () => void = () => {
  };
  onBack: () => void = () => {
  };
  @State keyword: string = '';
  @State statusText: string = 'Loading galleries...';
  @State requestUrl: string = '';
  @State activeSite: GallerySite = GallerySite.E;
  @State pageIndex: number = 0;
  @State totalPages: number = 0;
  @State nextUrl: string = '';
  @State resultCount: string = '';
  @State galleries: GalleryInfo[] = [];
  @State favoriteCat: number = FavListUrlBuilder.FAV_CAT_ALL;
  @State favoriteCategories: FavoriteCategoryInfo[] = [];
  @State favoriteLocalCount: number = -1;
  @State hasFirstRefresh: boolean = false;
  @State scrollResetVersion: number = 0;
  @State fabExpanded: boolean = false;
  @State filterActive: boolean = false;
  @State accountFilterEnabled: boolean = true;
  @State searchFilterEnabled: boolean = true;
  @State showSearchResultScene: boolean = false;
  @State searchResultDraft: SearchResultDraft = createEmptySearchResultDraft();
  @State searchMode: ListMode = ListMode.Normal;
  @State searchCategory: number = GalleryCategory.None;
  @State searchAdvancedPanelOpened: boolean = false;
  @State localSearchBarVisible: boolean = false;
  @State advancedSearchEnabled: boolean = false;
  @State advanceSearch: number = DEFAULT_ADVANCE_SEARCH;
  @State minRating: number = -1;
  @State pageFrom: number = -1;
  @State pageTo: number = -1;
  @State imageSearchPath: string = '';
  @State imageSearchUseSimilarityScan: boolean = false;
  @State imageSearchOnlyCovers: boolean = false;
  @State imageSearchShowExpunged: boolean = false;
  @State searchSubmitted: boolean = false;
  @State showDetail: boolean = false;
  @State showReader: boolean = false;
  @State sceneContentWidth: number = 0;
  @State splitListRatio: number = splitPaneCurrentRatio();
  @State splitDragging: boolean = false;
  private splitDragStartWidth: number = 0;
  private readerClosing: boolean = false;
  @State restoreDetailWithFade: boolean = false;
  @State detailLink: GalleryDetailLink = createEmptyGalleryDetailLink();
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailStatus: string = 'Tap a gallery row to load detail';
  @State detailRequestUrl: string = '';
  @State cardActionVisible: boolean = false;
  @State cardActionGallery: GalleryInfo = createEmptyGallery();
  @State searchBookmarks: SearchBookmarkInfo[] = [];
  @State addBookmarkDialogVisible: boolean = false;
  @State showBookmarkManager: boolean = false;
  @State addBookmarkName: string = '';
  @State addBookmarkDraft: SearchBookmarkInfo = {
    id: '',
    name: '',
    mode: ListMode.Normal,
    category: GalleryCategory.None,
    keyword: '',
    advanceSearch: -1,
    minRating: -1,
    pageFrom: -1,
    pageTo: -1,
    filterEnabled: true,
    location: GalleryRoute.Home,
    time: 0
  };
  @State renderVersion: number = 0;
  @State isLoadingMore: boolean = false;
  @State appendExhausted: boolean = false;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeightPx: number = 0;
  @StorageProp(SPLIT_PANE_RATIO_REVISION_KEY) @Watch('onSplitPaneRatioRevisionChange') splitPaneRatioRevision: number = 0;
  private listScrollOffset: number = 0;
  private detailScrollOffset: number = 0;
  private navigationCacheSuppressed: boolean = false;

  private cacheKey(): string {
    const mode = this.useForcedMode ? this.forcedMode.toString() : listModeForRoute(this.sourceRoute).toString();
    if (this.useLocalProvider) {
      return this.sourceRoute.toString() + '|local|' + this.follow + '|' + this.initialKeyword + '|' +
        this.localPageSize.toString();
    }
    if (this.isSearchResultScene) {
      return this.sourceRoute.toString() + '|search-result|' + this.keyword + '|' + this.searchMode.toString() + '|' +
        this.searchCategory.toString() + '|' + (this.advancedSearchEnabled ? '1' : '0') + '|' +
        this.advanceSearch.toString() + '|' + this.minRating.toString() + '|' +
        this.imageSearchPath + '|' + (this.imageSearchUseSimilarityScan ? 'sim' : 'nosim') + '|' +
        (this.imageSearchOnlyCovers ? 'covers' : 'all') + '|' +
        (this.imageSearchShowExpunged ? 'exp' : 'noexp') + '|' +
        (this.accountFilterEnabled ? 'account-filter-on' : 'account-filter-off') + '|' +
        (this.searchFilterEnabled ? 'search-filter-on' : 'search-filter-off') + '|' +
        (this.searchAdvancedPanelOpened ? 'advanced-panel-opened' : 'advanced-panel-closed');
    }
    return this.sourceRoute.toString() + '|' + mode + '|' + this.follow + '|' + this.initialKeyword + '|' +
      this.initialSearchMode.toString() + '|' + this.initialSearchCategory.toString() + '|' +
      (this.initialAdvancedSearchEnabled ? '1' : '0') + '|' + this.initialAdvanceSearch.toString() + '|' +
      this.initialMinRating.toString() + '|' + this.initialPageFrom.toString() + '|' + this.initialPageTo.toString() +
      '|' + (this.accountFilterEnabled ? 'account-filter-on' : 'account-filter-off') + '|favcat=' +
      (this.sourceRoute === GalleryRoute.Favorites ? this.favoriteCat.toString() : 'na');
  }

  private navigationCacheKey(): string {
    const mode = this.useForcedMode ? this.forcedMode.toString() : listModeForRoute(this.sourceRoute).toString();
    return this.sourceRoute.toString() + '|' + this.listMode + '|' + mode + '|' + this.follow + '|' +
      this.initialKeyword + '|' + (this.isSearchResultScene ? 'search-result' : 'root') + '|' +
      (this.useLocalProvider ? 'local' : 'remote') + '|favcat=' +
      (this.sourceRoute === GalleryRoute.Favorites ? this.favoriteCat.toString() : 'na');
  }

  private restoreListCache(): boolean {
    if (this.isSearchResultScene) {
      return false;
    }
    const cache = galleryListSceneCache.get(this.cacheKey());
    if (cache === undefined) {
      return false;
    }
    this.keyword = cache.keyword;
    this.statusText = cache.statusText;
    this.requestUrl = cache.requestUrl;
    this.activeSite = cache.activeSite;
    this.pageIndex = cache.pageIndex;
    this.totalPages = cache.totalPages;
    this.nextUrl = cache.nextUrl;
    this.resultCount = cache.resultCount;
    this.galleries = cloneGalleryInfos(cache.galleries);
    this.favoriteCat = cache.favoriteCat;
    this.favoriteCategories = cloneFavoriteCategories(cache.favoriteCategories);
    this.hasFirstRefresh = cache.hasFirstRefresh;
    this.filterActive = this.isSearchResultScene ? false : cache.filterActive;
    this.accountFilterEnabled = cache.accountFilterEnabled !== false;
    this.searchFilterEnabled = cache.searchFilterEnabled !== false;
    this.searchAdvancedPanelOpened = cache.searchAdvancedPanelOpened === true;
    this.localSearchBarVisible = this.useLocalProvider && cache.searchSubmitted !== true;
    this.searchMode = cache.searchMode;
    this.searchCategory = cache.searchCategory;
    this.advancedSearchEnabled = cache.advancedSearchEnabled;
    this.advanceSearch = cache.advanceSearch;
    this.minRating = cache.minRating;
    this.pageFrom = cache.pageFrom;
    this.pageTo = cache.pageTo;
    this.imageSearchPath = cache.imagePath === undefined ? '' : cache.imagePath;
    this.imageSearchUseSimilarityScan = cache.imageUseSimilarityScan === true;
    this.imageSearchOnlyCovers = cache.imageOnlySearchCovers === true;
    this.imageSearchShowExpunged = cache.imageShowExpunged === true;
    this.searchSubmitted = cache.searchSubmitted === true;
    this.listScrollOffset = cache.listScrollOffset;
    this.appendExhausted = cache.appendExhausted === true;
    return true;
  }

  private restoreNavigationCache(): void {
    const cache = galleryListNavigationCache.get(this.navigationCacheKey());
    if (cache === undefined) {
      return;
    }
    this.showSearchResultScene = this.isSearchResultScene ? false : cache.showSearchResultScene;
    this.searchResultDraft = this.isSearchResultScene ? createEmptySearchResultDraft() :
      cloneSearchResultDraft(cache.searchResultDraft);
    this.localSearchBarVisible = cache.localSearchBarVisible;
    this.showDetail = cache.showDetail;
    this.restoreDetailWithFade = cache.restoreDetailWithFade;
    this.detailLink = cloneGalleryDetailLink(cache.detailLink);
    this.detail = cloneGalleryDetail(cache.detail);
    this.detailStatus = cache.detailStatus;
    this.detailRequestUrl = cache.detailRequestUrl;
    this.detailScrollOffset = cache.detailScrollOffset;
    this.fabExpanded = cache.fabExpanded;
  }

  private saveListCache(): void {
    galleryListSceneCache.set(this.cacheKey(), {
      keyword: this.keyword,
      statusText: this.statusText,
      requestUrl: this.requestUrl,
      activeSite: this.activeSite,
      pageIndex: this.pageIndex,
      totalPages: this.totalPages,
      nextUrl: this.nextUrl,
      resultCount: this.resultCount,
      galleries: cloneGalleryInfos(this.galleries),
      favoriteCat: this.favoriteCat,
      favoriteCategories: cloneFavoriteCategories(this.favoriteCategories),
      hasFirstRefresh: this.hasFirstRefresh,
      filterActive: this.filterActive,
      accountFilterEnabled: this.accountFilterEnabled,
      searchFilterEnabled: this.searchFilterEnabled,
      searchAdvancedPanelOpened: this.searchAdvancedPanelOpened,
      searchMode: this.searchMode,
      searchCategory: this.searchCategory,
      advancedSearchEnabled: this.advancedSearchEnabled,
      advanceSearch: this.advanceSearch,
      minRating: this.minRating,
      pageFrom: this.pageFrom,
      pageTo: this.pageTo,
      imagePath: this.imageSearchPath,
      imageUseSimilarityScan: this.imageSearchUseSimilarityScan,
      imageOnlySearchCovers: this.imageSearchOnlyCovers,
      imageShowExpunged: this.imageSearchShowExpunged,
      searchSubmitted: this.searchSubmitted,
      listScrollOffset: this.listScrollOffset,
      appendExhausted: this.appendExhausted
    });
  }

  private saveNavigationCache(): void {
    if (this.navigationCacheSuppressed) {
      return;
    }
    galleryListNavigationCache.set(this.navigationCacheKey(), {
      showSearchResultScene: this.isSearchResultScene ? false : this.showSearchResultScene,
      searchResultDraft: this.isSearchResultScene ? createEmptySearchResultDraft() :
        cloneSearchResultDraft(this.searchResultDraft),
      localSearchBarVisible: this.localSearchBarVisible,
      showDetail: this.showDetail,
      restoreDetailWithFade: this.restoreDetailWithFade,
      detailLink: cloneGalleryDetailLink(this.detailLink),
      detail: cloneGalleryDetail(this.detail),
      detailStatus: this.detailStatus,
      detailRequestUrl: this.detailRequestUrl,
      detailScrollOffset: this.detailScrollOffset,
      fabExpanded: this.fabExpanded
    });
  }

  private clearNavigationCache(): void {
    galleryListNavigationCache.delete(this.navigationCacheKey());
  }

  private closeSearchResultToParent(): void {
    this.navigationCacheSuppressed = true;
    this.clearNavigationCache();
    this.onBack();
  }

  private refreshSearchResultNavigationCache(): void {
    if (this.showSearchResultScene) {
      this.saveNavigationCache();
    }
  }

  private resetListScroll(): void {
    this.listScrollOffset = 0;
    this.saveListCache();
  }

  private syncAccountFilterSetting(): void {
    this.accountFilterEnabled = ehSettingsStore.getValue('use_account_default_filter', 'On') !== 'Off';
  }

  private galleryStatusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    if (this.sourceRoute === GalleryRoute.Favorites) {
      this.favoriteCat = recentFavoriteCat;
    }
    if (!this.restoreListCache()) {
      this.keyword = this.initialKeyword.length > 0 ? this.initialKeyword : defaultKeywordForRoute(this.sourceRoute);
      this.searchMode = this.initialSearchMode;
      this.searchCategory = this.initialSearchCategory;
      this.advancedSearchEnabled = this.initialAdvancedSearchEnabled;
      this.advanceSearch = this.initialAdvanceSearch;
      this.minRating = this.initialMinRating;
      this.pageFrom = this.initialPageFrom;
      this.pageTo = this.initialPageTo;
      this.imageSearchPath = this.initialImagePath;
      this.imageSearchUseSimilarityScan = this.initialImageUseSimilarityScan;
      this.imageSearchOnlyCovers = this.initialImageOnlySearchCovers;
      this.imageSearchShowExpunged = this.initialImageShowExpunged;
      this.filterActive = this.isSearchResultScene ? false : this.searchResultDraft.filterActive;
      this.searchFilterEnabled = this.isSearchResultScene ? this.initialSearchFilterEnabled : true;
      this.searchAdvancedPanelOpened = this.isSearchResultScene ?
        (this.searchResultDraft.searchAdvancedPanelOpened || this.initialSearchAdvancedPanelOpened) : false;
      this.searchSubmitted = !this.isSearchResultScene || this.initialSearchSubmitted;
      this.localSearchBarVisible = false;
    }
    this.restoreNavigationCache();
    const context = getAbilityContext();
    if (context !== undefined) {
      Promise.all([
        ehCookieStore.load(context),
        ehFilterStore.load(context),
        ehSettingsStore.load(context),
        ehBookmarkStore.ensureLoaded(context),
        this.sourceRoute === GalleryRoute.Favorites ? ehLocalFavoritesStore.ensureLoaded(context) : Promise.resolve()
      ]).catch((error: Error) => {
        this.statusText = 'Cookie load failed, using current session: ' + error.message;
      }).finally(() => {
        this.refreshSearchBookmarks();
        this.refreshLocalFavoriteCount();
        const previousAccountFilterEnabled = this.accountFilterEnabled;
        this.syncAccountFilterSetting();
        if (!this.isSearchResultScene && previousAccountFilterEnabled !== this.accountFilterEnabled && !this.useLocalProvider) {
          this.hasFirstRefresh = false;
        }
        if (this.isSearchResultScene && this.initialSearchSubmitted && !this.hasFirstRefresh) {
          this.searchSubmitted = true;
        }
        if (!this.isSearchResultScene || this.searchSubmitted) {
          this.firstRefresh();
        }
      });
    } else {
      if (this.isSearchResultScene && this.initialSearchSubmitted && !this.hasFirstRefresh) {
        this.searchSubmitted = true;
      }
      if (!this.isSearchResultScene || this.searchSubmitted) {
        this.firstRefresh();
      }
    }
    setActiveBackHandler(() => this.handleSystemBack());
  }

  aboutToDisappear(): void {
    this.saveListCache();
    this.saveNavigationCache();
  }

  onPageHide(): void {
    this.saveListCache();
    this.saveNavigationCache();
  }

  onResetVersionChanged(): void {
    this.resetToTopLevel();
  }

  private handleSystemBack(): boolean {
    if (this.cardActionVisible) {
      this.closeCardActions();
      return true;
    }
    if (this.showBookmarkManager) {
      this.closeBookmarkManager();
      return true;
    }
    if (this.showReader) {
      this.closeReader();
      return true;
    }
    if (this.showDetail) {
      if (runDetailBackHandler()) {
        return true;
      }
      this.closeDetail();
      return true;
    }
    if (this.showSearchResultScene) {
      this.closeSearchResultScene();
      return true;
    }
    if (this.useLocalProvider && this.localSearchBarVisible) {
      this.closeLocalSearchBar();
      return true;
    }
    if (this.isSearchResultScene) {
      this.closeSearchResultToParent();
      return true;
    }
    return false;
  }

  private resetToTopLevel(): void {
    if (this.showReader) {
      leaveEmbeddedReaderFullscreen();
    }
    this.showReader = false;
    this.showDetail = false;
    this.restoreDetailWithFade = false;
    this.detailLink = createEmptyGalleryDetailLink();
    this.detail = createEmptyDetail();
    this.detailStatus = 'Tap a gallery row to load detail';
    this.detailRequestUrl = '';
    this.detailScrollOffset = 0;
    this.cardActionVisible = false;
    this.cardActionGallery = createEmptyGallery();
    this.showBookmarkManager = false;
    this.addBookmarkDialogVisible = false;
    this.showSearchResultScene = false;
    this.searchResultDraft = createEmptySearchResultDraft();
    this.localSearchBarVisible = false;
    this.fabExpanded = false;
    this.restoreBackHandler();
    this.renderVersion++;
    this.clearNavigationCache();
  }

  private firstRefresh(): void {
    if (this.useLocalProvider && (this.showDetail || this.showReader)) {
      return;
    }
    if (this.hasFirstRefresh && !this.useLocalProvider) {
      return;
    }
    this.hasFirstRefresh = true;
    this.loadListPage(0, this.useLocalProvider && this.galleries.length > 0);
  }

  private loadListPage(pageIndex: number, preserveExisting: boolean = false, onDone?: () => void): void {
    if (this.useLocalProvider) {
      this.loadLocal(pageIndex, preserveExisting, onDone);
      return;
    }
    this.loadRemote(pageIndex, preserveExisting, onDone);
  }

  private absoluteListUrl(url: string): string {
    if (url.indexOf('http://') === 0 || url.indexOf('https://') === 0) {
      return url;
    }
    if (url.indexOf('//') === 0) {
      return 'https:' + url;
    }
    const host = EhUrl.getHost(this.activeSite);
    if (url.indexOf('/') === 0) {
      return host.substring(0, host.length - 1) + url;
    }
    return host + url;
  }

  private loadRemote(pageIndex: number, preserveExisting: boolean = false, onDone?: () => void): void {
    this.pageIndex = pageIndex;
    this.statusText = 'Loading...';
    if (!preserveExisting) {
      this.resultCount = '';
      this.galleries = [];
    }
    this.nextUrl = '';
    this.isLoadingMore = false;
    this.appendExhausted = false;
    if (pageIndex === 0) {
      this.resetListScroll();
      this.scrollResetVersion++;
    }
    this.renderVersion++;
    this.closeDetail();
    this.saveListCache();
    const request = this.loadRoutePageWithFallback(pageIndex);

    request.then((result: GalleryListLoadResult) => {
      this.requestUrl = result.url;
      this.galleries = this.visibleRemoteGalleries(result.galleries);
      this.updateFavoriteCategories(result.favoriteCategories);
      this.statusText = result.ok ? result.message : galleryListFailureMessage(result, this.activeSite);
      this.totalPages = result.pages;
      this.nextUrl = result.nextUrl;
      this.resultCount = result.resultCount;
      this.appendExhausted = this.isAppendExhausted(result, pageIndex, this.galleries.length);
      this.renderVersion++;
      this.saveListCache();
      if (onDone !== undefined) {
        onDone();
      }
    }).catch((error: Error) => {
      this.statusText = 'Load failed: ' + error.message;
      this.galleries = [];
      this.renderVersion++;
      this.saveListCache();
      if (onDone !== undefined) {
        onDone();
      }
    });
  }

  private loadRemoteUrl(url: string, preserveExisting: boolean = false, onDone?: () => void): void {
    const absoluteUrl = this.absoluteListUrl(url);
    if (absoluteUrl.length === 0) {
      this.statusText = 'No other page to jump to';
      if (onDone !== undefined) {
        onDone();
      }
      return;
    }
    this.pageIndex = 0;
    this.statusText = 'Loading...';
    if (!preserveExisting) {
      this.resultCount = '';
      this.galleries = [];
    }
    this.nextUrl = '';
    this.isLoadingMore = false;
    this.appendExhausted = false;
    this.resetListScroll();
    this.scrollResetVersion++;
    this.renderVersion++;
    this.closeDetail();
    this.saveListCache();

    this.client.loadGalleryListUrl(absoluteUrl, this.activeSite, this.includeAccountUConfig()).then((result: GalleryListLoadResult) => {
      this.requestUrl = result.url;
      this.galleries = this.visibleRemoteGalleries(result.galleries);
      this.updateFavoriteCategories(result.favoriteCategories);
      this.statusText = result.ok ? result.message : galleryListFailureMessage(result, this.activeSite);
      this.totalPages = result.pages;
      this.nextUrl = result.nextUrl;
      this.resultCount = result.resultCount;
      this.appendExhausted = this.isAppendExhausted(result, this.pageIndex, this.galleries.length);
      this.renderVersion++;
      this.saveListCache();
      if (onDone !== undefined) {
        onDone();
      }
    }).catch((error: Error) => {
      this.statusText = 'Load failed: ' + error.message;
      this.galleries = [];
      this.renderVersion++;
      this.saveListCache();
      if (onDone !== undefined) {
        onDone();
      }
    });
  }

  private loadLocal(pageIndex: number, preserveExisting: boolean = false, onDone?: () => void): void {
    this.activeSite = effectiveListSite(this.sourceRoute);
    this.pageIndex = pageIndex;
    this.statusText = 'Loading...';
    if (!preserveExisting) {
      this.resultCount = '';
      this.galleries = [];
    }
    this.nextUrl = '';
    this.isLoadingMore = false;
    this.appendExhausted = false;
    if (pageIndex === 0) {
      this.resetListScroll();
      this.scrollResetVersion++;
    }
    this.renderVersion++;
    this.closeDetail();
    this.saveListCache();

    this.localProvider(this.keyword.trim(), pageIndex, this.localPageSize, this.localSearchOptions())
      .then((result: GalleryListLoadResult) => {
      this.requestUrl = result.url;
      this.galleries = this.visibleRemoteGalleries(result.galleries);
      this.statusText = result.ok ? result.message : result.message;
      this.totalPages = result.pages;
      this.nextUrl = result.nextUrl;
      this.resultCount = result.resultCount;
      this.appendExhausted = this.isAppendExhausted(result, pageIndex, this.galleries.length);
      this.renderVersion++;
      this.saveListCache();
      if (onDone !== undefined) {
        onDone();
      }
    }).catch((error: Error) => {
      this.statusText = 'Load failed: ' + error.message;
      this.galleries = [];
      this.renderVersion++;
      this.saveListCache();
      if (onDone !== undefined) {
        onDone();
      }
    });
  }

  private loadAppendPage(): void {
    if (this.isSearchResultScene && !this.searchSubmitted) {
      return;
    }
    if (this.isLoadingMore) {
      return;
    }
    if (this.appendExhausted) {
      this.statusText = uiText('All pages loaded');
      return;
    }
    if (this.useLocalProvider) {
      this.loadAppendLocalPage();
      return;
    }
    // Only stop if we have confirmed total page count AND already at the last page
    if (this.nextUrl.length === 0 && this.totalPages > 0 && this.pageIndex >= this.totalPages - 1) {
      this.statusText = uiText('All pages loaded');
      this.appendExhausted = true;
      return;
    }
    const nextPage = this.pageIndex + 1;
    this.isLoadingMore = true;

    const request =
      this.nextUrl.length > 0 ?
        this.client.loadGalleryListUrl(this.absoluteListUrl(this.nextUrl), this.activeSite, this.includeAccountUConfig()) :
        this.loadRoutePageWithFallback(nextPage);

    request.then((result: GalleryListLoadResult) => {
      this.requestUrl = result.url;
      const newGalleries = this.visibleRemoteGalleries(result.galleries);
      this.updateFavoriteCategories(result.favoriteCategories);
      if (newGalleries.length === 0) {
        // Empty page = reached the end even if we don't know total
        this.statusText = uiText('All pages loaded');
        this.appendExhausted = true;
        this.isLoadingMore = false;
        this.saveListCache();
        return;
      }
      const existingGids: Set<number> = new Set(this.galleries.map((g: GalleryInfo) => g.gid));
      const unique: GalleryInfo[] = newGalleries.filter((g: GalleryInfo) => !existingGids.has(g.gid));
      if (unique.length === 0) {
        this.statusText = uiText('All pages loaded');
        this.appendExhausted = true;
        this.isLoadingMore = false;
        this.saveListCache();
        return;
      }
      this.galleries = this.galleries.concat(unique);
      this.pageIndex = nextPage;
      if (result.pages > 0) {
        this.totalPages = result.pages;
      }
      this.nextUrl = result.nextUrl;
      this.resultCount = result.resultCount;
      this.statusText = result.ok ? result.message : galleryListFailureMessage(result, this.activeSite);
      this.appendExhausted = this.isAppendExhausted(result, nextPage, unique.length);
      this.isLoadingMore = false;
      this.saveListCache();
    }).catch((error: Error) => {
      this.statusText = 'Load more failed: ' + error.message;
      this.isLoadingMore = false;
      this.saveListCache();
    });
  }

  private localSearchOptions(): LocalGallerySearchOptions {
    return {
      mode: this.searchMode,
      category: this.searchCategory,
      advancedEnabled: this.advancedSearchEnabled,
      advancedPanelOpened: this.searchAdvancedPanelOpened,
      advanceSearch: this.advanceSearch,
      minRating: this.minRating
    };
  }

  private loadAppendLocalPage(): void {
    if (this.appendExhausted) {
      this.statusText = uiText('All pages loaded');
      return;
    }
    if (this.nextUrl.length === 0 && this.totalPages > 0 && this.pageIndex >= this.totalPages - 1) {
      this.statusText = uiText('All pages loaded');
      this.appendExhausted = true;
      return;
    }
    const nextPage = this.pageIndex + 1;
    this.isLoadingMore = true;
    this.localProvider(this.keyword.trim(), nextPage, this.localPageSize, this.localSearchOptions())
      .then((result: GalleryListLoadResult) => {
      this.requestUrl = result.url;
      const newGalleries = this.visibleRemoteGalleries(result.galleries);
      if (newGalleries.length === 0) {
        this.statusText = uiText('All pages loaded');
        this.appendExhausted = true;
        this.isLoadingMore = false;
        this.saveListCache();
        return;
      }
      const existingGids: Set<number> = new Set(this.galleries.map((g: GalleryInfo) => g.gid));
      const unique: GalleryInfo[] = newGalleries.filter((g: GalleryInfo) => !existingGids.has(g.gid));
      if (unique.length === 0) {
        this.statusText = uiText('All pages loaded');
        this.appendExhausted = true;
        this.isLoadingMore = false;
        this.saveListCache();
        return;
      }
      this.galleries = this.galleries.concat(unique);
      this.pageIndex = nextPage;
      if (result.pages > 0) {
        this.totalPages = result.pages;
      }
      this.nextUrl = result.nextUrl;
      this.resultCount = result.resultCount;
      this.statusText = result.ok ? result.message : result.message;
      this.appendExhausted = this.isAppendExhausted(result, nextPage, unique.length);
      this.isLoadingMore = false;
      this.saveListCache();
    }).catch((error: Error) => {
      this.statusText = 'Load more failed: ' + error.message;
      this.isLoadingMore = false;
      this.saveListCache();
    });
  }

  private loadRoutePageWithFallback(pageIndex: number): Promise<GalleryListLoadResult> {
    const primarySite = effectiveListSite(this.sourceRoute);
    this.activeSite = primarySite;
    return this.loadRoutePage(pageIndex, primarySite).then((result: GalleryListLoadResult) => {
      this.activeSite = primarySite;
      return result;
    });
  }

  private visibleRemoteGalleries(galleries: GalleryInfo[]): GalleryInfo[] {
    const cloned = cloneGalleryInfos(galleries);
    return this.shouldApplyLocalGalleryFilters() ? applyGalleryFilters(cloned) : cloned;
  }

  private updateFavoriteCategories(categories: FavoriteCategoryInfo[] | undefined): void {
    if (this.sourceRoute !== GalleryRoute.Favorites || categories === undefined || categories.length === 0) {
      return;
    }
    this.favoriteCategories = cloneFavoriteCategories(categories);
  }

  private refreshLocalFavoriteCount(): void {
    if (this.sourceRoute !== GalleryRoute.Favorites) {
      return;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      this.favoriteLocalCount = ehLocalFavoritesStore.count();
      return;
    }
    ehLocalFavoritesStore.ensureLoaded(context).then(() => {
      this.favoriteLocalCount = ehLocalFavoritesStore.count();
      this.renderVersion++;
    }).catch(() => {
      this.favoriteLocalCount = -1;
    });
  }

  private shouldApplyLocalGalleryFilters(): boolean {
    return !this.isSearchResultScene && !this.useLocalProvider && this.accountFilterEnabled &&
      localGalleryFilterRoute(this.sourceRoute);
  }

  private loadRoutePage(pageIndex: number, site: GallerySite): Promise<GalleryListLoadResult> {
    const requestKeyword = searchKeywordForRequest(this.keyword);
    const hasSearchTags = searchTagTokens(this.keyword).length > 0;
    if (this.sourceRoute === GalleryRoute.Favorites) {
      if (this.favoriteCat === FavListUrlBuilder.FAV_CAT_LOCAL) {
        return this.loadLocalFavoritePage(requestKeyword, pageIndex);
      }
      const builder = new FavListUrlBuilder();
      builder.keyword = requestKeyword;
      builder.index = pageIndex;
      builder.favCat = this.favoriteCat;
      this.requestUrl = builder.build(site);
      const request = this.client.loadFavoritesList(builder, site);
      if (this.favoriteCat === FavListUrlBuilder.FAV_CAT_ALL) {
        return request.then((result: GalleryListLoadResult) => {
          return this.mergeLocalFavoritesIntoAllFavorites(result, requestKeyword, pageIndex);
        });
      }
      return request;
    }

    const builder = new ListUrlBuilder();
    builder.keyword = (this.isSearchResultScene || routeUsesKeyword(this.sourceRoute)) ? requestKeyword : '';
    builder.pageIndex = pageIndex;
    const routeMode = hasSearchTags ? ListMode.Normal : (this.useForcedMode ? this.forcedMode : listModeForRoute(this.sourceRoute));
    builder.mode = this.searchModeForRoute(routeMode, builder.keyword);
    if (hasSearchTags) {
      builder.mode = ListMode.Normal;
    }
    builder.follow = this.follow;
    builder.category = this.requestCategoryForMode(builder.mode);
    builder.imagePath = this.imageSearchPath;
    builder.useSimilarityScan = this.imageSearchUseSimilarityScan;
    builder.onlySearchCovers = this.imageSearchOnlyCovers;
    builder.showExpunged = this.imageSearchShowExpunged;
    if (this.shouldApplySearchFilters() && this.advancedSearchEnabled && this.searchSupportsAdvanced(builder.mode)) {
      builder.advanceSearch = this.advanceSearch;
      builder.minRating = this.minRating;
      builder.pageFrom = this.pageFrom;
      builder.pageTo = this.pageTo;
    }
    if (this.isSearchResultScene && !this.searchFilterEnabled && this.searchSupportsAdvanced(builder.mode)) {
      const baseFlags = builder.advanceSearch === -1 ? 0 : builder.advanceSearch;
      builder.advanceSearch = baseFlags | ACCOUNT_DEFAULT_FILTER_DISABLE_FLAGS;
    }
    if (!this.isSearchResultScene && !this.includeAccountUConfig() && this.searchSupportsAdvanced(builder.mode)) {
      builder.advanceSearch =
        (builder.advanceSearch === -1 ? 0 : builder.advanceSearch) | ACCOUNT_DEFAULT_FILTER_DISABLE_FLAGS;
    }
    this.requestUrl = builder.build(site);
    return this.client.loadGalleryList(builder, site, this.includeAccountUConfig());
  }

  private async loadLocalFavoritePage(keyword: string, pageIndex: number): Promise<GalleryListLoadResult> {
    const context = getAbilityContext();
    if (context === undefined) {
      return {
        ok: false,
        url: 'local:favorites',
        statusCode: 0,
        message: 'Local favorites unavailable',
        pages: 0,
        nextPage: -1,
        nextUrl: '',
        resultCount: '',
        galleries: [],
        favoriteCategories: this.favoriteCategories
      };
    }
    await ehLocalFavoritesStore.ensureLoaded(context);
    const pageSize = 25;
    const all = ehLocalFavoritesStore.getItems(keyword);
    this.favoriteLocalCount = ehLocalFavoritesStore.count();
    const start = Math.max(0, pageIndex) * pageSize;
    const page = all.slice(start, Math.min(all.length, start + pageSize));
    const pages = all.length === 0 ? 0 : Math.ceil(all.length / pageSize);
    return {
      ok: page.length > 0,
      url: 'local:favorites',
      statusCode: 200,
      message: page.length > 0 ? 'Parsed ' + page.length.toString() + ' galleries' : 'No results',
      pages: pages,
      nextPage: pageIndex + 1 < pages ? pageIndex + 1 : -1,
      nextUrl: '',
      resultCount: all.length.toString() + ' local favorites',
      galleries: page,
      favoriteCategories: this.favoriteCategories
    };
  }

  private async mergeLocalFavoritesIntoAllFavorites(result: GalleryListLoadResult, keyword: string,
    pageIndex: number): Promise<GalleryListLoadResult> {
    const context = getAbilityContext();
    if (context === undefined) {
      return result;
    }
    await ehLocalFavoritesStore.ensureLoaded(context);
    this.favoriteLocalCount = ehLocalFavoritesStore.count();
    if (pageIndex !== 0) {
      return result;
    }
    const local = ehLocalFavoritesStore.getItems(keyword);
    if (local.length === 0) {
      return result;
    }
    const merged = mergeFavoriteGalleries(local, result.galleries);
    return {
      ok: result.ok || merged.length > 0,
      url: result.url,
      statusCode: result.statusCode,
      message: result.ok ? result.message + ', local ' + local.length.toString() : 'Parsed ' + merged.length.toString() + ' galleries',
      pages: result.pages,
      nextPage: result.nextPage,
      nextUrl: result.nextUrl,
      resultCount: mergedFavoriteResultCount(result.resultCount, local.length),
      galleries: merged,
      favoriteCategories: result.favoriteCategories
    };
  }

  private includeAccountUConfig(): boolean {
    return this.isSearchResultScene || this.accountFilterEnabled;
  }

  private searchModeForRoute(routeMode: ListMode, keyword: string): ListMode {
    if (!this.isSearchResultScene && this.filterActive && keyword.trim().length > 0) {
      return ListMode.Filter;
    }
    if (this.sourceRoute === GalleryRoute.Home) {
      return this.searchMode;
    }
    if (this.sourceRoute === GalleryRoute.Subscription && this.searchMode !== ListMode.Uploader &&
      this.searchMode !== ListMode.Tag) {
      return ListMode.Subscription;
    }
    if (this.searchMode === ListMode.Uploader || this.searchMode === ListMode.Tag) {
      return this.searchMode;
    }
    return routeMode;
  }

  private shouldApplySearchFilters(): boolean {
    return !this.isSearchResultScene || this.searchAdvancedPanelOpened;
  }

  private requestCategoryForMode(mode: ListMode): number {
    if (this.isSearchResultScene && this.searchAdvancedPanelOpened && this.searchSupportsCategory(mode)) {
      return this.searchCategory === GalleryCategory.None ? ALL_CATEGORY : this.searchCategory;
    }
    if (!this.isSearchResultScene && this.shouldApplySearchFilters() && this.searchSupportsCategory(mode) &&
      this.searchCategory !== GalleryCategory.None) {
      return this.searchCategory;
    }
    if (!this.isSearchResultScene && this.searchSupportsCategory(mode) && !this.accountFilterEnabled) {
      return ALL_CATEGORY;
    }
    return GalleryCategory.None;
  }

  private searchSupportsCategory(mode: ListMode): boolean {
    return mode === ListMode.Normal || mode === ListMode.Subscription || mode === ListMode.Tag ||
      mode === ListMode.Uploader || mode === ListMode.WhatsHot;
  }

  private searchSupportsAdvanced(mode: ListMode): boolean {
    return mode === ListMode.Normal || mode === ListMode.Subscription || mode === ListMode.Tag ||
      mode === ListMode.Uploader || mode === ListMode.WhatsHot;
  }

  private refreshSearchBookmarks(): void {
    this.searchBookmarks = ehBookmarkStore.getItems();
  }

  private canUseBookmarks(): boolean {
    return !this.useLocalProvider && this.sourceRoute !== GalleryRoute.Favorites &&
      (this.sourceRoute === GalleryRoute.Home || this.sourceRoute === GalleryRoute.Subscription ||
        this.sourceRoute === GalleryRoute.WhatsHot);
  }

  private currentBookmarkLocation(): GalleryRoute {
    if (this.sourceRoute === GalleryRoute.Subscription) {
      return GalleryRoute.Subscription;
    }
    if (this.sourceRoute === GalleryRoute.WhatsHot) {
      return GalleryRoute.WhatsHot;
    }
    return GalleryRoute.Home;
  }

  private currentBookmarkMode(): ListMode {
    const requestKeyword = searchKeywordForRequest(this.keyword);
    const hasSearchTags = searchTagTokens(this.keyword).length > 0;
    if (hasSearchTags) {
      return ListMode.Normal;
    }
    const routeMode = this.useForcedMode ? this.forcedMode : listModeForRoute(this.currentBookmarkLocation());
    return this.searchModeForRoute(routeMode, requestKeyword);
  }

  private currentBookmarkFilterEnabled(): boolean {
    return this.isSearchResultScene ? this.searchFilterEnabled : this.accountFilterEnabled;
  }

  private currentBookmarkCategory(mode: ListMode): number {
    return this.requestCategoryForMode(mode);
  }

  private currentBookmarkDefaultName(mode: ListMode, category: number): string {
    const translatedKeyword = this.translatedBookmarkKeyword(this.keyword);
    if (translatedKeyword.length > 0) {
      return translatedKeyword;
    }
    if (mode === ListMode.Subscription && category === GalleryCategory.None && !this.advancedSearchEnabled) {
      return uiText('Subscription');
    }
    if (mode === ListMode.WhatsHot) {
      return uiText('Whats Hot');
    }
    if (category !== GalleryCategory.None && category !== ALL_CATEGORY) {
      return categoryName(category);
    }
    return uiText('Homepage');
  }

  private translatedBookmarkKeyword(keyword: string): string {
    const parts: string[] = [];
    const tokens = searchTagTokens(keyword);
    for (let i = 0; i < tokens.length; i++) {
      const name = this.translatedBookmarkTag(tokens[i]);
      if (name.length > 0) {
        parts.push(name);
      }
    }
    const text = searchKeywordWithoutTagTokens(keyword).replace(/\$/g, ' ').replace(/\s+/g, ' ').trim();
    if (text.length > 0) {
      parts.push(text);
    }
    if (tokens.length === 0 && parts.length === 0) {
      const fallback = keyword.replace(/\$/g, ' ').replace(/\s+/g, ' ').trim();
      if (fallback.length > 0) {
        parts.push(fallback);
      }
    }
    return parts.join(' ').replace(/\s+/g, ' ').trim();
  }

  private translatedBookmarkTag(token: string): string {
    let value = token.trim();
    if (value.endsWith('$')) {
      value = value.substring(0, value.length - 1).trim();
    }
    const colon = value.indexOf(':');
    let namespace = '';
    let tag = value;
    if (colon > 0 && colon < value.length - 1) {
      namespace = value.substring(0, colon).trim();
      tag = value.substring(colon + 1).trim();
    }
    if (shouldShowTagTranslations()) {
      const translated = ehTagTranslationStore.translate(namespace, tag);
      if (translated.length > 0) {
        return translated;
      }
    }
    return searchTagTokenLabel(token).replace(/_/g, ' ').replace(/\$/g, ' ').trim();
  }

  private bookmarkHasAdvancedParams(bookmark: SearchBookmarkInfo): boolean {
    return bookmark.advanceSearch !== -1 || bookmark.minRating !== -1 || bookmark.pageFrom !== -1 ||
      bookmark.pageTo !== -1;
  }

  private showFloatingStatus(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: uiStatusText(message) });
    } catch (error) {
    }
  }

  private openAddBookmarkDialog(): void {
    if (!this.canUseBookmarks()) {
      return;
    }
    if (this.searchMode === ListMode.ImageSearch) {
      this.statusText = 'Cannot bookmark image search';
      return;
    }
    const bookmarkMode = this.currentBookmarkMode();
    const bookmarkCategory = this.currentBookmarkCategory(bookmarkMode);
    const name = this.currentBookmarkDefaultName(bookmarkMode, bookmarkCategory);
    const draft = ehBookmarkStore.createBookmark(name, bookmarkMode, bookmarkCategory, this.keyword,
      this.advancedSearchEnabled ? this.advanceSearch : -1, this.minRating, this.pageFrom, this.pageTo,
      this.currentBookmarkFilterEnabled(), this.currentBookmarkLocation());
    if (ehBookmarkStore.hasEquivalent(draft)) {
      this.statusText = 'Duplicate bookmark';
      this.showFloatingStatus('Duplicate bookmark');
      return;
    }
    this.addBookmarkDraft = draft;
    this.addBookmarkName = name;
    this.addBookmarkDialogVisible = true;
  }

  private confirmAddBookmark(): void {
    const name = this.addBookmarkName.trim();
    if (name.length === 0) {
      this.statusText = 'Bookmark name is empty';
      return;
    }
    const bookmark = ehBookmarkStore.createBookmark(name, this.addBookmarkDraft.mode, this.addBookmarkDraft.category,
      this.addBookmarkDraft.keyword, this.addBookmarkDraft.advanceSearch, this.addBookmarkDraft.minRating,
      this.addBookmarkDraft.pageFrom, this.addBookmarkDraft.pageTo, this.addBookmarkDraft.filterEnabled,
      this.addBookmarkDraft.location);
    if (!ehBookmarkStore.addBookmark(bookmark)) {
      this.statusText = 'Duplicate bookmark';
      this.showFloatingStatus('Duplicate bookmark');
      return;
    }
    this.addBookmarkDialogVisible = false;
    this.refreshSearchBookmarks();
    this.statusText = 'Bookmark added';
  }

  private removeSearchBookmark(bookmark: SearchBookmarkInfo): void {
    ehBookmarkStore.removeBookmark(bookmark.id);
    this.refreshSearchBookmarks();
    this.statusText = 'Bookmark removed';
  }

  private openBookmarkManager(): void {
    this.refreshSearchBookmarks();
    this.showBookmarkManager = true;
  }

  private closeBookmarkManager(): void {
    this.showBookmarkManager = false;
  }

  private renameSearchBookmark(bookmark: SearchBookmarkInfo, name: string): void {
    if (!ehBookmarkStore.renameBookmark(bookmark.id, name)) {
      this.statusText = name.trim().length === 0 ? 'Bookmark name is empty' : 'Bookmark update failed';
      return;
    }
    this.refreshSearchBookmarks();
    this.statusText = 'Bookmark updated';
  }

  private moveSearchBookmarkToIndex(from: number, to: number): void {
    if (ehBookmarkStore.moveBookmarkToIndex(from, to)) {
      this.refreshSearchBookmarks();
      this.statusText = 'Bookmark updated';
    }
  }

  private openSearchBookmark(bookmark: SearchBookmarkInfo): void {
    const hasAdvancedParams = this.bookmarkHasAdvancedParams(bookmark);
    const showSearchOptions = hasAdvancedParams || bookmark.category !== GalleryCategory.None;
    const draft: SearchResultDraft = {
      keyword: bookmark.keyword,
      mode: bookmark.mode,
      category: bookmark.category,
      advancedEnabled: hasAdvancedParams,
      advanceSearch: bookmark.advanceSearch === -1 ? DEFAULT_ADVANCE_SEARCH : bookmark.advanceSearch,
      minRating: bookmark.minRating,
      pageFrom: bookmark.pageFrom,
      pageTo: bookmark.pageTo,
      filterActive: false,
      searchFilterEnabled: bookmark.filterEnabled,
      searchAdvancedPanelOpened: showSearchOptions,
      submitted: true,
      sourceRoute: bookmark.location,
      imagePath: '',
      imageUseSimilarityScan: false,
      imageOnlySearchCovers: false,
      imageShowExpunged: false
    };
    if (!this.isSearchResultScene) {
      this.searchResultDraft = draft;
      this.showSearchResultScene = true;
      this.saveNavigationCache();
      setTimeout(() => {
        this.refreshSearchResultNavigationCache();
      }, 0);
      return;
    }
    this.keyword = draft.keyword;
    this.searchMode = draft.mode;
    this.searchCategory = draft.category;
    this.advancedSearchEnabled = draft.advancedEnabled;
    this.advanceSearch = draft.advanceSearch;
    this.minRating = draft.minRating;
    this.pageFrom = draft.pageFrom;
    this.pageTo = draft.pageTo;
    this.searchFilterEnabled = draft.searchFilterEnabled;
    this.searchAdvancedPanelOpened = draft.searchAdvancedPanelOpened;
    this.searchSubmitted = true;
    this.hasFirstRefresh = true;
    this.resetListScroll();
    this.loadListPage(0);
  }

  private applySearch(): void {
    this.fabExpanded = false;
    this.rememberSearchKeyword(this.keyword);
    const directGallery = gallerySuggestionUrl(this.keyword);
    if (directGallery !== null) {
      this.searchSubmitted = true;
      this.hasFirstRefresh = true;
      this.resetListScroll();
      this.openDetailByToken(directGallery.gid, directGallery.token);
      return;
    }
    this.searchSubmitted = true;
    this.hasFirstRefresh = true;
    this.resetListScroll();
    this.loadListPage(0);
  }

  private startImageSearch(path: string, useSimilarityScan: boolean, onlySearchCovers: boolean): void {
    if (path.length === 0) {
      this.statusText = 'No image selected for search';
      return;
    }
    this.fabExpanded = false;
    const draft: SearchResultDraft = {
      keyword: '',
      mode: ListMode.ImageSearch,
      category: GalleryCategory.None,
      advancedEnabled: false,
      advanceSearch: DEFAULT_ADVANCE_SEARCH,
      minRating: -1,
      pageFrom: -1,
      pageTo: -1,
      filterActive: false,
      searchFilterEnabled: true,
      searchAdvancedPanelOpened: false,
      submitted: true,
      sourceRoute: GalleryRoute.Home,
      imagePath: path,
      imageUseSimilarityScan: useSimilarityScan,
      imageOnlySearchCovers: onlySearchCovers,
      imageShowExpunged: true
    };
    if (!this.isSearchResultScene) {
      this.searchResultDraft = draft;
      this.showSearchResultScene = true;
      this.saveNavigationCache();
      setTimeout(() => {
        this.refreshSearchResultNavigationCache();
      }, 0);
      return;
    }
    this.keyword = '';
    this.searchMode = ListMode.ImageSearch;
    this.searchCategory = GalleryCategory.None;
    this.advancedSearchEnabled = false;
    this.advanceSearch = DEFAULT_ADVANCE_SEARCH;
    this.minRating = -1;
    this.pageFrom = -1;
    this.pageTo = -1;
    this.imageSearchPath = path;
    this.imageSearchUseSimilarityScan = useSimilarityScan;
    this.imageSearchOnlyCovers = onlySearchCovers;
    this.imageSearchShowExpunged = true;
    this.searchSubmitted = true;
    this.hasFirstRefresh = true;
    this.resetListScroll();
    this.loadListPage(0);
  }

  private rememberSearchKeyword(keyword: string): void {
    recordSearchHistory(keyword);
  }

  private changeFavoriteCat(favCat: number): void {
    if (this.sourceRoute !== GalleryRoute.Favorites || favCat === this.favoriteCat) {
      return;
    }
    this.favoriteCat = favCat;
    recentFavoriteCat = favCat;
    this.hasFirstRefresh = true;
    this.resetListScroll();
    this.loadListPage(0, false);
  }

  private favoriteSceneTitle(): string {
    if (this.sourceRoute !== GalleryRoute.Favorites || this.favoriteCat === FavListUrlBuilder.FAV_CAT_ALL) {
      return gallerySearchTitle(this.sourceRoute, this.keyword, this.filterActive);
    }
    return favoriteCategoryName(this.favoriteCat, this.favoriteCategories);
  }

  private openSearchScene(): void {
    this.fabExpanded = false;
    if (this.useLocalProvider) {
      this.openLocalSearchBar();
      return;
    }
    this.searchResultDraft = {
      keyword: this.keyword.trim(),
      mode: this.searchMode,
      category: this.searchCategory,
      advancedEnabled: this.advancedSearchEnabled,
      advanceSearch: this.advanceSearch,
      minRating: this.minRating,
      pageFrom: -1,
      pageTo: -1,
      filterActive: false,
      searchFilterEnabled: true,
      searchAdvancedPanelOpened: false,
      submitted: false,
      sourceRoute: this.sourceRoute,
      imagePath: '',
      imageUseSimilarityScan: false,
      imageOnlySearchCovers: false,
      imageShowExpunged: false
    };
    this.showSearchResultScene = true;
    this.saveNavigationCache();
    setTimeout(() => {
      this.refreshSearchResultNavigationCache();
    }, 0);
  }

  private openLocalSearchBar(): void {
    this.localSearchBarVisible = true;
    this.searchSubmitted = false;
    this.galleries = [];
    this.resultCount = '';
    this.nextUrl = '';
    this.statusText = '';
    this.saveListCache();
    this.saveNavigationCache();
  }

  private closeLocalSearchBar(): void {
    this.localSearchBarVisible = false;
    this.searchSubmitted = true;
    this.keyword = '';
    this.searchMode = ListMode.Normal;
    this.searchCategory = GalleryCategory.None;
    this.searchAdvancedPanelOpened = false;
    this.advancedSearchEnabled = false;
    this.advanceSearch = DEFAULT_ADVANCE_SEARCH;
    this.minRating = -1;
    this.hasFirstRefresh = false;
    this.saveListCache();
    this.saveNavigationCache();
    this.loadListPage(0);
  }

  private closeSearchResultScene(): void {
    this.showSearchResultScene = false;
    this.searchResultDraft = createEmptySearchResultDraft();
    this.saveNavigationCache();
    setTimeout(() => {
      setActiveBackHandler(() => this.handleSystemBack());
    }, 0);
  }

  private toggleFilter(): void {
    if (this.isSearchResultScene) {
      this.toggleSearchFilterEnabled();
      return;
    }
    this.accountFilterEnabled = !this.accountFilterEnabled;
    this.fabExpanded = false;
    ehSettingsStore.setValue('use_account_default_filter', this.accountFilterEnabled ? 'On' : 'Off');
    this.statusText = this.accountFilterEnabled ? 'Account filters enabled' : 'Account filters disabled';
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSettingsStore.save(context).catch((error: Error) => {
        this.statusText = 'Save setting failed: ' + error.message;
        this.saveListCache();
      });
    }
    this.saveListCache();
    this.loadListPage(0, false);
  }

  private toggleSearchFilterEnabled(): void {
    const nextEnabled = !this.searchFilterEnabled;
    this.searchFilterEnabled = nextEnabled;
    this.advanceSearch = nextEnabled ? (this.advanceSearch & ~ACCOUNT_DEFAULT_FILTER_DISABLE_FLAGS) :
      (this.advanceSearch | ACCOUNT_DEFAULT_FILTER_DISABLE_FLAGS);
    this.fabExpanded = false;
    this.statusText = this.searchFilterEnabled ? 'Search filters enabled' : 'Search filters disabled';
    this.searchSubmitted = true;
    this.saveListCache();
    this.loadListPage(0, false);
  }

  private jumpGalleryPage(): void {
    this.fabExpanded = false;
  }

  private openRandomGallery(): void {
    this.fabExpanded = false;
    if (this.galleries.length === 0) {
      this.statusText = 'Random needs a loaded gallery list';
      return;
    }
    const index = Math.floor(Math.random() * this.galleries.length);
    this.loadDetail(this.galleries[index]);
  }

  private loadDetail(gallery: GalleryInfo): void {
    this.restoreDetailWithFade = false;
    this.showDetail = true;
    const detailLink = createGalleryDetailLinkFromGallery(gallery, this.activeSite, this.requestUrl);
    this.detailLink = detailLink;
    this.detail = initialDetailForLink(detailLink);
    this.detailStatus = '';
    this.detailRequestUrl = detailLink.url;
    this.renderVersion++;
    this.saveNavigationCache();
  }

  private isAppendExhausted(result: GalleryListLoadResult, loadedPageIndex: number, addedCount: number): boolean {
    if (addedCount <= 0) {
      return true;
    }
    if (result.nextUrl.length > 0) {
      return false;
    }
    if (result.nextPage >= 0 && result.nextPage !== loadedPageIndex) {
      return false;
    }
    return result.pages <= 0 || loadedPageIndex >= result.pages - 1;
  }

  private openDetailByToken(gid: number, token: string): void {
    this.restoreDetailWithFade = false;
    this.showDetail = true;
    const detailLink = createGalleryDetailLink(gid, token, 'Gallery ' + gid.toString(), this.activeSite, this.requestUrl);
    this.detailLink = detailLink;
    this.detail = initialDetailForLink(detailLink);
    this.detailStatus = '';
    this.detailRequestUrl = detailLink.url;
    this.renderVersion++;
    this.saveNavigationCache();
  }

  private closeDetail(): void {
    this.restoreDetailWithFade = false;
    this.showDetail = false;
    this.showReader = false;
    this.detailLink = createEmptyGalleryDetailLink();
    this.detail = createEmptyDetail();
    this.detailStatus = 'Tap a gallery row to load detail';
    this.detailRequestUrl = '';
    this.detailScrollOffset = 0;
    this.renderVersion++;
    this.saveNavigationCache();
  }

  private closeReader(): void {
    if (this.readerClosing) {
      return;
    }
    this.readerClosing = true;
    this.restoreDetailWithFade = this.showDetail;
    if (!isEmbeddedReaderActive()) {
      this.showReader = false;
      this.restoreBackHandler();
      this.clearRestoreDetailFadeLater();
      this.readerClosing = false;
      return;
    }
    leaveEmbeddedReaderFullscreen().then(() => {
      this.showReader = false;
      this.restoreBackHandler();
      this.clearRestoreDetailFadeLater();
    }).finally(() => {
      this.readerClosing = false;
    });
  }

  private clearRestoreDetailFadeLater(): void {
    setTimeout(() => {
      if (!this.showReader) {
        this.restoreDetailWithFade = false;
      }
    }, 260);
  }

  private restoreBackHandler(): void {
    setTimeout(() => {
      setActiveBackHandler(() => this.handleSystemBack());
    }, 0);
  }

  private openCardActions(gallery: GalleryInfo): void {
    if (gallery.gid <= 0 || gallery.token.length === 0) {
      return;
    }
    this.fabExpanded = false;
    this.cardActionGallery = gallery;
    this.cardActionVisible = true;
  }

  private closeCardActions(): void {
    this.cardActionVisible = false;
    this.cardActionGallery = createEmptyGallery();
  }

  private galleryShareUrl(gallery: GalleryInfo): string {
    return EhUrl.getGalleryDetailUrl(gallery.gid, gallery.token, 0, false, this.activeSite);
  }

  private shareCardGallery(gallery: GalleryInfo): void {
    const context = getAbilityContext();
    const url = this.galleryShareUrl(gallery);
    this.closeCardActions();
    if (context === undefined || url.length === 0) {
      this.statusText = 'Share failed: Ability context is not ready';
      this.renderVersion++;
      return;
    }
    const shareData: systemShare.SharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.PLAIN_TEXT,
      content: url,
      title: galleryDisplayTitle(gallery),
      description: 'EhViewer'
    });
    const controller = new systemShare.ShareController(shareData);
    controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DETAIL
    }).then(() => {
      this.statusText = 'Share panel closed';
      this.renderVersion++;
    }).catch((error: Error) => {
      this.statusText = 'Share failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private toggleCardDownload(gallery: GalleryInfo): void {
    this.closeCardActions();
    const queued = toggleGalleryDownload(gallery);
    this.statusText = queued ? 'Added to download list' : 'Removed from download list';
    this.renderVersion++;
  }

  private deleteHistoryGallery(gallery: GalleryInfo): void {
    const context = getAbilityContext();
    this.closeCardActions();
    if (gallery.gid <= 0) {
      return;
    }
    if (context === undefined) {
      ehHistoryStore.removeGallery(gallery.gid);
      this.galleries = this.galleries.filter((item: GalleryInfo) => item.gid !== gallery.gid);
      this.statusText = 'History deleted';
      this.renderVersion++;
      this.saveListCache();
      return;
    }
    ehHistoryStore.ensureLoaded(context).then(() => {
      ehHistoryStore.removeGallery(gallery.gid);
      return ehHistoryStore.save(context);
    }).then(() => {
      this.statusText = 'History deleted';
      this.loadListPage(0, false);
    }).catch((error: Error) => {
      this.statusText = 'Delete history failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private openSearchResult(request: DetailSearchRequest): void {
    this.showReader = false;
    this.searchResultDraft = {
      keyword: request.keyword,
      mode: request.mode,
      category: request.category,
      advancedEnabled: false,
      advanceSearch: DEFAULT_ADVANCE_SEARCH,
      minRating: -1,
      pageFrom: -1,
      pageTo: -1,
      filterActive: false,
      searchFilterEnabled: true,
      searchAdvancedPanelOpened: false,
      submitted: true,
      sourceRoute: GalleryRoute.Home,
      imagePath: request.imagePath,
      imageUseSimilarityScan: request.useSimilarityScan,
      imageOnlySearchCovers: request.onlySearchCovers,
      imageShowExpunged: request.showExpunged
    };
    this.detailStatus = request.title;
    this.fabExpanded = false;
    this.showSearchResultScene = true;
    this.saveNavigationCache();
    setTimeout(() => {
      this.refreshSearchResultNavigationCache();
    }, 0);
  }

  private updateSceneContentWidth(width: number): void {
    const normalized = Math.floor(width);
    if (normalized <= 0 || Number.isNaN(normalized) || Math.abs(this.sceneContentWidth - normalized) < 1) {
      return;
    }
    this.sceneContentWidth = normalized;
  }

  onSplitPaneRatioRevisionChange(): void {
    if (!this.splitDragging) {
      this.splitListRatio = splitPaneCurrentRatio();
    }
  }

  private useSplitLayout(): boolean {
    return !this.isSearchResultScene && splitPaneModeEnabled() && this.sceneContentWidth >= SPLIT_PANE_BREAKPOINT &&
      this.showDetail && !this.showReader;
  }

  private splitListPaneWidth(): number {
    return splitPaneListWidth(this.sceneContentWidth, this.splitListRatio);
  }

  private splitSidePaneWidth(): number {
    if (!this.useSplitLayout()) {
      return this.sceneContentWidth > 0 ? this.sceneContentWidth : 0;
    }
    return splitPaneSideWidth(this.sceneContentWidth, this.splitListPaneWidth());
  }

  private updateSplitPaneByOffset(offsetX: number): void {
    if (this.sceneContentWidth <= 0) {
      return;
    }
    const targetWidth = splitPaneWidthFromDrag(this.sceneContentWidth, this.splitDragStartWidth, offsetX);
    this.splitListRatio = splitPaneRatioForWidth(this.sceneContentWidth, targetWidth);
  }

  private finishSplitPaneDrag(): void {
    this.splitDragging = false;
    saveSplitPaneRatio(this.splitListRatio);
  }

  build() {
    Column() {
      if (!this.isSearchResultScene && this.showSearchResultScene) {
        GalleryListScene({
          sceneTitle: this.searchResultDraft.keyword.length > 0 ? this.searchResultDraft.keyword : 'Search',
          listMode: 'Search',
          sourceRoute: this.searchResultDraft.sourceRoute,
          initialKeyword: this.searchResultDraft.keyword,
          initialSearchMode: this.searchResultDraft.mode,
          initialSearchCategory: this.searchResultDraft.category,
          initialAdvancedSearchEnabled: this.searchResultDraft.advancedEnabled,
          initialAdvanceSearch: this.searchResultDraft.advanceSearch,
          initialMinRating: this.searchResultDraft.minRating,
          initialPageFrom: this.searchResultDraft.pageFrom,
          initialPageTo: this.searchResultDraft.pageTo,
          initialSearchFilterEnabled: this.searchResultDraft.searchFilterEnabled,
          initialSearchSubmitted: this.searchResultDraft.submitted,
          initialSearchAdvancedPanelOpened: this.searchResultDraft.searchAdvancedPanelOpened,
          initialImagePath: this.searchResultDraft.imagePath,
          initialImageUseSimilarityScan: this.searchResultDraft.imageUseSimilarityScan,
          initialImageOnlySearchCovers: this.searchResultDraft.imageOnlySearchCovers,
          initialImageShowExpunged: this.searchResultDraft.imageShowExpunged,
          isSearchResultScene: true,
          onBack: () => {
            this.closeSearchResultScene();
          }
        })
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.move(TransitionEdge.END).animation({ duration: 260, curve: Curve.EaseOut }),
            TransitionEffect.move(TransitionEdge.END).animation({ duration: 220, curve: Curve.EaseIn })))
      } else if (this.showReader) {
        ReaderSessionScene({
          restoreAppChromeOnExit: true,
          onBack: () => {
            this.closeReader();
          }
        })
          .width('100%')
          .height('100%')
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          GalleryListContent({
            sceneTitle: this.sceneTitle,
            listMode: this.listMode,
            keyword: this.keyword,
            searchTitle: this.useLocalProvider && this.keyword.trim().length === 0 ? this.sceneTitle :
              this.favoriteSceneTitle(),
            actionsExpanded: this.fabExpanded,
            filterActive: this.filterActive,
            showFavoriteButton: this.sourceRoute === GalleryRoute.Favorites && !this.isSearchResultScene,
            showBookmarkButton: this.canUseBookmarks(),
            bookmarks: this.searchBookmarks,
            favoriteCat: this.favoriteCat,
            favoriteCategories: this.favoriteCategories,
            favoriteLocalCount: this.favoriteLocalCount,
            accountFilterEnabled: this.accountFilterEnabled,
            searchFilterEnabled: this.searchFilterEnabled,
            showSearchButton: (routeUsesKeyword(this.sourceRoute) || this.useLocalProvider) && !this.isSearchResultScene,
            showBackButton: this.isSearchResultScene,
            searchPlaceholder: this.useLocalProvider ? 'Search history' : 'Search galleries',
            isSearchResultScene: this.isSearchResultScene,
            useLocalSearchBar: this.useLocalProvider && this.localSearchBarVisible,
            searchSubmitted: this.searchSubmitted,
            searchModeValue: this.searchMode,
            searchCategory: this.searchCategory,
            advancedSearchEnabled: this.advancedSearchEnabled,
            advanceSearch: this.advanceSearch,
            minRating: this.minRating,
            pageIndex: this.pageIndex,
            totalPages: this.totalPages,
            resultCount: this.resultCount,
            canJump: this.totalPages > 1 || this.totalPages < 0 || this.nextUrl.length > 0,
            canRandom: this.galleries.length > 0,
            statusText: this.statusText,
            requestUrl: this.requestUrl,
            isLoadingMore: this.isLoadingMore,
            galleries: this.galleries,
            onKeywordChange: (value: string) => {
              if (value === this.keyword) {
                return;
              }
              this.keyword = value;
              if (this.isSearchResultScene || this.useLocalProvider) {
                this.searchSubmitted = false;
                this.galleries = [];
                this.resultCount = '';
                this.nextUrl = '';
                this.statusText = '';
                this.saveListCache();
              }
            },
            onSearchFocus: () => {
            },
            onFavoriteCatChange: (favCat: number) => {
              this.changeFavoriteCat(favCat);
            },
            onFavoriteDrawerOpen: () => {
              this.refreshLocalFavoriteCount();
            },
            onBookmarkDrawerOpen: () => {
              this.refreshSearchBookmarks();
            },
            onBookmarkSettings: () => {
              this.openBookmarkManager();
            },
            onAddBookmark: () => {
              this.openAddBookmarkDialog();
            },
            onSelectBookmark: (bookmark: SearchBookmarkInfo) => {
              this.openSearchBookmark(bookmark);
            },
            onDeleteBookmark: (bookmark: SearchBookmarkInfo) => {
              this.removeSearchBookmark(bookmark);
            },
            onSearchModeChange: (mode: ListMode) => {
              if (mode === this.searchMode) {
                return;
              }
              this.searchMode = mode;
              if (this.isSearchResultScene || this.useLocalProvider) {
                this.searchSubmitted = false;
              }
            },
            onSearchCategoryChange: (category: number) => {
              if (category === this.searchCategory) {
                return;
              }
              this.searchAdvancedPanelOpened = true;
              this.searchCategory = category;
              if (this.isSearchResultScene || this.useLocalProvider) {
                this.searchSubmitted = false;
              }
            },
            onAdvancedEnabledChange: (enabled: boolean) => {
              if (enabled === this.advancedSearchEnabled) {
                return;
              }
              this.searchAdvancedPanelOpened = true;
              this.advancedSearchEnabled = enabled;
              if (this.isSearchResultScene || this.useLocalProvider) {
                this.searchSubmitted = false;
              }
            },
            onAdvanceSearchChange: (flags: number) => {
              if (flags === this.advanceSearch) {
                return;
              }
              this.searchAdvancedPanelOpened = true;
              this.advanceSearch = flags;
              if (this.isSearchResultScene || this.useLocalProvider) {
                this.searchSubmitted = false;
              }
            },
            onMinRatingChange: (rating: number) => {
              if (rating === this.minRating) {
                return;
              }
              this.searchAdvancedPanelOpened = true;
              this.minRating = rating;
              if (this.isSearchResultScene || this.useLocalProvider) {
                this.searchSubmitted = false;
              }
            },
            onPageJump: (page: number) => {
              this.loadListPage(Math.max(0, page - 1));
            },
            onSeekJump: (appendParam: string) => {
              const targetUrl = buildJumpSeekUrl(this.nextUrl.length > 0 ? this.absoluteListUrl(this.nextUrl) :
                this.requestUrl, appendParam);
              if (targetUrl.length === 0) {
                this.statusText = 'No other page to jump to';
                return;
              }
              this.fabExpanded = false;
              this.loadRemoteUrl(targetUrl);
            },
            onMenu: () => {
              this.onMenu();
            },
            onBack: () => {
              if (this.useLocalProvider && this.localSearchBarVisible) {
                this.closeLocalSearchBar();
              } else if (this.isSearchResultScene) {
                this.closeSearchResultToParent();
              } else {
                this.onBack();
              }
            },
            onSearch: () => {
              if (this.useLocalProvider && !this.localSearchBarVisible) {
                this.openLocalSearchBar();
              } else if (this.isSearchResultScene || this.useLocalProvider) {
                this.applySearch();
              } else {
                this.openSearchScene();
              }
            },
            onRefresh: () => {
              if ((this.isSearchResultScene || this.useLocalProvider) && !this.searchSubmitted) {
                this.applySearch();
                return;
              }
              this.loadListPage(0, this.galleries.length > 0);
            },
            onRefreshPull: (done: () => void) => {
              if ((this.isSearchResultScene || this.useLocalProvider) && !this.searchSubmitted) {
                this.applySearch();
                done();
                return;
              }
              this.loadListPage(0, this.galleries.length > 0, done);
            },
            onLoadMore: () => {
              this.loadAppendPage();
            },
            onToggleActions: () => {
              this.fabExpanded = !this.fabExpanded;
            },
            onFilter: () => {
              this.toggleFilter();
            },
            onAdvancedPanelOpen: () => {
              this.searchAdvancedPanelOpened = true;
            },
            onJump: () => {
              this.jumpGalleryPage();
            },
            onRandom: () => {
              this.openRandomGallery();
            },
            onImageSearch: (path: string, useSimilarityScan: boolean, onlySearchCovers: boolean) => {
              this.startImageSearch(path, useSimilarityScan, onlySearchCovers);
            },
            onSelectGallery: (gallery: GalleryInfo) => {
              this.loadDetail(gallery);
            },
            onLongPressGallery: (gallery: GalleryInfo) => {
              this.openCardActions(gallery);
            },
            onSystemBack: () => {
              return this.handleSystemBack();
            },
            scrollResetVersion: this.scrollResetVersion,
            initialScrollOffset: this.listScrollOffset,
            onScrollUpdate: (offset: number) => {
              this.listScrollOffset = offset;
              updateGalleryListScrollCache(this.cacheKey(), this.listScrollOffset);
            }
          })
            .width(this.useSplitLayout() ? this.splitListPaneWidth() : '100%')
            .height('100%')
            .animation({
              duration: this.splitDragging ? 0 : 220,
              curve: Curve.EaseOut
            })

          if (this.showBookmarkManager) {
            SearchBookmarkManagerScene({
              bookmarks: this.searchBookmarks,
              statusBarHeight: this.galleryStatusBarVp(),
              onBack: () => {
                this.closeBookmarkManager();
              },
              onRename: (bookmark: SearchBookmarkInfo, name: string) => {
                this.renameSearchBookmark(bookmark, name);
              },
              onMoveIndex: (from: number, to: number) => {
                this.moveSearchBookmarkToIndex(from, to);
              },
              onDelete: (bookmark: SearchBookmarkInfo) => {
                this.removeSearchBookmark(bookmark);
              }
            })
              .width('100%')
              .height('100%')
              .transition(TransitionEffect.asymmetric(
                TransitionEffect.move(TransitionEdge.END).animation({ duration: 260, curve: Curve.EaseOut }),
                TransitionEffect.move(TransitionEdge.END).animation({ duration: 220, curve: Curve.EaseIn })))
              .zIndex(29)
          }

          if (this.addBookmarkDialogVisible) {
            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width('100%')
                .height('100%')
                .backgroundColor(themeScrimColor())
                .onClick(() => {
                  this.addBookmarkDialogVisible = false;
                })

              Column({ space: 12 }) {
                Row() {
                  Text(uiText('Add bookmark'))
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
                  .backgroundColor(themeSurfaceVariant())
                  .onClick(() => {
                    this.addBookmarkDialogVisible = false;
                  })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                TextInput({ text: this.addBookmarkName, placeholder: uiText('Bookmark name') })
                  .height(42)
                  .width('100%')
                  .fontSize(15)
                  .fontColor(themePrimaryText())
                  .backgroundColor(themeFieldBackground())
                  .borderRadius(6)
                  .padding({ left: 12, right: 12 })
                  .onChange((value: string) => {
                    this.addBookmarkName = value;
                  })
                  .onSubmit(() => {
                    this.confirmAddBookmark();
                  })

                Text(bookmarkSummary(this.addBookmarkDraft))
                  .fontSize(12)
                  .fontColor(themeSecondaryText())
                  .width('100%')
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Row({ space: 10 }) {
                  Button(uiText('Cancel'))
                    .height(40)
                    .layoutWeight(1)
                    .fontSize(14)
                    .fontColor(themePrimaryText())
                    .backgroundColor(themeSurfaceVariant())
                    .borderRadius(20)
                    .onClick(() => {
                      this.addBookmarkDialogVisible = false;
                    })
                  Button(uiText('Save'))
                    .height(40)
                    .layoutWeight(1)
                    .fontSize(14)
                    .fontColor(themeOnPrimaryText())
                    .backgroundColor(themePrimaryColor())
                    .borderRadius(20)
                    .onClick(() => {
                      this.confirmAddBookmark();
                    })
                }
                .width('100%')
              }
              .width('72%')
              .constraintSize({ maxWidth: 340, minWidth: 280 })
              .padding(18)
              .backgroundColor(themeSurface())
              .borderRadius(10)
              .shadow({ radius: 22, color: themeShadowColor(), offsetY: 8 })
              .onClick(() => {})
            }
              .width('100%')
              .height('100%')
              .zIndex(30)
          }

          if (this.useSplitLayout()) {
            SplitPaneDivider({
              x: this.splitListPaneWidth(),
              dragging: this.splitDragging,
              onSplitDragStart: () => {
                this.splitDragging = true;
                this.splitDragStartWidth = this.splitListPaneWidth();
              },
              onSplitDragUpdate: (offsetX: number) => {
                this.updateSplitPaneByOffset(offsetX);
              },
              onSplitDragEnd: () => {
                this.finishSplitPaneDrag();
              }
            })
          }

          if (this.showDetail) {
            GalleryDetailHostScene({
              detailLink: this.detailLink,
              listRequestUrl: this.requestUrl,
              initialDetailScrollOffset: this.detailScrollOffset,
              onBack: () => {
                this.closeDetail();
              },
              onShowEmbeddedReader: () => {
                this.showReader = true;
              },
              onOpenSearch: (request: DetailSearchRequest) => {
                this.openSearchResult(request);
              },
              onDetailLoaded: (detail: GalleryDetail) => {
                this.detail = detail;
              },
              onDetailScrollUpdate: (offset: number) => {
                this.detailScrollOffset = offset;
              }
            })
              .width(this.useSplitLayout() ? this.splitSidePaneWidth() : '100%')
              .height('100%')
              .translate({ x: this.useSplitLayout() ? this.splitListPaneWidth() + 1 : 0 })
              .zIndex(5)
              .animation({
                duration: this.splitDragging ? 0 : 220,
                curve: Curve.EaseOut
              })
              .transition(this.restoreDetailWithFade ?
                TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }) :
                TransitionEffect.move(TransitionEdge.END).animation({ duration: 300, curve: Curve.EaseOut }))
          }

          if (this.cardActionVisible) {
            GalleryCardActionOverlay({
              gallery: this.cardActionGallery,
              isHistory: this.sourceRoute === GalleryRoute.History,
              onDismiss: () => {
                this.closeCardActions();
              },
              onShare: (gallery: GalleryInfo) => {
                this.shareCardGallery(gallery);
              },
              onDownload: (gallery: GalleryInfo) => {
                this.toggleCardDownload(gallery);
              },
              onDeleteHistory: (gallery: GalleryInfo) => {
                this.deleteHistoryGallery(gallery);
              }
            })
              .zIndex(30)
          }
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateSceneContentWidth(areaDimensionToVp(newArea.width, (value: number) => this.getUIContext().px2vp(value)));
    })
  }
}


@Component
struct ImageSearchPanel {
  @Prop panelWidth: number = 320;
  @Prop panelMaxHeight: number = 420;
  onClose: () => void = () => {
  };
  onSearch: (path: string, useSimilarityScan: boolean, onlySearchCovers: boolean) => void =
    (_path: string, _useSimilarityScan: boolean, _onlySearchCovers: boolean) => {
    };
  @State selectedPath: string = '';
  @State statusText: string = 'No image selected';
  @State useSimilarityScan: boolean = true;
  @State onlySearchCovers: boolean = false;
  @State uploadOriginalPhoto: boolean = true;
  @State busy: boolean = false;

  private selectedName(): string {
    if (this.selectedPath.length === 0) {
      return uiText('No image selected');
    }
    const slash = Math.max(this.selectedPath.lastIndexOf('/'), this.selectedPath.lastIndexOf('\\'));
    return slash >= 0 ? this.selectedPath.substring(slash + 1) : this.selectedPath;
  }

  private async chooseFromAlbum(): Promise<void> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      if (this.uploadOriginalPhoto) {
        options.assetCompatibleCapability = {
          supportedHighResolution: true
        } as photoAccessHelper.AssetCompatibleCapability;
      }
      const photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const result = await photoPicker.select(options);
      if (result.photoUris.length > 0) {
        await this.usePickedUri(result.photoUris[0], result.isOriginalPhoto);
      }
    } catch (error) {
      this.busy = false;
      this.statusText = 'Image selection failed';
    }
  }

  private async chooseFromFile(): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Ability context is not ready';
      return;
    }
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['图片(.jpg,.jpeg,.png,.webp,.gif)|.jpg,.jpeg,.png,.webp,.gif'];
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris = await documentPicker.select(options);
      if (uris.length > 0) {
        await this.usePickedUri(uris[0], true);
      }
    } catch (error) {
      this.busy = false;
      this.statusText = 'Image selection failed';
    }
  }

  private async usePickedUri(uri: string, isOriginalPhoto: boolean): Promise<void> {
    this.busy = true;
    this.statusText = 'Preparing image...';
    const path = await copyImageSearchSourceToCache(uri);
    this.busy = false;
    if (path.length === 0) {
      this.statusText = 'Image selection failed';
      return;
    }
    this.selectedPath = path;
    this.statusText = isOriginalPhoto ? 'Original image selected' : 'Compatible image selected';
  }

  private submit(): void {
    if (this.selectedPath.length === 0 || this.busy) {
      this.statusText = 'No image selected';
      return;
    }
    this.onSearch(this.selectedPath, this.useSimilarityScan, this.onlySearchCovers);
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Row() {
          Text(uiText('Image search'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([themePrimaryText()])
          }
          .width(34)
          .height(34)
          .backgroundColor(themeFieldBackground())
          .onClick(() => {
            this.onClose();
          })
        }
        .width('100%')

        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(18)
                .fontColor([themeOnPrimaryText()])
              Text(uiText('From album'))
                .fontSize(13)
                .fontColor(themeOnPrimaryText())
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .width('100%')
          }
          .height(38)
          .layoutWeight(1)
          .borderRadius(6)
          .backgroundColor(themePrimaryColor())
          .enabled(!this.busy)
          .onClick(() => {
            this.chooseFromAlbum();
          })

          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.folder'))
                .fontSize(18)
                .fontColor([themePrimaryColor()])
              Text(uiText('From file'))
                .fontSize(13)
                .fontColor(themePrimaryColor())
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .width('100%')
          }
          .height(38)
          .layoutWeight(1)
          .borderRadius(6)
          .backgroundColor(themeFieldBackground())
          .enabled(!this.busy)
          .onClick(() => {
            this.chooseFromFile();
          })
        }
        .width('100%')

        Column({ space: 4 }) {
          Text(uiText('Selected image'))
            .fontSize(12)
            .fontColor(themeSecondaryText())
          Text(this.selectedName())
            .fontSize(13)
            .fontColor(this.selectedPath.length > 0 ? themePrimaryText() : themeTertiaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding(10)
        .backgroundColor(themeFieldBackground())
        .borderRadius(6)

        Row() {
          Text(uiText('Upload original image'))
            .fontSize(14)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.uploadOriginalPhoto })
            .onChange((isOn: boolean) => {
              this.uploadOriginalPhoto = isOn;
            })
        }
        .width('100%')

        Row() {
          Text(uiText('Similarity scan'))
            .fontSize(14)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.useSimilarityScan })
            .onChange((isOn: boolean) => {
              this.useSimilarityScan = isOn;
            })
        }
        .width('100%')

        Row() {
          Text(uiText('Only cover search'))
            .fontSize(14)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.onlySearchCovers })
            .onChange((isOn: boolean) => {
              this.onlySearchCovers = isOn;
            })
        }
        .width('100%')

        Text(uiStatusText(this.statusText))
          .fontSize(12)
          .fontColor(this.statusText === 'Image selection failed' ? themeDangerText() : themeSecondaryText())
          .width('100%')
          .maxLines(2)

        Button(uiText('Search image'))
          .height(40)
          .width('100%')
          .fontSize(14)
          .fontColor(themeOnPrimaryText())
          .backgroundColor(themePrimaryColor())
          .borderRadius(6)
          .enabled(this.selectedPath.length > 0 && !this.busy)
          .onClick(() => {
            this.submit();
          })
      }
      .width('100%')
      .padding(14)
    }
    .width(this.panelWidth)
    .constraintSize({ maxHeight: this.panelMaxHeight })
    .backgroundColor(themeSurface())
    .borderRadius(8)
    .shadow({ radius: 14, color: themeShadowColor(), offsetX: 0, offsetY: 4 })
  }
}

@Component
export struct GalleryCardActionOverlay {
  @Prop gallery: GalleryInfo = createEmptyGallery();
  @Prop isHistory: boolean = false;
  onDismiss: () => void = () => {
  };
  onShare: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  onDownload: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  onDeleteHistory: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };

  @Builder
  private actionRow(label: string, symbolIcon: Resource, color: string, onTap: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row() {
        SymbolGlyph(symbolIcon)
          .fontSize(20)
          .fontColor([color])
        Text(uiText(label))
          .fontSize(15)
          .fontColor(color)
          .margin({ left: 12 })
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height(48)
    .backgroundColor(Color.Transparent)
    .borderRadius(0)
    .onClick(onTap)
  }

  @Builder
  private divider() {
    Divider()
      .height(1)
      .color(themeFieldBackground())
      .margin({ left: 16, right: 16 })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(themeScrimColor())
        .onClick(() => {
          this.onDismiss();
        })

      Column({ space: 0 }) {
        Text(galleryDisplayTitle(this.gallery))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 10 })

        this.divider()

        this.actionRow('Share', $r('sys.symbol.share'), themePrimaryText(), () => {
          this.onShare(this.gallery);
        })

        this.divider()

        this.actionRow(downloadButtonText(this.gallery.gid), $r('sys.symbol.arrow_down_circle'), themePrimaryText(), () => {
          this.onDownload(this.gallery);
        })

        if (this.isHistory) {
          this.divider()

          this.actionRow('Delete history', $r('sys.symbol.trash'), themeDangerText(), () => {
            this.onDeleteHistory(this.gallery);
          })
        }
      }
      .width('78%')
      .constraintSize({ maxWidth: 360 })
      .padding({ top: 4, bottom: 6 })
      .backgroundColor(themeSurface())
      .borderRadius(10)
      .clip(true)
      .shadow({ radius: 18, color: themeShadowColor(), offsetY: 8 })
    }
    .width('100%')
    .height('100%')
  }
}


@Component
export struct GalleryListContent {
  @Prop sceneTitle: string = '';
  @Prop listMode: string = '';
  @Prop @Watch('onSearchKeywordChanged') keyword: string = '';
  @Prop searchTitle: string = '';
  @Prop actionsExpanded: boolean = false;
  @Prop filterActive: boolean = false;
  @Prop showFavoriteButton: boolean = false;
  @Prop showBookmarkButton: boolean = false;
  @Prop bookmarks: SearchBookmarkInfo[] = [];
  @Prop favoriteCat: number = FavListUrlBuilder.FAV_CAT_ALL;
  @Prop favoriteCategories: FavoriteCategoryInfo[] = [];
  @Prop favoriteLocalCount: number = -1;
  @Prop accountFilterEnabled: boolean = true;
  @Prop searchFilterEnabled: boolean = true;
  @Prop showSearchButton: boolean = false;
  @Prop showBackButton: boolean = false;
  @Prop searchPlaceholder: string = 'Search galleries';
  @Prop isSearchResultScene: boolean = false;
  @Prop useLocalSearchBar: boolean = false;
  @Prop searchSubmitted: boolean = true;
  @Prop searchModeValue: ListMode = ListMode.Normal;
  @Prop searchCategory: number = GalleryCategory.None;
  @Prop advancedSearchEnabled: boolean = false;
  @Prop advanceSearch: number = DEFAULT_ADVANCE_SEARCH;
  @Prop minRating: number = -1;
  @Prop @Watch('onPageChanged') pageIndex: number = 0;
  @Prop totalPages: number = 0;
  @Prop resultCount: string = '';
  @Prop canJump: boolean = false;
  @Prop canRandom: boolean = false;
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  @Prop isLoadingMore: boolean = false;
  @Prop @Watch('onGalleriesChanged') galleries: GalleryInfo[] = [];
  @Prop @Watch('onScrollReset') scrollResetVersion: number = 0;
  onKeywordChange: (value: string) => void = () => {
  };
  onSearchFocus: () => void = () => {
  };
  onFavoriteCatChange: (favCat: number) => void = (_favCat: number) => {
  };
  onFavoriteDrawerOpen: () => void = () => {
  };
  onBookmarkDrawerOpen: () => void = () => {
  };
  onBookmarkSettings: () => void = () => {
  };
  onAddBookmark: () => void = () => {
  };
  onSelectBookmark: (bookmark: SearchBookmarkInfo) => void = (_bookmark: SearchBookmarkInfo) => {
  };
  onDeleteBookmark: (bookmark: SearchBookmarkInfo) => void = (_bookmark: SearchBookmarkInfo) => {
  };
  onSearchModeChange: (mode: ListMode) => void = (_mode: ListMode) => {
  };
  onSearchCategoryChange: (category: number) => void = (_category: number) => {
  };
  onAdvancedEnabledChange: (enabled: boolean) => void = (_enabled: boolean) => {
  };
  onAdvanceSearchChange: (flags: number) => void = (_flags: number) => {
  };
  onMinRatingChange: (rating: number) => void = (_rating: number) => {
  };
  onPageJump: (page: number) => void = (_page: number) => {
  };
  onSeekJump: (appendParam: string) => void = (_appendParam: string) => {
  };
  onMenu: () => void = () => {
  };
  onBack: () => void = () => {
  };
  onSearch: () => void = () => {
  };
  onRefresh: () => void = () => {
  };
  onLoadMore: () => void = () => {
  };
  onToggleActions: () => void = () => {
  };
  onFilter: () => void = () => {
  };
  onAdvancedPanelOpen: () => void = () => {
  };
  onJump: () => void = () => {
  };
  onRandom: () => void = () => {
  };
  onImageSearch: (path: string, useSimilarityScan: boolean, onlySearchCovers: boolean) => void =
    (_path: string, _useSimilarityScan: boolean, _onlySearchCovers: boolean) => {
    };
  onSelectGallery: (gallery: GalleryInfo) => void = () => {
  };
  onLongPressGallery: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  onSystemBack: () => boolean = () => false;
  initialScrollOffset: number = 0;
  onScrollUpdate: (offset: number) => void = () => {
  };
  @State contentWidth: number = 0;
  @State refreshing: boolean = false;
  @State advancedPanelVisible: boolean = false;
  @State pageJumpDraft: string = '';
  @State seekYearDraft: string = '';
  @State seekMonthDraft: string = '';
  @State seekDayDraft: string = '';
  @State jumpPanelVisible: boolean = false;
  @State imageSearchPanelVisible: boolean = false;
  @State selectedTagNamespaces: string[] = [];
  @State searchSuggestionItems: SearchSuggestionItem[] = [];
  @State searchSuggestionRevision: number = 0;
  onRefreshPull: (done: () => void) => void = (done: () => void) => {
    done();
  };
  private readonly REFRESH_OFFSET: number = 42;
  @State viewportHeight: number = 0;
  private listScroller: Scroller = new Scroller();
  private loadMorePending: boolean = false;
  private restoredScroll: boolean = false;
  @State private contentOpacity: number = 1;
  @State toolbarOffsetY: number = 0;
  @State favoriteDrawerVisible: boolean = false;
  @State favoriteDrawerOffsetX: number = 288;
  @State favoriteDrawerOverlayOpacity: number = 0;
  @State bookmarkDrawerVisible: boolean = false;
  @State bookmarkDrawerOffsetX: number = 288;
  @State bookmarkDrawerOverlayOpacity: number = 0;
  private toolbarRestoring: boolean = false;
  private barHeight: number = 56; // matches EhNavBar body height
  private readonly FAVORITE_DRAWER_WIDTH: number = 288;
  @StorageProp('statusBarHeight') statusBarHeightPx: number = 0;

  onScrollReset(): void {
    // Scroll back to the top when scrollResetVersion changes.
    this.snapListToTop();
  }

  onPageChanged(): void {
    this.syncPageJumpDraft();
  }

  onSearchKeywordChanged(): void {
    this.refreshSearchSuggestions();
  }

  onGalleriesChanged(): void {
  }

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  private favoriteDrawerLeft(): number {
    const width = this.contentWidth > 0 ? this.contentWidth :
      mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value));
    return Math.max(0, width - this.FAVORITE_DRAWER_WIDTH);
  }

  private bookmarkDrawerLeft(): number {
    const width = this.contentWidth > 0 ? this.contentWidth :
      mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value));
    return Math.max(0, width - this.FAVORITE_DRAWER_WIDTH);
  }

  private openFavoriteDrawer(): void {
    if (!this.showFavoriteButton || this.favoriteDrawerVisible) {
      return;
    }
    this.onFavoriteDrawerOpen();
    this.favoriteDrawerVisible = true;
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
      this.favoriteDrawerOffsetX = 0;
      this.favoriteDrawerOverlayOpacity = 0.45;
    });
  }

  private closeFavoriteDrawer(): void {
    if (!this.favoriteDrawerVisible) {
      return;
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
      this.favoriteDrawerOffsetX = this.FAVORITE_DRAWER_WIDTH;
      this.favoriteDrawerOverlayOpacity = 0;
    });
    setTimeout(() => {
      if (this.favoriteDrawerOffsetX > this.FAVORITE_DRAWER_WIDTH - 40) {
        this.favoriteDrawerVisible = false;
      }
    }, 220);
  }

  private handleOpenFavoriteDrawerPan(event: GestureEvent | undefined): void {
    if (!this.showFavoriteButton || this.favoriteDrawerVisible || event === undefined) {
      return;
    }
    const distanceX = event.offsetX;
    const distanceY = Math.abs(event.offsetY);
    const velocityX = event.velocityX;
    if (distanceX < -72 && distanceY < Math.max(48, Math.abs(distanceX) * 0.7) && velocityX <= 80) {
      this.openFavoriteDrawer();
    }
  }

  private handleOpenBookmarkDrawerPan(event: GestureEvent | undefined): void {
    if (!this.showBookmarkButton || this.showFavoriteButton || this.bookmarkDrawerVisible || event === undefined) {
      return;
    }
    const distanceX = event.offsetX;
    const distanceY = Math.abs(event.offsetY);
    const velocityX = event.velocityX;
    if (distanceX < -72 && distanceY < Math.max(48, Math.abs(distanceX) * 0.7) && velocityX <= 80) {
      this.openBookmarkDrawer();
    }
  }

  aboutToAppear(): void {
    setActiveBackHandler(() => this.handleContentBack());
    this.syncContentWidthFromWindow();
    this.syncPageJumpDraft();
    this.refreshSearchSuggestions();
    if (this.initialScrollOffset > 0) {
      this.contentOpacity = 0;
    }
    setTimeout(() => {
      this.syncContentWidthFromWindow();
    }, 0);
  }

  private handleContentBack(): boolean {
    if (this.bookmarkDrawerVisible) {
      this.closeBookmarkDrawer();
      return true;
    }
    if (this.favoriteDrawerVisible) {
      this.closeFavoriteDrawer();
      return true;
    }
    if (this.advancedPanelVisible) {
      this.closeAdvancedPanel();
      return true;
    }
    if (this.imageSearchPanelVisible) {
      this.closeImageSearchPanel();
      return true;
    }
    if (this.jumpPanelVisible) {
      this.closeJumpPanel();
      return true;
    }
    return this.onSystemBack();
  }

  private syncPageJumpDraft(): void {
    this.pageJumpDraft = (this.pageIndex + 1).toString();
  }

  private syncSeekDateDraft(): void {
    const now = new Date();
    this.seekYearDraft = now.getFullYear().toString();
    this.seekMonthDraft = (now.getMonth() + 1).toString();
    this.seekDayDraft = now.getDate().toString();
  }

  private submitPageJump(): void {
    if (this.totalPages < 0) {
      return;
    }
    const parsed = Number.parseInt(this.pageJumpDraft);
    if (Number.isNaN(parsed) || parsed <= 0) {
      this.syncPageJumpDraft();
      return;
    }
    const maxPage = this.totalPages > 0 ? this.totalPages : parsed;
    this.onPageJump(Math.max(1, Math.min(parsed, maxPage)));
  }

  private submitSeekDate(): void {
    const year = Number.parseInt(this.seekYearDraft);
    const month = Number.parseInt(this.seekMonthDraft);
    const day = Number.parseInt(this.seekDayDraft);
    if (Number.isNaN(year) || Number.isNaN(month) || Number.isNaN(day) ||
      year < 2000 || month < 1 || month > 12 || day < 1 || day > 31) {
      this.syncSeekDateDraft();
      return;
    }
    this.onSeekJump('seek=' + year.toString() + '-' + month.toString() + '-' + day.toString());
  }

  private useSeekJumpPanel(): boolean {
    return this.totalPages < 0;
  }

  private jumpSeekPresets(): string[] {
    return ['1d', '3d', '1w', '2w', '1m', '6m', '1y', '2y'];
  }

  private toggleAdvancedPanel(): void {
    if (this.isSearchResultScene) {
      this.onAdvancedPanelOpen();
    }
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
      this.advancedPanelVisible = !this.advancedPanelVisible;
    });
  }

  private closeAdvancedPanel(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
      this.advancedPanelVisible = false;
    });
  }

  private openJumpPanel(): void {
    if (!this.canJump) {
      return;
    }
    this.syncPageJumpDraft();
    if (this.useSeekJumpPanel() &&
      (this.seekYearDraft.length === 0 || this.seekMonthDraft.length === 0 || this.seekDayDraft.length === 0)) {
      this.syncSeekDateDraft();
    }
    this.jumpPanelVisible = true;
  }

  private closeJumpPanel(): void {
    this.jumpPanelVisible = false;
  }

  private openImageSearchPanel(): void {
    this.advancedPanelVisible = false;
    this.jumpPanelVisible = false;
    this.imageSearchPanelVisible = true;
  }

  private closeImageSearchPanel(): void {
    this.imageSearchPanelVisible = false;
  }

  private totalBarHeight(): number {
    return this.statusBarVp() + this.barHeight;
  }

  private imageSearchPanelWidth(): number {
    if (this.contentWidth <= 0) {
      return 320;
    }
    return Math.min(320, Math.max(260, this.contentWidth - 24));
  }

  private imageSearchPanelMaxHeight(): number {
    if (this.viewportHeight <= 0) {
      return 420;
    }
    return Math.max(280, this.viewportHeight - 48);
  }

  private advancedPanelMaxHeight(): number {
    if (this.viewportHeight <= 0) {
      return 520;
    }
    return Math.max(360, this.viewportHeight - this.statusBarVp() - this.barHeight - 28);
  }

  private visibleBarHeight(): number {
    return immersiveChromeHeightFromOffset(this.toolbarOffsetY, this.totalBarHeight());
  }

  private toolbarVisible(): boolean {
    return this.visibleBarHeight() > 0;
  }

  private handleScrollFrame(scrollOffset: number): number {
    const yOffset = normalizeGalleryListScrollOffset(this.listScroller.currentOffset().yOffset);
    if (yOffset <= 4) {
      this.toolbarRestoring = false;
      this.toolbarOffsetY = 0;
      return scrollOffset;
    }
    if (scrollOffset > 0 && this.visibleBarHeight() > 0) {
      const previousOffsetY = this.toolbarOffsetY;
      this.toolbarRestoring = false;
      this.toolbarOffsetY = nextFloatingToolbarOffset(this.toolbarOffsetY, scrollOffset, yOffset, this.totalBarHeight());
      const consumedOffset = Math.max(0, previousOffsetY - this.toolbarOffsetY);
      return Math.max(0, scrollOffset - consumedOffset);
    }
    if (scrollOffset < 0 && this.toolbarOffsetY < 0) {
      this.restoreToolbarOnReverseScroll();
    }
    return scrollOffset;
  }

  private restoreToolbarOnReverseScroll(): void {
    if (this.toolbarRestoring) {
      return;
    }
    this.toolbarRestoring = true;
    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      this.toolbarOffsetY = 0;
    });
    setTimeout(() => {
      this.toolbarRestoring = false;
    }, 320);
  }

  private triggerLoadMoreIfNear(last: number): void {
    if (this.isLoadingMore || this.loadMorePending) {
      return;
    }
    if (this.galleries.length > 0 && last >= this.galleries.length - 24) {
      this.loadMorePending = true;
      this.onLoadMore();
      // Reset local guard after one frame so rapid scroll events don't queue duplicates
      setTimeout(() => {
        this.loadMorePending = false;
      }, 500);
    }
  }

  private estimateContentHeight(): number {
    const columns = Math.max(1, this.galleryColumnCount());
    const rows = Math.ceil(this.galleries.length / columns);
    const cardHeight = galleryListMode() === 'Thumb' ? Math.max(0, this.galleryCardWidth() / 0.75 + 54) :
      galleryThumbHeight();
    return this.searchResultStripHeight() + rows * cardHeight +
      Math.max(0, rows - 1) * this.galleryCardGap() +
      this.galleryContentPadding();
  }

  private triggerLoadMoreByOffset(offset: number): void {
    const viewportHeight = this.listViewportHeight();
    if (viewportHeight <= 0) {
      return;
    }
    const remaining = this.estimateContentHeight() - offset - viewportHeight;
    if (remaining <= Math.max(viewportHeight * 2.5, 1500)) {
      this.triggerLoadMoreIfNear(this.galleries.length);
    }
  }

  private contentStartOffset(): number {
    return this.visibleBarHeight();
  }

  private listViewportHeight(): number {
    if (this.viewportHeight <= 0) {
      return 1;
    }
    return Math.max(1, this.viewportHeight - this.contentStartOffset());
  }

  private searchResultStripHeight(): number {
    return 0;
  }

  private galleryCardPreferredWidth(): number {
    if (galleryListMode() === 'Extended') {
      return 340;
    }
    if (galleryListMode() === 'Detail') {
      return 340;
    }
    const value = galleryThumbWidth();
    if (value <= 70) {
      return 116;
    }
    if (value >= 104) {
      return 164;
    }
    return 136;
  }

  private galleryCardGap(): number {
    return 8;
  }

  private galleryContentPadding(): number {
    return 8;
  }

  private snapListToTop(): void {
    this.listScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    this.toolbarOffsetY = 0;
    this.onScrollUpdate(0);
  }

  private rememberListOffset(yOffset: number): void {
    if (this.refreshing) {
      return;
    }
    this.onScrollUpdate(yOffset);
  }

  private galleryCardWidth(): number {
    const availableWidth = Math.max(0, this.contentWidth - this.galleryContentPadding() * 2);
    if (availableWidth <= 0 || Number.isNaN(availableWidth)) {
      return this.galleryCardPreferredWidth();
    }
    const columns = this.galleryColumnCount();
    const gap = this.galleryCardGap();
    return Math.max(this.galleryCardMinWidth(), Math.floor((availableWidth - gap * (columns - 1)) / columns));
  }

  private galleryColumnCount(): number {
    return this.galleryColumnCountForWidth(this.contentWidth);
  }

  private galleryColumnCountForWidth(width: number): number {
    const availableWidth = Math.max(0, width - this.galleryContentPadding() * 2);
    if (availableWidth <= 0 || Number.isNaN(availableWidth)) {
      return 1;
    }
    const preferred = this.galleryCardPreferredWidth();
    const gap = this.galleryCardGap();
    return Math.max(1, Math.floor((availableWidth + gap) / (preferred + gap)));
  }

  private galleryCardMinWidth(): number {
    if (galleryListMode() === 'Extended') {
      return 300;
    }
    if (galleryListMode() === 'Detail') {
      return 300;
    }
    return 104;
  }

  private updateContentWidth(width: number): void {
    const normalizedWidth = Math.floor(width);
    if (normalizedWidth <= 0 || Number.isNaN(normalizedWidth) ||
      Math.abs(this.contentWidth - normalizedWidth) < 1) {
      return;
    }
    this.contentWidth = normalizedWidth;
    rememberMainContentWidthVp(normalizedWidth);
  }

  private selectedSearchTagTokens(): string[] {
    return searchTagTokens(this.keyword);
  }

  private searchInputText(): string {
    return searchKeywordWithoutTagTokens(this.keyword);
  }

  private updateSearchInputText(value: string): void {
    this.onKeywordChange(composeSearchKeywordWithInput(this.keyword, value));
  }

  private removeSearchTag(token: string): void {
    this.onKeywordChange(removeSearchTagToken(this.keyword, token));
  }

  private searchTagStripMaxWidth(): number {
    if (this.contentWidth <= 0) {
      return 160;
    }
    return Math.max(80, this.contentWidth - 240);
  }

  private removeLastSearchTagFromEmptyInput(): boolean {
    if (this.searchInputText().length > 0) {
      return false;
    }
    const tokens = this.selectedSearchTagTokens();
    if (tokens.length === 0) {
      return false;
    }
    this.removeSearchTag(tokens[tokens.length - 1]);
    return true;
  }

  @Builder
  private searchTagChip(token: string) {
    Row({ space: 4 }) {
      Text(searchTagTokenLabel(token))
        .fontSize(12)
        .fontColor(themeOnPrimaryText())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 132 })

      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(13)
        .fontColor([themeOnPrimaryText()])
        .width(18)
        .height(18)
        .onClick(() => {
          this.removeSearchTag(token);
        })
    }
    .height(28)
    .padding({ left: 9, right: 6 })
    .backgroundColor(themePrimaryColor())
    .borderRadius(14)
    .flexShrink(0)
  }

  @Builder
  private searchKeywordEditor() {
    Row({ space: this.selectedSearchTagTokens().length > 0 ? 4 : 0 }) {
      if (this.selectedSearchTagTokens().length > 0) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.selectedSearchTagTokens(), (token: string) => {
              this.searchTagChip(token)
            }, (token: string) => token)
          }
        }
        .height(30)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .constraintSize({ maxWidth: this.searchTagStripMaxWidth() })
        .flexShrink(1)
      }

      TextInput({ text: this.searchInputText(), placeholder: uiText(this.searchPlaceholder) })
        .height(34)
        .layoutWeight(1)
        .constraintSize({ minWidth: 96 })
        .backgroundColor(themeTransparentColor())
        .placeholderColor(themeSecondaryText())
        .fontColor(themePrimaryText())
        .caretColor(themePrimaryColor())
        .padding({ left: this.selectedSearchTagTokens().length > 0 ? 4 : 8, right: 8 })
        .onFocus(() => {
          this.refreshSearchSuggestions();
          this.onSearchFocus();
        })
        .onChange((value: string) => {
          this.updateSearchInputText(value);
        })
        .onWillDelete((value: DeleteValue): boolean => {
          if (value.direction === TextDeleteDirection.BACKWARD && this.removeLastSearchTagFromEmptyInput()) {
            return false;
          }
          return true;
        })
        .onKeyEvent((event: KeyEvent): boolean => {
          if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_DEL) {
            return this.removeLastSearchTagFromEmptyInput();
          }
          return false;
        })
        .onSubmit(() => {
          this.closeAdvancedPanel();
          this.onSearch();
        })
    }
    .height(38)
    .layoutWeight(1)
    .padding({ left: 8, right: 8 })
    .backgroundColor(themeFieldBackground())
    .borderRadius(19)
    .alignItems(VerticalAlign.Center)
  }

  private syncContentWidthFromWindow(): void {
    if (this.contentWidth >= 240) {
      return;
    }
    this.updateContentWidth(mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value)));
  }

  @Builder
  private searchResultNavBar() {
    Column() {
      Column()
        .height(this.statusBarVp())
        .width('100%')
        .backgroundColor(themePrimaryColor())

      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([themeOnPrimaryText()])
        }
        .width(40)
        .height(40)
        .backgroundColor(themeOnPrimaryActionBackground())
        .flexShrink(0)
        .onClick(() => {
          this.onBack();
        })

        this.searchKeywordEditor()

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(22)
            .fontColor([themeOnPrimaryText()])
        }
        .width(40)
        .height(40)
        .backgroundColor(
          this.advancedPanelVisible || this.advancedSearchEnabled ? themeOnPrimaryActionStrongBackground() :
            themeOnPrimaryActionBackground())
        .flexShrink(0)
        .onClick(() => {
          this.toggleAdvancedPanel();
        })
      }
      .width('100%')
      .height(this.barHeight)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(themePrimaryColor())
    }
    .width('100%')
    .translate({ y: this.toolbarOffsetY })
    .opacity(1)
    .visibility(this.toolbarVisible() ? Visibility.Visible : Visibility.Hidden)
    .animation({ duration: 200, curve: Curve.EaseOut })
    .zIndex(10)
  }

  private shouldShowSearchSuggestions(): boolean {
    return (this.isSearchResultScene || this.useLocalSearchBar) && !this.searchSubmitted;
  }

  private refreshSearchSuggestions(namespaces: string[] = this.selectedTagNamespaces): void {
    this.searchSuggestionItems = buildSearchSuggestions(this.keyword, 0, namespaces);
    this.searchSuggestionRevision++;
  }

  private selectedTagNamespaceKey(): string {
    return this.selectedTagNamespaces.slice().sort().join('|');
  }

  private applySearchSuggestion(suggestion: SearchSuggestionItem): void {
    if (suggestion.kind === 'tag') {
      this.onKeywordChange(addSearchTagToken(this.keyword, suggestion.query));
      this.onSearchModeChange(ListMode.Normal);
      return;
    }
    this.onKeywordChange(suggestion.query);
  }

  private toggleTagNamespace(namespace: string): void {
    const next = this.selectedTagNamespaces.slice();
    const index = next.indexOf(namespace);
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(namespace);
    }
    this.selectedTagNamespaces = next;
    this.refreshSearchSuggestions(next);
  }

  @Builder
  private searchSuggestionPlaceholder() {
    Column({ space: 4 }) {
      SearchSummaryStrip({
        selectedTagNamespaces: this.selectedTagNamespaces,
        selectedTagNamespaceKey: this.selectedTagNamespaceKey(),
        revision: this.searchSuggestionRevision,
        onToggleTagNamespace: (namespace: string) => {
          this.toggleTagNamespace(namespace);
        }
      })
      if (this.searchSuggestionItems.length > 0) {
        SearchSuggestionList({
          suggestions: this.searchSuggestionItems,
          revision: this.searchSuggestionRevision,
          onSelect: (suggestion: SearchSuggestionItem) => {
            this.applySearchSuggestion(suggestion);
          }
        })
          .height(Math.max(240, this.viewportHeight - this.totalBarHeight() - 58))
      } else {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(28)
            .fontColor([themePlaceholderColor()])
          Text(uiText('Search history appears before typing; tag tips appear while typing'))
            .fontSize(12)
            .fontColor(themeTertiaryText())
        }
        .width('100%')
        .height(180)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(themeSurface())
        .borderRadius(6)
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 4 })
  }

  private openBookmarkDrawer(): void {
    if (!this.showBookmarkButton || this.bookmarkDrawerVisible) {
      return;
    }
    this.onBookmarkDrawerOpen();
    this.bookmarkDrawerVisible = true;
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
      this.bookmarkDrawerOffsetX = 0;
      this.bookmarkDrawerOverlayOpacity = 0.45;
    });
  }

  private closeBookmarkDrawer(): void {
    if (!this.bookmarkDrawerVisible) {
      return;
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
      this.bookmarkDrawerOffsetX = this.FAVORITE_DRAWER_WIDTH;
      this.bookmarkDrawerOverlayOpacity = 0;
    });
    setTimeout(() => {
      if (this.bookmarkDrawerOffsetX > this.FAVORITE_DRAWER_WIDTH - 40) {
        this.bookmarkDrawerVisible = false;
      }
    }, 220);
  }

  @Builder
  private galleryRow(row: GalleryRowData) {
    ListItem() {
      Row() {
        ForEach(row.items, (gallery: GalleryInfo, colIndex: number) => {
          if (galleryListMode() === 'Thumb') {
            GalleryThumbCard({
              gallery: gallery,
              onLongPress: (pressed: GalleryInfo) => {
                this.onLongPressGallery(pressed);
              }
            })
              .width(this.galleryCardWidth())
              .margin({
                right: colIndex < row.items.length - 1 ? this.galleryCardGap() : 0
              })
              .animation({ duration: 220, curve: Curve.EaseOut })
              .onClick(() => {
                this.onSelectGallery(gallery);
              })
          } else {
            GalleryListRow({
              gallery: gallery,
              onLongPress: (pressed: GalleryInfo) => {
                this.onLongPressGallery(pressed);
              }
            })
              .width(this.galleryCardWidth())
              .margin({
                right: colIndex < row.items.length - 1 ? this.galleryCardGap() : 0
              })
              .animation({ duration: 220, curve: Curve.EaseOut })
              .onClick(() => {
                this.onSelectGallery(gallery);
              })
          }
        }, (gallery: GalleryInfo, _colIndex: number) => this.galleryCardKey(gallery))
      }
      .width('100%')
      .padding({ left: this.galleryContentPadding(), right: this.galleryContentPadding() })
      .justifyContent(FlexAlign.Start)
      .animation({ duration: 220, curve: Curve.EaseOut })
    }
    .margin({ bottom: this.galleryCardGap() })
    .reuseId('gallery-row-' + this.galleryColumnCount().toString())
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Refresh({ refreshing: this.refreshing }) {
          List({ space: 0, scroller: this.listScroller }) {
            if (this.shouldShowSearchSuggestions()) {
              ListItem() {
                this.searchSuggestionPlaceholder()
              }
            } else if (this.galleries.length === 0) {
              ListItem() {
                GalleryListStateView({
                  statusText: this.statusText,
                  requestUrl: this.requestUrl,
                  onRefresh: this.onRefresh
                })
                  .width('100%')
                  .height('100%')
              }
              .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
            } else {
              ListItem()
                .margin({ bottom: this.galleryCardGap() })
              // Group gallery cards into rows with galleryColumnCount() items per row.
              ForEach(this.buildRows(), (row: GalleryRowData) => {
                this.galleryRow(row)
              }, (row: GalleryRowData) => row.key)

              // Load-more indicator.
              if (this.isLoadingMore) {
                ListItem() {
                  Row() {
                    LoadingProgress().width(20).height(20).color(themePlaceholderColor())
                    Text(uiText('Loading...')).fontSize(12).fontColor(themePlaceholderColor()).margin({ left: 6 })
                  }
                  .width('100%')
                  .height(40)
                  .justifyContent(FlexAlign.Center)
                }
              }
            }
          }
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true, effectEdge: EffectEdge.START | EffectEdge.END })
          .cachedCount(10)
          .width('100%')
          .height(this.listViewportHeight())
          .onAppear(() => {
            this.syncContentWidthFromWindow();
            if (!this.restoredScroll && this.initialScrollOffset > 0) {
              this.restoredScroll = true;
              setTimeout(() => {
                this.listScroller.scrollTo({ xOffset: 0, yOffset: this.initialScrollOffset });
                this.contentOpacity = 1;
              }, 80);
            }
          })
          .onScrollFrameBegin((offset: number, _state: ScrollState) => {
            return { offsetRemain: this.handleScrollFrame(offset) };
          })
          .onDidScroll((_scrollOffset: number, _scrollState: ScrollState) => {
            const yOff = normalizeGalleryListScrollOffset(this.listScroller.currentOffset().yOffset);
            this.rememberListOffset(yOff);
            if (!this.shouldShowSearchSuggestions()) {
              this.triggerLoadMoreByOffset(yOff);
            }
          })
          .onScrollStop(() => {
            const yOff = normalizeGalleryListScrollOffset(this.listScroller.currentOffset().yOffset);
            this.rememberListOffset(yOff);
          })
          .onReachEnd(() => {
            if (!this.shouldShowSearchSuggestions()) {
              this.triggerLoadMoreIfNear(this.galleries.length);
            }
          })
        }
        .refreshOffset(this.REFRESH_OFFSET)
        .pullToRefresh(true)
        .onRefreshing(() => {
          this.onRefreshPull(() => {
            this.refreshing = false;
          });
        })
        .width('100%')
        .height(this.listViewportHeight())
        .translate({ y: this.contentStartOffset() })
        .backgroundColor(themePageBackground())
      }
      .width('100%')
      .height('100%')
      .opacity(this.contentOpacity)
      .animation({ duration: 100, curve: Curve.EaseOut })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.updateContentWidth(newArea.width as number);
        const h = newArea.height as number;
        if (h > 0 && !Number.isNaN(h)) {
          this.viewportHeight = h;
        }
      })

      if (this.favoriteDrawerVisible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(themeScrimColor())
          .opacity(this.favoriteDrawerOverlayOpacity)
          .onClick(() => {
            this.closeFavoriteDrawer();
          })
          .gesture(
            PanGesture({ fingers: 1, direction: PanDirection.Right, distance: 28 })
              .onActionEnd(() => {
                this.closeFavoriteDrawer();
              })
          )
          .zIndex(15)

        FavoriteCategoryDrawer({
          statusBarHeight: this.statusBarVp(),
          selectedFavCat: this.favoriteCat,
          categories: this.favoriteCategories,
          localFavoriteCount: this.favoriteLocalCount,
          onSelect: (favCat: number) => {
            this.closeFavoriteDrawer();
            this.onFavoriteCatChange(favCat);
          },
          onClose: () => {
            this.closeFavoriteDrawer();
          }
          })
          .position({ x: this.favoriteDrawerLeft(), y: 0 })
          .translate({ x: this.favoriteDrawerOffsetX })
          .zIndex(16)
          .shadow({ radius: 32, color: themeShadowColor(), offsetX: -8, offsetY: 0 })
          .gesture(
            PanGesture({ fingers: 1, direction: PanDirection.Right, distance: 28 })
              .onActionEnd(() => {
                this.closeFavoriteDrawer();
              })
          )
      }

      if (this.bookmarkDrawerVisible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(themeScrimColor())
          .opacity(this.bookmarkDrawerOverlayOpacity)
          .onClick(() => {
            this.closeBookmarkDrawer();
          })
          .gesture(
            PanGesture({ fingers: 1, direction: PanDirection.Right, distance: 28 })
              .onActionEnd(() => {
                this.closeBookmarkDrawer();
              })
          )
          .zIndex(17)

        SearchBookmarkDrawer({
          statusBarHeight: this.statusBarVp(),
          bookmarks: this.bookmarks,
          onSelect: (bookmark: SearchBookmarkInfo) => {
            this.closeBookmarkDrawer();
            this.onSelectBookmark(bookmark);
          },
          onAdd: () => {
            this.closeBookmarkDrawer();
            this.onAddBookmark();
          },
          onSettings: () => {
            this.closeBookmarkDrawer();
            this.onBookmarkSettings();
          },
          onDelete: (bookmark: SearchBookmarkInfo) => {
            this.onDeleteBookmark(bookmark);
          },
          onClose: () => {
            this.closeBookmarkDrawer();
          }
        })
          .position({ x: this.bookmarkDrawerLeft(), y: 0 })
          .translate({ x: this.bookmarkDrawerOffsetX })
          .zIndex(18)
          .shadow({ radius: 32, color: themeShadowColor(), offsetX: -8, offsetY: 0 })
          .gesture(
            PanGesture({ fingers: 1, direction: PanDirection.Right, distance: 28 })
              .onActionEnd(() => {
                this.closeBookmarkDrawer();
              })
          )
      }

      // FAB 悬浮按钮
      Column() {
        QuickActionColumn({
          expanded: this.actionsExpanded,
          filterActive: this.filterActive,
          accountFilterEnabled: this.isSearchResultScene ? this.searchFilterEnabled : this.accountFilterEnabled,
          canJump: this.canJump,
          canRandom: this.canRandom,
          canImageSearch: !this.useLocalSearchBar,
          canBookmark: this.showBookmarkButton,
          onToggle: this.onToggleActions,
          onFilter: this.onFilter,
          onJump: () => {
            this.openJumpPanel();
          },
          onRefresh: this.onRefresh,
          onRandom: this.onRandom,
          onImageSearch: () => {
            this.openImageSearchPanel();
          },
          onBookmark: () => {
            this.onAddBookmark();
          }
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.End)
      .padding({ right: 16, bottom: 24 })
      .hitTestBehavior(HitTestMode.Transparent)

      if (this.advancedPanelVisible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(themeScrimColor())
          .onClick(() => {
            this.closeAdvancedPanel();
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseInOut }))
          .zIndex(11)

        Stack({ alignContent: Alignment.Top }) {
          SearchAdvancedPanel({
            searchModeValue: this.searchModeValue,
            searchCategory: this.searchCategory,
            advancedSearchEnabled: this.advancedSearchEnabled,
            advanceSearch: this.advanceSearch,
            searchFilterEnabled: this.searchFilterEnabled,
            minRating: this.minRating,
            pageFrom: -1,
            pageTo: -1,
            panelMaxHeight: this.advancedPanelMaxHeight(),
            onSearchModeChange: this.onSearchModeChange,
            onSearchCategoryChange: this.onSearchCategoryChange,
            onAdvancedEnabledChange: this.onAdvancedEnabledChange,
            onAdvanceSearchChange: this.onAdvanceSearchChange,
            onMinRatingChange: this.onMinRatingChange,
            onClose: () => {
              this.closeAdvancedPanel();
            },
            onSearch: () => {
              this.closeAdvancedPanel();
              this.onSearch();
            }
          })
            .constraintSize({ maxHeight: this.advancedPanelMaxHeight() })
            .transition(TransitionEffect.move(TransitionEdge.TOP)
              .animation({ duration: 180, curve: Curve.EaseOut }))
        }
          .width('100%')
          .height('100%')
          .padding({ top: this.statusBarVp() + this.barHeight + 8, left: 10, right: 10 })
          .hitTestBehavior(HitTestMode.Transparent)
          .zIndex(12)
      }

      if (this.imageSearchPanelVisible) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(themeScrimColor())
            .onClick(() => {
              this.closeImageSearchPanel();
            })

          ImageSearchPanel({
            panelWidth: this.imageSearchPanelWidth(),
            panelMaxHeight: this.imageSearchPanelMaxHeight(),
            onClose: () => {
              this.closeImageSearchPanel();
            },
            onSearch: (path: string, useSimilarityScan: boolean, onlySearchCovers: boolean) => {
              this.closeImageSearchPanel();
              this.onImageSearch(path, useSimilarityScan, onlySearchCovers);
            }
          })
        }
          .width('100%')
          .height('100%')
          .zIndex(13)
      }

      if (this.jumpPanelVisible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(themeScrimColor())
          .onClick(() => {
            this.closeJumpPanel();
          })
          .zIndex(13)

        Column({ space: 10 }) {
          if (this.useSeekJumpPanel()) {
            Text('Jump/Seek')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(themePrimaryText())
              .width('100%')
            if (this.resultCount.length > 0) {
              Text(this.resultCount)
                .fontSize(12)
                .fontColor(themeSecondaryText())
                .width('100%')
            }
            Grid() {
              ForEach(this.jumpSeekPresets(), (preset: string) => {
                GridItem() {
                  Button(preset)
                    .height(34)
                    .width('100%')
                    .fontSize(12)
                    .fontColor(themePrimaryColor())
                    .backgroundColor(themeFieldBackground())
                    .borderRadius(4)
                    .onClick(() => {
                      this.onSeekJump('jump=' + preset);
                      this.closeJumpPanel();
                    })
                }
              }, (preset: string) => preset)
            }
            .columnsTemplate('1fr 1fr 1fr 1fr')
            .rowsGap(6)
            .columnsGap(6)
            .height(74)

            Row({ space: 6 }) {
              TextInput({ text: this.seekYearDraft, placeholder: '2026' })
                .height(36)
                .layoutWeight(1.4)
                .type(InputType.Number)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .borderRadius(4)
                .padding({ left: 8, right: 8 })
                .onChange((value: string) => {
                  this.seekYearDraft = value;
                })
              TextInput({ text: this.seekMonthDraft, placeholder: '6' })
                .height(36)
                .layoutWeight(1)
                .type(InputType.Number)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .borderRadius(4)
                .padding({ left: 8, right: 8 })
                .onChange((value: string) => {
                  this.seekMonthDraft = value;
                })
              TextInput({ text: this.seekDayDraft, placeholder: '26' })
                .height(36)
                .layoutWeight(1)
                .type(InputType.Number)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .borderRadius(4)
                .padding({ left: 8, right: 8 })
                .onChange((value: string) => {
                  this.seekDayDraft = value;
                })
            }

            Button(uiText('Seek date'))
              .height(36)
              .width('100%')
              .fontSize(13)
              .fontColor(themeOnPrimaryText())
              .backgroundColor(themePrimaryColor())
              .borderRadius(4)
              .onClick(() => {
                this.submitSeekDate();
                this.closeJumpPanel();
              })
          } else {
            Text(uiText('Jump'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(themePrimaryText())
              .width('100%')
            Row({ space: 8 }) {
              TextInput({ text: this.pageJumpDraft, placeholder: (this.pageIndex + 1).toString() })
                .height(38)
                .layoutWeight(1)
                .type(InputType.Number)
                .fontColor(themePrimaryText())
                .backgroundColor(themeFieldBackground())
                .borderRadius(4)
                .padding({ left: 10, right: 10 })
                .onChange((value: string) => {
                  this.pageJumpDraft = value;
                })
                .onSubmit(() => {
                  this.submitPageJump();
                  this.closeJumpPanel();
                })
              Text('/ ' + (this.totalPages > 0 ? this.totalPages.toString() : '-'))
                .fontSize(13)
                .fontColor(themeSecondaryText())
            }

            Button(uiText('Jump'))
              .height(36)
              .width('100%')
              .fontSize(13)
              .fontColor(themeOnPrimaryText())
              .backgroundColor(themePrimaryColor())
              .borderRadius(4)
              .onClick(() => {
                this.submitPageJump();
                this.closeJumpPanel();
              })
          }
        }
        .width(this.useSeekJumpPanel() ? 280 : 220)
        .padding(12)
        .backgroundColor(themeSurface())
        .borderRadius(8)
        .shadow({
          radius: 12,
          color: themeShadowColor(),
          offsetX: 0,
          offsetY: 4
        })
        .position({
          x: this.contentWidth > 0 ? Math.max(12, this.contentWidth - (this.useSeekJumpPanel() ? 304 : 244)) : 100,
          y: this.viewportHeight > 0 ? Math.max(96, this.viewportHeight - (this.useSeekJumpPanel() ? 310 : 210)) : 360
        })
        .zIndex(14)
      }

      // 浮动导航栏
      Column() {
        if (this.isSearchResultScene || this.useLocalSearchBar) {
          this.searchResultNavBar()
        } else {
          EhNavBar({
            statusBarHeight: this.statusBarVp(),
            title: this.searchTitle.length > 0 ? this.searchTitle : this.sceneTitle,
            searchMode: false,
            keyword: this.keyword,
            filterActive: this.filterActive,
            showSearchButton: this.showSearchButton,
            showFavoriteButton: this.showFavoriteButton,
            showBookmarkButton: this.showBookmarkButton,
            showRefreshButton: false,
            showBackButton: this.showBackButton,
            translateY: this.toolbarOffsetY,
            onMenu: () => {
              this.onMenu();
            },
            onBack: () => {
              this.onBack();
            },
            onSearch: () => {
              this.onSearch();
            },
            onFavoriteButton: () => {
              this.openFavoriteDrawer();
            },
            onBookmarkButton: () => {
              this.openBookmarkDrawer();
            },
            onKeywordChange: (v: string) => {
              this.onKeywordChange(v);
            },
            onRefresh: () => {
              this.onRefresh();
            }
          })
        }
      }
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Left, distance: 28 })
        .onActionEnd((event: GestureEvent | undefined) => {
          this.handleOpenFavoriteDrawerPan(event);
          this.handleOpenBookmarkDrawerPan(event);
        })
    )
  }

  // 把 galleries 按列数分组成行数组
  private buildRows(): GalleryRowData[] {
    const cols = this.galleryColumnCount();
    const rows: GalleryRowData[] = [];
    for (let i = 0; i < this.galleries.length; i += cols) {
      const items = this.galleries.slice(i, i + cols);
      const rowIndex = Math.floor(i / cols);
      rows.push({
        index: rowIndex,
        key: cols.toString() + ':' + rowIndex.toString() + ':' + this.galleryRowKey(items),
        items: items
      });
    }
    return rows;
  }

  private galleryRowKey(row: GalleryInfo[]): string {
    return row.map((gallery: GalleryInfo) => this.galleryCardKey(gallery)).join('-');
  }

  private galleryCardKey(gallery: GalleryInfo): string {
    return gallery.gid.toString() + ':' + gallery.token + ':' + gallery.title;
  }
}

@Component
export struct GalleryListStateView {
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  onRefresh: () => void = () => {
  };

  private isLoading(): boolean {
    const lower = this.statusText.toLowerCase();
    return lower.indexOf('loading') >= 0;
  }

  private isError(): boolean {
    const lower = this.statusText.toLowerCase();
    return lower.indexOf('failed') >= 0 || lower.indexOf('error') >= 0 ||
      lower.indexOf('blocked') >= 0 || lower.indexOf('banned') >= 0 ||
      lower.indexOf('required') >= 0;
  }

  private titleText(): string {
    if (this.isLoading()) {
      return 'Loading...';
    }
    if (this.isError()) {
      return 'Load failed';
    }
    return 'No galleries';
  }

  build() {
    Column() {
      if (this.isLoading()) {
        LoadingProgress()
          .width(48)
          .height(48)
          .color(themePrimaryColor())
      } else {
        SymbolGlyph(this.isError() ? $r('sys.symbol.exclamationmark_triangle') : $r('sys.symbol.magnifyingglass'))
          .fontSize(48)
          .fontColor([this.isError() ? themeDangerText() : themeTertiaryText()])
      }

      Text(uiText(this.titleText()))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(themePrimaryText())
        .margin({ top: 14 })

      if (this.statusText.length > 0) {
        Text(uiStatusText(this.statusText))
          .fontSize(13)
          .fontColor(themeSecondaryText())
          .lineHeight(20)
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })
          .width('82%')
      }

      if (this.requestUrl.length > 0 && this.isError()) {
        Text(this.requestUrl)
          .fontSize(11)
          .fontColor(themeTertiaryText())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })
          .width('82%')
      }

      if (!this.isLoading()) {
        Button(uiText('Refresh'))
          .height(38)
          .fontSize(13)
          .fontColor(themeOnPrimaryText())
          .backgroundColor(themePrimaryColor())
          .margin({ top: 16 })
          .onClick(() => {
            this.onRefresh();
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 24, right: 24, bottom: 48 })
    .backgroundColor(themePageBackground())
  }
}

function localGalleryFilterRoute(route: GalleryRoute): boolean {
  return route === GalleryRoute.Home || route === GalleryRoute.Subscription || route === GalleryRoute.WhatsHot;
}
