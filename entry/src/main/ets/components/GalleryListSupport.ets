import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { GalleryCategory, GalleryDetail, GalleryInfo, GalleryRoute, GallerySite } from '../model/GalleryModels';
import { DEFAULT_ADVANCE_SEARCH, FavListUrlBuilder, ListMode } from '../services/EhUrl';
import {
  GalleryDetailLink,
} from '../services/GalleryDetailSupport';
import { FavoriteCategoryInfo } from '../services/GalleryListParser';
import {
  themePrimaryText,
} from '../shared/EhTheme';
import {
  uiMaterialBackground,
} from '../shared/EhUiStyle';
import {
  cloneGalleryDetail,
  cloneGalleryInfo,
  getAbilityContext,
} from '../shared/EhShared';

export function galleryChromeForeground(): string {
  return themePrimaryText();
}

export function galleryChromeBackground(solidColor: string): ResourceColor {
  return uiMaterialBackground(solidColor);
}

export interface ThumbnailImageSize {
  width: number;
  height: number;
}

export const GALLERY_THUMBNAIL_CACHE_COUNT: number = 16;
export const GALLERY_THUMBNAIL_PREFETCH_BEFORE: number = GALLERY_THUMBNAIL_CACHE_COUNT;
export const GALLERY_THUMBNAIL_PREFETCH_AFTER: number = GALLERY_THUMBNAIL_CACHE_COUNT + 8;

export function readThumbnailImageSize(path: string): ThumbnailImageSize {
  let source: image.ImageSource | undefined = undefined;
  try {
    source = image.createImageSource(path);
    const info = source.getImageInfoSync();
    return { width: info.size.width, height: info.size.height };
  } catch (error) {
    return { width: 0, height: 0 };
  } finally {
    if (source !== undefined) {
      source.release().catch(() => {
      });
    }
  }
}

export interface GalleryListSceneCache {
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

export interface SearchResultDraft {
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

export interface NestedSearchFrame {
  draft: SearchResultDraft;
  showDetail: boolean;
  detailLink: GalleryDetailLink;
  detail: GalleryDetail;
  detailStatus: string;
  detailRequestUrl: string;
  detailScrollOffset: number;
}

export interface GalleryListNavigationCache {
  activeSplitPane: string;
  showSearchResultScene: boolean;
  searchResultDraft: SearchResultDraft;
  nestedSearchFrames?: NestedSearchFrame[];
  searchResultDetailOpened: boolean;
  searchOriginShowDetail: boolean;
  searchOriginDetailLink: GalleryDetailLink;
  searchOriginDetail: GalleryDetail;
  searchOriginDetailStatus: string;
  searchOriginDetailRequestUrl: string;
  searchOriginDetailScrollOffset: number;
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

export const galleryListSceneCache: Map<string, GalleryListSceneCache> = new Map();
export const galleryListNavigationCache: Map<string, GalleryListNavigationCache> = new Map();
export const ACCOUNT_DEFAULT_FILTER_DISABLE_FLAGS: number = 0x100 | 0x200 | 0x400;
export const IMAGE_SEARCH_FILE_SUFFIXES: string[] = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];

export function createEmptySearchResultDraft(): SearchResultDraft {
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

export function cloneSearchResultDraft(draft: SearchResultDraft): SearchResultDraft {
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

export function cloneNestedSearchFrame(frame: NestedSearchFrame): NestedSearchFrame {
  return {
    draft: cloneSearchResultDraft(frame.draft),
    showDetail: frame.showDetail,
    detailLink: cloneGalleryDetailLink(frame.detailLink),
    detail: cloneGalleryDetail(frame.detail),
    detailStatus: frame.detailStatus,
    detailRequestUrl: frame.detailRequestUrl,
    detailScrollOffset: frame.detailScrollOffset
  };
}

export function cloneNestedSearchFrames(frames: NestedSearchFrame[] | undefined): NestedSearchFrame[] {
  const cloned: NestedSearchFrame[] = [];
  if (frames === undefined) {
    return cloned;
  }
  for (let i = 0; i < frames.length; i++) {
    cloned.push(cloneNestedSearchFrame(frames[i]));
  }
  return cloned;
}

export function cloneFavoriteCategories(categories: FavoriteCategoryInfo[]): FavoriteCategoryInfo[] {
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

export function mergeFavoriteGalleries(local: GalleryInfo[], remote: GalleryInfo[]): GalleryInfo[] {
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

export function galleryListHasGid(galleries: GalleryInfo[], gid: number): boolean {
  for (let i = 0; i < galleries.length; i++) {
    if (galleries[i].gid === gid) {
      return true;
    }
  }
  return false;
}

export function mergedFavoriteResultCount(remoteText: string, localCount: number): string {
  const localText = localCount.toString() + ' local favorites';
  return remoteText.length > 0 ? remoteText + ' + ' + localText : localText;
}

export function cloneGalleryDetailLink(link: GalleryDetailLink): GalleryDetailLink {
  return {
    gid: link.gid,
    token: link.token,
    url: link.url,
    referer: link.referer,
    site: link.site,
    seed: cloneGalleryInfo(link.seed)
  };
}

export async function copyImageSearchSourceToCache(sourceUri: string): Promise<string> {
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

export function imageSearchExtension(value: string): string {
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

export function updateGalleryListScrollCache(key: string, offset: number): void {
  const cache = galleryListSceneCache.get(key);
  if (cache === undefined) {
    return;
  }
  cache.listScrollOffset = normalizeGalleryListScrollOffset(offset);
}

export function normalizeGalleryListScrollOffset(offset: number): number {
  if (offset <= 1 || Number.isNaN(offset)) {
    return 0;
  }
  return offset;
}





export interface FavoriteCategoryOption {
  favCat: number;
  name: string;
  count: number;
}

export interface DefaultFavoriteSlotOption {
  slot: number | null;
  name: string;
}

export function favoriteCategoryOptions(categories: FavoriteCategoryInfo[], localFavoriteCount: number): FavoriteCategoryOption[] {
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

export function defaultFavoriteSlotOptions(categories: FavoriteCategoryInfo[]): DefaultFavoriteSlotOption[] {
  const options: DefaultFavoriteSlotOption[] = [
    { slot: null, name: 'Let me select' },
    { slot: -1, name: 'Local Favorites' }
  ];
  for (let i = 0; i < 10; i++) {
    const category = findFavoriteCategory(i, categories);
    options.push({
      slot: i,
      name: category === null ? 'Favorites ' + i.toString() : category.name
    });
  }
  return options;
}

export function findFavoriteCategory(favCat: number, categories: FavoriteCategoryInfo[]): FavoriteCategoryInfo | null {
  for (let i = 0; i < categories.length; i++) {
    if (categories[i].favCat === favCat) {
      return categories[i];
    }
  }
  return null;
}

export function favoriteCategoryName(favCat: number, categories: FavoriteCategoryInfo[]): string {
  if (favCat === FavListUrlBuilder.FAV_CAT_ALL) {
    return 'Favourite';
  }
  if (favCat === FavListUrlBuilder.FAV_CAT_LOCAL) {
    return 'Local Favorites';
  }
  const parsed = findFavoriteCategory(favCat, categories);
  return parsed === null ? 'Favorites ' + favCat.toString() : parsed.name;
}

export function favoriteCategoryCountText(count: number): string {
  return count >= 0 ? count.toString() : '';
}
export function localGalleryFilterRoute(route: GalleryRoute): boolean {
  return route === GalleryRoute.Home || route === GalleryRoute.Subscription || route === GalleryRoute.WhatsHot;
}
