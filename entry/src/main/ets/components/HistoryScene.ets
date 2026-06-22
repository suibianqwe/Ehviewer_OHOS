import { GalleryCategory, GalleryInfo, GalleryRoute } from '../model/GalleryModels';
import { GalleryListLoadResult } from '../services/EhHttpClient';
import { DEFAULT_ADVANCE_SEARCH, ListMode } from '../services/EhUrl';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { cloneGalleryInfos, getAbilityContext } from '../shared/EhShared';
import { GalleryListScene } from './GalleryScenes';

const HISTORY_PAGE_SIZE: number = 25;

@Component
export struct HistoryScene {
  onMenu: () => void = () => {
  };

  private async loadHistoryPage(keyword: string, pageIndex: number,
    pageSize: number): Promise<GalleryListLoadResult> {
    const context = getAbilityContext();
    if (context !== undefined) {
      await ehHistoryStore.load(context);
    }

    const allItems = cloneGalleryInfos(ehHistoryStore.getItems());
    const filtered = this.filterHistoryItems(allItems, keyword);
    const safePageSize = Math.max(1, pageSize);
    const safePageIndex = Math.max(0, pageIndex);
    const start = safePageIndex * safePageSize;
    const end = Math.min(filtered.length, start + safePageSize);
    const pageItems: GalleryInfo[] = [];
    for (let i = start; i < end; i++) {
      pageItems.push(filtered[i]);
    }
    const pages = filtered.length === 0 ? 0 : Math.ceil(filtered.length / safePageSize);

    return {
      ok: true,
      url: this.historyRequestUrl(keyword, safePageIndex),
      statusCode: 200,
      message: pageItems.length.toString() + '/' + filtered.length.toString() + ' history items',
      pages: pages,
      nextPage: safePageIndex + 1 < pages ? safePageIndex + 1 : -1,
      nextUrl: '',
      resultCount: filtered.length.toString(),
      galleries: pageItems
    };
  }

  private historyRequestUrl(keyword: string, pageIndex: number): string {
    const query = keyword.trim();
    return query.length > 0 ? 'ehviewer://history?page=' + pageIndex.toString() + '&q=' + encodeURIComponent(query) :
      'ehviewer://history?page=' + pageIndex.toString();
  }

  private filterHistoryItems(items: GalleryInfo[], keyword: string): GalleryInfo[] {
    const query = keyword.trim().toLowerCase();
    if (query.length === 0) {
      return items;
    }

    const filtered: GalleryInfo[] = [];
    for (let i = 0; i < items.length; i++) {
      if (this.matchesHistoryKeyword(items[i], query)) {
        filtered.push(items[i]);
      }
    }
    return filtered;
  }

  private matchesHistoryKeyword(item: GalleryInfo, query: string): boolean {
    if (this.matchesText(item.title, query) || this.matchesText(item.titleJpn, query) ||
      this.matchesText(item.uploader, query) || this.matchesText(item.simpleLanguage, query)) {
      return true;
    }
    if (this.matchesStringArray(item.simpleTags, query) || this.matchesStringArray(item.tagList, query)) {
      return true;
    }
    return item.gid.toString() === query;
  }

  private matchesStringArray(values: string[] | undefined, query: string): boolean {
    if (values === undefined) {
      return false;
    }
    for (let i = 0; i < values.length; i++) {
      if (this.matchesText(values[i], query)) {
        return true;
      }
    }
    return false;
  }

  private matchesText(value: string | undefined, query: string): boolean {
    if (value === undefined) {
      return false;
    }
    return value.toLowerCase().indexOf(query) >= 0;
  }

  build() {
    GalleryListScene({
      sceneTitle: 'History',
      listMode: 'History',
      sourceRoute: GalleryRoute.History,
      initialKeyword: '',
      initialSearchMode: ListMode.Normal,
      initialSearchCategory: GalleryCategory.None,
      initialAdvancedSearchEnabled: false,
      initialAdvanceSearch: DEFAULT_ADVANCE_SEARCH,
      initialMinRating: -1,
      initialPageFrom: -1,
      initialPageTo: -1,
      initialSearchSubmitted: true,
      isSearchResultScene: false,
      useForcedMode: true,
      forcedMode: ListMode.Normal,
      useLocalProvider: true,
      localPageSize: HISTORY_PAGE_SIZE,
      localProvider: (keyword: string, pageIndex: number, pageSize: number): Promise<GalleryListLoadResult> => {
        return this.loadHistoryPage(keyword, pageIndex, pageSize);
      },
      onMenu: () => {
        this.onMenu();
      }
    })
      .width('100%')
      .height('100%')
  }
}
