import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { GalleryCategory, GalleryComment, GalleryDetail, GalleryInfo, GalleryPage, GalleryPreview, GalleryRoute, GallerySite, GalleryTagGroup, TopListBucket, TopListDetail, TopListInfo, TopListItem, TopListKind } from '../model/GalleryModels';
import { ehCookieStore } from '../services/EhCookieStore';
import { DownloadDirectoryScanResult, RestoredDownloadGallery, ehDownloadFileStore } from '../services/EhDownloadFileStore';
import { DownloadInfo, DownloadLabel, DownloadState, ehDownloadStore } from '../services/EhDownloadStore';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehSettingsStore, SettingEntry, defaultSettingEntries } from '../services/EhSettingsStore';
import { EhHttpClient, GalleryDetailLoadResult, GalleryListLoadResult, GalleryPageLoadResult, NetworkDiagnosticResult, RateGalleryResult, SignInResult, ToggleFavoriteResult, TopListLoadResult } from '../services/EhHttpClient';
import { EhUrl, FavListUrlBuilder, ListMode, ListUrlBuilder } from '../services/EhUrl';
import { galleryPageCache } from '../services/GalleryPageCache';
import { CacheClearResult, readerImageCache } from '../services/ReaderImageCache';
import { ehSpiderInfoStore } from '../services/EhSpiderInfoStore';
import { MigrationTask, migrationTasks } from '../services/MigrationStatus';
import { FilterRule, FILTER_MODE_TITLE, FILTER_MODE_UPLOADER, FILTER_MODE_TAG, FILTER_MODE_TAG_NAMESPACE, ehFilterStore } from '../services/EhFilterStore';
import { LANGUAGE_REVISION_KEY } from '../shared/EhShared';
import { EhBackupBundle, DrawerItem, SettingsHeaderItem, SettingsRowItem, SessionMode, SettingsPanel, DRAWER_ITEMS, SETTINGS_HEADERS, STATUS_BAR_HEIGHT_KEY, ON_OFF_OPTIONS, shouldUseChineseUi, uiText, uiValue, uiStatusText, uiPageText, zhText, setActiveBackHandler, runActiveBackHandler, createEmptyGallery, createEmptyDownloadInfo, createDetailFromGallery, createEmptyDetail, createEmptyPreview, createEmptyPage, createEmptyTopListDetail, createEmptyTopListInfo, createEmptyTopListBucket, createEmptyTopListItem, cloneStringArray, cloneRequiredStringArray, cloneGalleryInfo, cloneGalleryInfos, padTwo, applyGalleryFilters, cloneGalleryTagGroups, cloneGalleryComments, cloneGalleryPreviews, cloneGalleryDetail, cloneGalleryPage, createReaderLoadingPage, cloneTopListItem, cloneTopListBucket, cloneTopListInfo, cloneTopListDetail, getAbilityContext, saveGalleryToHistory, saveGalleryReadPosition, readerStartIndex, downloadButtonText, toggleGalleryDownload, saveDownloadsQuietly, filterDownloadItems, downloadItemMatches, sortDownloadItems, nextDownloadStatusFilter, nextDownloadLabelFilter, nextDownloadSortMode, nextStringOption, nextDownloadState, nextDownloadLabel, downloadLabelName, downloadStateLabel, downloadStateColor, downloadProgressText, downloadSizeText, downloadImageUrlForPage, downloadThreadLimit, downloadPageIndexes, downloadQueueSummary, parseHistoryMaxSize, routeTitle, routeSubtitle, launchRouteFromSetting, settingsPanelTitle, settingsRowsForPanel, optionSettingsRow, textSettingsRow, staticSettingsRow, settingEntryValue, cloneStringOptions, settingMigrationMessage, nextOption, isValidProxyPortText, formatNetworkDiagnostics, listModeForRoute, routeUsesKeyword, usesGallerySearchToolbar, usesEmbeddedToolbar, defaultKeywordForRoute, gallerySearchTitle, currentGallerySite, effectiveListSite, gallerySiteName, galleryListFailureMessage, shouldRetryGalleryListOnE, withGalleryListMessage, readerPageReferer, readerDisplayImageUrl, cacheReaderImageForPage, cacheThumbnailImage, cloneGalleryPageWithCache, readerLocalImageSource, readerZoomSize, readerFullImageWidth, readerFullImageHeight, readerImageFit, readerShortUrl, readerPreloadCount, readerIsRightToLeft, categoryName, categoryColor, ratingText, galleryDisplayTitle, showGalleryPages, galleryListMode, galleryThumbWidth, galleryThumbHeight, galleryRowHeight, galleryTagPreview, detailTitleFontSize, detailTitleMaxLines, detailHeadingFontSize, readerShowProgress, readerShowClock, readerClockText, padTimeNumber, topListChipColor } from '../shared/EhShared';
import { CommentsScene, GalleryDetailScene, GalleryListRow, GalleryListScene, PlaceholderScene, ReaderScene } from './GalleryScenes';
@Component
export struct HistoryScene {
  private client: EhHttpClient = new EhHttpClient();
  onMenu: () => void = () => {};

  @State histories: GalleryInfo[] = [];
  @State statusText: string = 'Loading history...';
  @State showDetail: boolean = false;
  @State showReader: boolean = false;
  @State showComments: boolean = false;
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailStatus: string = 'Tap a history item to load detail';
  @State detailRequestUrl: string = '';
  @State detailDownloadText: string = 'Download';
  @State readerStatus: string = 'Reader is ready';
  @State readerPage: GalleryPage = createEmptyPage();
  @State readerPreviewIndex: number = 0;
  @State renderVersion: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  private historyScroller: Scroller = new Scroller();
  private historyScrollOffset: number = 0;
  private detailScrollOffset: number = 0;

  aboutToAppear(): void {
    setActiveBackHandler(() => this.handleSystemBack());
    this.loadHistory();
  }

  aboutToDisappear(): void {
    setActiveBackHandler(null);
  }

  private handleSystemBack(): boolean {
    if (this.showReader) { this.closeReader(); return true; }
    if (this.showComments) { this.closeComments(); return true; }
    if (this.showDetail) { this.closeDetail(); return true; }
    return false;
  }

  private loadHistory(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.histories = cloneGalleryInfos(ehHistoryStore.getItems());
      this.statusText = this.histories.length.toString() + ' local history items';
      this.renderVersion++;
      return;
    }

    ehHistoryStore.load(context).then(() => {
      this.histories = cloneGalleryInfos(ehHistoryStore.getItems());
      this.statusText = this.histories.length.toString() + ' history items';
      this.renderVersion++;
    }).catch((error: Error) => {
      this.statusText = 'History load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private clearHistory(): void {
    ehHistoryStore.clear();
    this.histories = [];
    this.statusText = 'History cleared';
    this.renderVersion++;
    this.persistHistory();
  }

  private removeHistory(gallery: GalleryInfo): void {
    ehHistoryStore.removeGallery(gallery.gid);
    this.histories = cloneGalleryInfos(ehHistoryStore.getItems());
    this.statusText = 'Removed from history: ' + gallery.title;
    this.renderVersion++;
    this.persistHistory();
  }

  private persistHistory(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehHistoryStore.save(context).catch((error: Error) => {
      this.statusText = 'History save failed: ' + error.message;
    });
  }

  private loadDetail(gallery: GalleryInfo): void {
    this.showDetail = true;
    this.detail = createDetailFromGallery(gallery);
    this.detailStatus = 'Loading detail for gid ' + gallery.gid.toString() + '...';
    this.detailRequestUrl = '';
    this.detailDownloadText = downloadButtonText(gallery.gid);
    this.renderVersion++;

    this.client.loadGalleryDetail(gallery.gid, gallery.token, 0, currentGallerySite(), '').then((result: GalleryDetailLoadResult) => {
      this.detailRequestUrl = result.url;
      if (!result.ok || result.detail === null) {
        this.detailStatus = 'Detail load failed: ' + result.message;
        this.renderVersion++;
        return;
      }

      this.detailStatus = 'Detail loaded';
      this.detail = cloneGalleryDetail(result.detail);
      this.detailDownloadText = downloadButtonText(result.detail.gid);
      this.renderVersion++;
      saveGalleryToHistory(result.detail);
      this.loadHistory();
      this.prewarmReader();
    }).catch((error: Error) => {
      this.detailStatus = 'Detail load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private closeDetail(): void {
    this.showDetail = false;
    this.showReader = false;
    this.showComments = false;
    this.detail = createEmptyDetail();
    this.detailStatus = 'Tap a history item to load detail';
    this.detailRequestUrl = '';
    this.detailDownloadText = 'Download';
    this.readerStatus = 'Reader is ready';
    this.readerPage = createEmptyPage();
    this.readerPreviewIndex = 0;
    this.detailScrollOffset = 0;
    this.renderVersion++;
    this.loadHistory();
  }

  private openComments(): void {
    this.showComments = true;
    this.renderVersion++;
  }

  private closeComments(): void {
    this.showComments = false;
    this.renderVersion++;
  }

  private closeReader(): void {
    this.showReader = false;
    this.readerStatus = 'Reader is ready';
    this.readerPage = createEmptyPage();
    this.readerPreviewIndex = 0;
    this.renderVersion++;
  }

  private loadReaderPage(preview: GalleryPreview): void {
    if (preview.pageUrl.length === 0) {
      this.readerStatus = 'Preview has no page URL';
      return;
    }

    this.showReader = true;
    this.readerPreviewIndex = preview.index;
    saveGalleryReadPosition(this.detail.gid, preview.index);
    this.readerStatus = 'Loading page ' + (preview.index + 1).toString() + '...';
    this.readerPage = createReaderLoadingPage(preview.pageUrl);
    this.renderVersion++;

    const cached = galleryPageCache.get(preview.pageUrl);
    if (cached !== null) {
      this.readerStatus = 'Page loaded from cache';
      this.readerPage = cloneGalleryPage(cached);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, cached);
      this.preloadReaderPages(preview.index);
      return;
    }

    this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
      readerPageReferer(this.detailRequestUrl, this.detail.previewSet, preview.index, currentGallerySite())).then((result: GalleryPageLoadResult) => {
      if (!result.ok || result.page === null) {
        this.readerStatus = 'Page load failed: ' + result.message;
        return;
      }
      const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
      galleryPageCache.put(cacheUrl, result.page);
      galleryPageCache.put(preview.pageUrl, result.page);
      this.readerStatus = 'Page loaded';
      this.readerPage = cloneGalleryPage(result.page);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, result.page);
      this.preloadReaderPages(preview.index);
    }).catch((error: Error) => {
      this.readerStatus = 'Page load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private cacheReaderImage(index: number, page: GalleryPage): void {
    cacheReaderImageForPage(page, (cachedPage: GalleryPage) => {
      galleryPageCache.put(cachedPage.pageUrl.length > 0 ? cachedPage.pageUrl : page.pageUrl, cachedPage);
      if (this.showReader && this.readerPreviewIndex === index) {
        this.readerPage = cloneGalleryPage(cachedPage);
        this.readerStatus = 'Page loaded from local cache';
        this.renderVersion++;
      }
    });
  }

  private async preloadReaderPages(index: number): Promise<void> {
    const count = readerPreloadCount();
    if (count <= 0) {
      return;
    }

    for (let offset = 1; offset <= count; offset++) {
      const nextIndex = index + offset;
      if (nextIndex < 0 || nextIndex >= this.detail.previewSet.length) {
        return;
      }

      const preview = this.detail.previewSet[nextIndex];
      if (preview.pageUrl.length === 0 || galleryPageCache.has(preview.pageUrl)) {
        continue;
      }

      try {
        const result = await this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
          readerPageReferer(this.detailRequestUrl, this.detail.previewSet, nextIndex, currentGallerySite()));
        if (result.ok && result.page !== null) {
          const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
          galleryPageCache.put(cacheUrl, result.page);
          galleryPageCache.put(preview.pageUrl, result.page);
          this.cacheReaderImage(nextIndex, result.page);
        }
      } catch (error) {
      }
    }
  }

  private async prewarmReader(): Promise<void> {
    if (this.detail.previewSet.length === 0) {
      return;
    }

    const preview = this.detail.previewSet[0];
    if (preview.pageUrl.length === 0 || galleryPageCache.has(preview.pageUrl)) {
      return;
    }

    try {
      const result = await this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
        readerPageReferer(this.detailRequestUrl, this.detail.previewSet, 0, currentGallerySite()));
      if (result.ok && result.page !== null) {
        const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
        galleryPageCache.put(cacheUrl, result.page);
        galleryPageCache.put(preview.pageUrl, result.page);
        this.cacheReaderImage(0, result.page);
        this.preloadReaderPages(0);
      }
    } catch (error) {
    }
  }

  private loadReaderPageByIndex(index: number): void {
    if (index < 0 || index >= this.detail.previewSet.length) {
      return;
    }
    this.loadReaderPage(this.detail.previewSet[index]);
  }

  private readDetail(): void {
    if (this.detail.previewSet.length === 0) {
      this.detailStatus = 'Read is waiting for preview pages';
      return;
    }
    this.loadReaderPageByIndex(readerStartIndex(this.detail));
  }

  private toggleDownloadDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'Download needs a loaded gallery';
      return;
    }
    const queued = toggleGalleryDownload(this.detail);
    this.detailDownloadText = queued ? 'Queued' : 'Download';
    this.detailStatus = queued ? 'Added to download queue' : 'Removed from download queue';
    this.renderVersion++;
  }

  private toggleFavoriteDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'No gallery loaded';
      return;
    }
    const wasFavorited = this.detail.isFavorited;
    this.detailStatus = wasFavorited ? 'Removing from favorites...' : 'Adding to favorites...';
    this.client.toggleFavorite(this.detail.gid, this.detail.token, wasFavorited,
      GallerySite.E).then((result: ToggleFavoriteResult) => {
      this.detailStatus = result.message;
      if (result.ok) {
        this.detail.isFavorited = result.nowFavorited;
      }
      this.renderVersion++;
    }).catch((error: Error) => {
      this.detailStatus = 'Favorite failed: ' + error.message;
    });
  }

  private shareDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'No gallery loaded';
      return;
    }
    const url = EhUrl.getGalleryDetailUrl(this.detail.gid, this.detail.token, 0, false, GallerySite.E);
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(data);
      this.detailStatus = 'Gallery URL copied to clipboard';
    } catch (error) {
      this.detailStatus = 'Copy failed: ' + String(error);
    }
    this.renderVersion++;
  }

  build() {
    if (this.showReader) {
      ReaderScene({
        renderVersion: this.renderVersion,
        page: this.readerPage,
        statusText: this.readerStatus,
        pageIndex: this.readerPreviewIndex,
        totalPages: this.detail.previewSet.length,
        onBack: () => {
          this.closeReader();
        },
        onPrev: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex - 1);
        },
        onNext: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex + 1);
        },
        onJump: (index: number) => {
          this.loadReaderPageByIndex(index);
        },
        onRetry: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex);
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showComments) {
      CommentsScene({
        renderVersion: this.renderVersion,
        comments: this.detail.comments,
        galleryTitle: galleryDisplayTitle(this.detail),
        onBack: () => {
          this.closeComments();
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showDetail) {
      GalleryDetailScene({
        renderVersion: this.renderVersion,
        detail: this.detail,
        isFavorited: this.detail.isFavorited,
        statusText: this.detailStatus,
        requestUrl: this.detailRequestUrl,
        downloadText: this.detailDownloadText,
        onBack: () => {
          this.closeDetail();
        },
        onDownload: () => {
          this.toggleDownloadDetail();
        },
        onRead: () => {
          this.readDetail();
        },
        onSelectPreview: (preview: GalleryPreview) => {
          this.loadReaderPage(preview);
        },
        onComments: () => {
          this.openComments();
        },
        onFavorite: () => {
          this.toggleFavoriteDetail();
        },
        onShare: () => {
          this.shareDetail();
        },
        initialDetailScrollOffset: this.detailScrollOffset,
        onDetailScrollUpdate: (offset: number) => {
          this.detailScrollOffset = offset;
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else {
      Column() {
        TopListHeader({
          title: 'History',
          statusText: this.statusText,
          requestUrl: '',
          showClear: true,
          canClear: this.histories.length > 0,
          onMenu: this.onMenu,
          onRefresh: () => {
            this.loadHistory();
          },
          onClear: () => {
            this.clearHistory();
          }
        })

        if (this.histories.length === 0) {
          PlaceholderScene({
            title: 'History',
            detail: 'Viewed gallery details will appear here. Open a gallery from Homepage, Favorites or Top Lists to add it.'
          })
        } else {
          List({ space: 8, scroller: this.historyScroller }) {
            ForEach(this.histories, (gallery: GalleryInfo) => {
              ListItem() {
                Column() {
                  GalleryListRow({ gallery: gallery })
                    .onClick(() => {
                      this.loadDetail(gallery);
                    })
                  Row() {
                    Text(uiText('Remove'))
                      .fontSize(12)
                      .fontColor('#C33A2C')
                      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                      .onClick(() => {
                        this.removeHistory(gallery);
                      })
                    Blank()
                  }
                  .width('100%')
                  .padding({ right: 8, bottom: 6 })
                  .backgroundColor(Color.White)
                }
                .borderRadius(6)
              }
            }, (gallery: GalleryInfo) => gallery.gid.toString() + ':' + this.renderVersion.toString())
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 8, right: 8, top: 8, bottom: 12 })
          .onAppear(() => {
            if (this.historyScrollOffset > 0) {
              this.historyScroller.scrollTo({ xOffset: 0, yOffset: this.historyScrollOffset });
            }
          })
          .onScrollStop(() => {
            this.historyScrollOffset = this.historyScroller.currentOffset().yOffset;
          })
        }
      }
      .width('100%')
      .height('100%')
    }
  }
}

@Component
export struct TopListScene {
  private client: EhHttpClient = new EhHttpClient();
  onMenu: () => void = () => {};

  @State statusText: string = 'Loading top lists...';
  @State requestUrl: string = '';
  @State selectedIndex: number = 0;
  @State topList: TopListDetail = createEmptyTopListDetail();
  @State showGalleryList: boolean = false;
  @State galleryListTitle: string = 'Top List';
  @State galleryListModeLabel: string = 'Top List';
  @State galleryFollow: string = '';
  @State galleryKeyword: string = '';
  @State galleryRoute: GalleryRoute = GalleryRoute.TopLists;
  @State galleryUseForcedMode: boolean = false;
  @State galleryForcedMode: ListMode = ListMode.Normal;
  @State showDetail: boolean = false;
  @State showReader: boolean = false;
  @State showComments: boolean = false;
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailStatus: string = 'Tap a ranking item to load detail';
  @State detailRequestUrl: string = '';
  @State detailDownloadText: string = 'Download';
  @State readerStatus: string = 'Reader is ready';
  @State readerPage: GalleryPage = createEmptyPage();
  @State readerPreviewIndex: number = 0;
  @State renderVersion: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  private topListScroller: Scroller = new Scroller();
  private topListScrollOffset: number = 0;
  private detailScrollOffset: number = 0;

  aboutToAppear(): void {
    setActiveBackHandler(() => this.handleSystemBack());
    this.loadTopList();
  }

  aboutToDisappear(): void {
    setActiveBackHandler(null);
  }

  private handleSystemBack(): boolean {
    if (this.showReader) { this.closeReader(); return true; }
    if (this.showComments) { this.closeComments(); return true; }
    if (this.showDetail) { this.closeDetail(); return true; }
    if (this.showGalleryList) { this.closeGalleryList(); return true; }
    return false;
  }

  private loadTopList(): void {
    this.statusText = 'Loading top lists...';
    this.renderVersion++;
    this.client.loadTopList(GallerySite.E).then((result: TopListLoadResult) => {
      this.requestUrl = result.url;
      if (!result.ok || result.detail === null) {
        this.statusText = 'Load failed: ' + result.message;
        this.renderVersion++;
        return;
      }
      this.topList = cloneTopListDetail(result.detail);
      this.statusText = result.message + ': ' + result.detail.lists.length.toString() + ' sections';
      if (this.selectedIndex >= result.detail.lists.length) {
        this.selectedIndex = 0;
      }
      this.renderVersion++;
    }).catch((error: Error) => {
      this.statusText = 'Load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private openBucket(bucket: TopListBucket): void {
    this.galleryListTitle = 'Gallery Toplists';
    this.galleryListModeLabel = bucket.title;
    this.galleryFollow = bucket.follow;
    this.galleryKeyword = '';
    this.galleryRoute = GalleryRoute.TopLists;
    this.galleryUseForcedMode = false;
    this.showGalleryList = true;
  }

  private openTopListItem(item: TopListItem, info: TopListInfo): void {
    if (item.gid.length > 0 && item.token.length > 0) {
      this.loadDetailFromItem(item);
      return;
    }

    this.galleryListTitle = info.title;
    this.galleryListModeLabel = 'Related galleries';
    this.galleryFollow = '';
    this.galleryKeyword = item.value;
    this.galleryRoute = GalleryRoute.Home;
    this.galleryUseForcedMode = true;
    this.galleryForcedMode = info.kind === TopListKind.Uploader ? ListMode.Uploader : ListMode.Normal;
    this.showGalleryList = true;
  }

  private closeGalleryList(): void {
    this.showGalleryList = false;
    this.galleryFollow = '';
    this.galleryKeyword = '';
    this.galleryUseForcedMode = false;
  }

  private loadDetailFromItem(item: TopListItem): void {
    const gid = Number.parseInt(item.gid);
    if (Number.isNaN(gid)) {
      this.statusText = 'Invalid gallery id: ' + item.gid;
      return;
    }

    this.showDetail = true;
    const loadingDetail = createEmptyDetail();
    loadingDetail.gid = gid;
    loadingDetail.token = item.token;
    loadingDetail.title = item.value;
    this.detail = loadingDetail;
    this.detailStatus = 'Loading detail for gid ' + item.gid + '...';
    this.detailRequestUrl = '';
    this.detailDownloadText = downloadButtonText(gid);
    this.renderVersion++;

    this.client.loadGalleryDetail(gid, item.token, 0, GallerySite.E, this.requestUrl).then((result: GalleryDetailLoadResult) => {
      this.detailRequestUrl = result.url;
      if (!result.ok || result.detail === null) {
        this.detailStatus = 'Detail load failed: ' + result.message;
        this.renderVersion++;
        return;
      }
      this.detailStatus = 'Detail loaded';
      this.detail = cloneGalleryDetail(result.detail);
      this.detailDownloadText = downloadButtonText(result.detail.gid);
      this.renderVersion++;
      saveGalleryToHistory(result.detail);
      this.prewarmReader();
    }).catch((error: Error) => {
      this.detailStatus = 'Detail load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private closeDetail(): void {
    this.showDetail = false;
    this.showReader = false;
    this.showComments = false;
    this.detail = createEmptyDetail();
    this.detailStatus = 'Tap a ranking item to load detail';
    this.detailRequestUrl = '';
    this.detailDownloadText = 'Download';
    this.readerStatus = 'Reader is ready';
    this.readerPage = createEmptyPage();
    this.readerPreviewIndex = 0;
    this.detailScrollOffset = 0;
    this.renderVersion++;
  }

  private openComments(): void {
    this.showComments = true;
    this.renderVersion++;
  }

  private closeComments(): void {
    this.showComments = false;
    this.renderVersion++;
  }

  private closeReader(): void {
    this.showReader = false;
    this.readerStatus = 'Reader is ready';
    this.readerPage = createEmptyPage();
    this.readerPreviewIndex = 0;
    this.renderVersion++;
  }

  private loadReaderPage(preview: GalleryPreview): void {
    if (preview.pageUrl.length === 0) {
      this.readerStatus = 'Preview has no page URL';
      return;
    }

    this.showReader = true;
    this.readerPreviewIndex = preview.index;
    saveGalleryReadPosition(this.detail.gid, preview.index);
    this.readerStatus = 'Loading page ' + (preview.index + 1).toString() + '...';
    this.readerPage = createReaderLoadingPage(preview.pageUrl);
    this.renderVersion++;

    const cached = galleryPageCache.get(preview.pageUrl);
    if (cached !== null) {
      this.readerStatus = 'Page loaded from cache';
      this.readerPage = cloneGalleryPage(cached);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, cached);
      this.preloadReaderPages(preview.index);
      return;
    }

    this.client.loadGalleryPage(preview.pageUrl, GallerySite.E,
      readerPageReferer(this.detailRequestUrl, this.detail.previewSet, preview.index, GallerySite.E)).then((result: GalleryPageLoadResult) => {
      if (!result.ok || result.page === null) {
        this.readerStatus = 'Page load failed: ' + result.message;
        return;
      }
      const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
      galleryPageCache.put(cacheUrl, result.page);
      galleryPageCache.put(preview.pageUrl, result.page);
      this.readerStatus = 'Page loaded';
      this.readerPage = cloneGalleryPage(result.page);
      this.renderVersion++;
      this.cacheReaderImage(preview.index, result.page);
      this.preloadReaderPages(preview.index);
    }).catch((error: Error) => {
      this.readerStatus = 'Page load failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private cacheReaderImage(index: number, page: GalleryPage): void {
    cacheReaderImageForPage(page, (cachedPage: GalleryPage) => {
      galleryPageCache.put(cachedPage.pageUrl.length > 0 ? cachedPage.pageUrl : page.pageUrl, cachedPage);
      if (this.showReader && this.readerPreviewIndex === index) {
        this.readerPage = cloneGalleryPage(cachedPage);
        this.readerStatus = 'Page loaded from local cache';
        this.renderVersion++;
      }
    });
  }

  private async preloadReaderPages(index: number): Promise<void> {
    const count = readerPreloadCount();
    if (count <= 0) {
      return;
    }

    for (let offset = 1; offset <= count; offset++) {
      const nextIndex = index + offset;
      if (nextIndex < 0 || nextIndex >= this.detail.previewSet.length) {
        return;
      }

      const preview = this.detail.previewSet[nextIndex];
      if (preview.pageUrl.length === 0 || galleryPageCache.has(preview.pageUrl)) {
        continue;
      }

      try {
        const result = await this.client.loadGalleryPage(preview.pageUrl, GallerySite.E,
          readerPageReferer(this.detailRequestUrl, this.detail.previewSet, nextIndex, GallerySite.E));
        if (result.ok && result.page !== null) {
          const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
          galleryPageCache.put(cacheUrl, result.page);
          galleryPageCache.put(preview.pageUrl, result.page);
          this.cacheReaderImage(nextIndex, result.page);
        }
      } catch (error) {
      }
    }
  }

  private async prewarmReader(): Promise<void> {
    if (this.detail.previewSet.length === 0) {
      return;
    }

    const preview = this.detail.previewSet[0];
    if (preview.pageUrl.length === 0 || galleryPageCache.has(preview.pageUrl)) {
      return;
    }

    try {
      const result = await this.client.loadGalleryPage(preview.pageUrl, GallerySite.E,
        readerPageReferer(this.detailRequestUrl, this.detail.previewSet, 0, GallerySite.E));
      if (result.ok && result.page !== null) {
        const cacheUrl = result.page.pageUrl.length > 0 ? result.page.pageUrl : preview.pageUrl;
        galleryPageCache.put(cacheUrl, result.page);
        galleryPageCache.put(preview.pageUrl, result.page);
        this.cacheReaderImage(0, result.page);
        this.preloadReaderPages(0);
      }
    } catch (error) {
    }
  }

  private loadReaderPageByIndex(index: number): void {
    if (index < 0 || index >= this.detail.previewSet.length) {
      return;
    }
    this.loadReaderPage(this.detail.previewSet[index]);
  }

  private readDetail(): void {
    if (this.detail.previewSet.length === 0) {
      this.detailStatus = 'Read is waiting for preview pages';
      return;
    }
    this.loadReaderPageByIndex(readerStartIndex(this.detail));
  }

  private toggleDownloadDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'Download needs a loaded gallery';
      return;
    }
    const queued = toggleGalleryDownload(this.detail);
    this.detailDownloadText = queued ? 'Queued' : 'Download';
    this.detailStatus = queued ? 'Added to download queue' : 'Removed from download queue';
    this.renderVersion++;
  }

  private toggleFavoriteDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'No gallery loaded';
      return;
    }
    const wasFavorited = this.detail.isFavorited;
    this.detailStatus = wasFavorited ? 'Removing from favorites...' : 'Adding to favorites...';
    this.client.toggleFavorite(this.detail.gid, this.detail.token, wasFavorited,
      GallerySite.E).then((result: ToggleFavoriteResult) => {
      this.detailStatus = result.message;
      if (result.ok) {
        this.detail.isFavorited = result.nowFavorited;
      }
      this.renderVersion++;
    }).catch((error: Error) => {
      this.detailStatus = 'Favorite failed: ' + error.message;
    });
  }

  private shareDetail(): void {
    if (this.detail.gid <= 0) {
      this.detailStatus = 'No gallery loaded';
      return;
    }
    const url = EhUrl.getGalleryDetailUrl(this.detail.gid, this.detail.token, 0, false, GallerySite.E);
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(data);
      this.detailStatus = 'Gallery URL copied to clipboard';
    } catch (error) {
      this.detailStatus = 'Copy failed: ' + String(error);
    }
    this.renderVersion++;
  }

  private currentInfo(): TopListInfo {
    if (this.topList.lists.length === 0 || this.selectedIndex < 0 || this.selectedIndex >= this.topList.lists.length) {
      return createEmptyTopListInfo();
    }
    return this.topList.lists[this.selectedIndex];
  }

  build() {
    if (this.showReader) {
      ReaderScene({
        renderVersion: this.renderVersion,
        page: this.readerPage,
        statusText: this.readerStatus,
        pageIndex: this.readerPreviewIndex,
        totalPages: this.detail.previewSet.length,
        onBack: () => {
          this.closeReader();
        },
        onPrev: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex - 1);
        },
        onNext: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex + 1);
        },
        onJump: (index: number) => {
          this.loadReaderPageByIndex(index);
        },
        onRetry: () => {
          this.loadReaderPageByIndex(this.readerPreviewIndex);
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showComments) {
      CommentsScene({
        renderVersion: this.renderVersion,
        comments: this.detail.comments,
        galleryTitle: galleryDisplayTitle(this.detail),
        onBack: () => {
          this.closeComments();
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showDetail) {
      GalleryDetailScene({
        renderVersion: this.renderVersion,
        detail: this.detail,
        isFavorited: this.detail.isFavorited,
        statusText: this.detailStatus,
        requestUrl: this.detailRequestUrl,
        downloadText: this.detailDownloadText,
        onBack: () => {
          this.closeDetail();
        },
        onDownload: () => {
          this.toggleDownloadDetail();
        },
        onRead: () => {
          this.readDetail();
        },
        onSelectPreview: (preview: GalleryPreview) => {
          this.loadReaderPage(preview);
        },
        onComments: () => {
          this.openComments();
        },
        onFavorite: () => {
          this.toggleFavoriteDetail();
        },
        onShare: () => {
          this.shareDetail();
        },
        initialDetailScrollOffset: this.detailScrollOffset,
        onDetailScrollUpdate: (offset: number) => {
          this.detailScrollOffset = offset;
        }
      })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
    } else if (this.showGalleryList) {
      Column() {
        Row() {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(20)
              .fontColor([Color.White])
          }
          .width(36)
          .height(36)
          .backgroundColor('#2F6F8F')
          .onClick(() => {
            this.closeGalleryList();
          })
          Text(uiText(this.galleryListTitle) + ' / ' + uiText(this.galleryListModeLabel))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#17202A')
            .margin({ left: 12 })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 8 })
        .backgroundColor(Color.White)

        GalleryListScene({
          sceneTitle: this.galleryListTitle,
          listMode: this.galleryListModeLabel,
          sourceRoute: this.galleryRoute,
          follow: this.galleryFollow,
          initialKeyword: this.galleryKeyword,
          useForcedMode: this.galleryUseForcedMode,
          forcedMode: this.galleryForcedMode
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .transition(TransitionEffect.move(TransitionEdge.END)
        .animation({ duration: 300, curve: Curve.EaseOut }))
    } else {
      Column() {
        TopListHeader({
          title: this.topList.title.length === 0 ? uiText('Top Lists') : this.topList.title,
          statusText: this.statusText,
          requestUrl: this.requestUrl,
          onMenu: this.onMenu,
          onRefresh: () => {
            this.loadTopList();
          }
        })

        TopListTabs({
          lists: this.topList.lists,
          selectedIndex: this.selectedIndex,
          onSelect: (index: number) => {
            this.selectedIndex = index;
          }
        })
          .margin({ left: 12, right: 12, bottom: 8 })

        TopListBoard({
          info: this.currentInfo(),
          onOpenBucket: (bucket: TopListBucket) => {
            this.openBucket(bucket);
          },
          onOpenItem: (item: TopListItem, info: TopListInfo) => {
            this.openTopListItem(item, info);
          },
          initialScrollOffset: this.topListScrollOffset,
          onScrollUpdate: (offset: number) => {
            this.topListScrollOffset = offset;
          }
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }
}

@Component
export struct TopListHeader {
  @Prop title: string = '';
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  @Prop showClear: boolean = false;
  @Prop canClear: boolean = false;
  onMenu: () => void = () => {};
  onRefresh: () => void = () => {};
  onClear: () => void = () => {};

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.open_sidebar'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(38)
        .height(38)
        .backgroundColor('rgba(255,255,255,0.15)')
        .flexShrink(0)
        .onClick(() => {
          this.onMenu();
        })

        Column() {
          Text(uiText(this.title))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#17202A')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.statusText.length > 0) {
            Text(uiStatusText(this.statusText))
              .fontSize(11)
              .fontColor('#667085')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
          }
        }
        .height(38)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
        .margin({ left: 10 })
        .backgroundColor(Color.White)
        .borderRadius(19)

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.play_arrow_triangle_2_circlepath'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(38)
        .height(38)
        .backgroundColor('rgba(255,255,255,0.15)')
        .flexShrink(0)
        .margin({ left: 10 })
        .onClick(() => {
          this.onRefresh();
        })

        if (this.showClear) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(17)
              .fontColor([Color.White])
          }
          .width(38)
          .height(38)
          .backgroundColor(this.canClear ? 'rgba(220,60,50,0.78)' : 'rgba(255,255,255,0.1)')
          .flexShrink(0)
          .margin({ left: 8 })
          .enabled(this.canClear)
          .onClick(() => {
            this.onClear();
          })
        }
      }
      .width('100%')
      .height(62)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)

      if (this.requestUrl.length > 0) {
        Row() {
          Text(this.requestUrl)
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.75)')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(26)
        .padding({ left: 16, right: 14 })
        .backgroundColor('rgba(0,0,0,0.12)')
      }
    }
    .width('100%')
    .backgroundColor('#2F6F8F')
  }
}

@Component
export struct TopListTabs {
  @Prop lists: TopListInfo[] = [];
  @Prop selectedIndex: number = 0;
  onSelect: (index: number) => void = () => {};

  build() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.lists, (info: TopListInfo, index: number) => {
          Button(info.title)
            .height(34)
            .fontSize(12)
            .fontColor(index === this.selectedIndex ? Color.White : '#2F6F8F')
            .backgroundColor(index === this.selectedIndex ? '#2F6F8F' : Color.White)
            .border({ width: 1, color: '#D0D5DD' })
            .onClick(() => {
              this.onSelect(index);
            })
        }, (info: TopListInfo) => info.kind.toString())
      }
      .padding({ left: 2, right: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }
}

@Component
export struct TopListBoard {
  @Prop info: TopListInfo = createEmptyTopListInfo();
  onOpenBucket: (bucket: TopListBucket) => void = () => {};
  onOpenItem: (item: TopListItem, info: TopListInfo) => void = () => {};
  initialScrollOffset: number = 0;
  onScrollUpdate: (offset: number) => void = () => {};
  private boardScroller: Scroller = new Scroller();

  build() {
    List({ space: 10, scroller: this.boardScroller }) {
      ForEach(this.info.buckets, (bucket: TopListBucket) => {
        ListItem() {
          TopListBucketCard({
            bucket: bucket,
            info: this.info,
            canOpenBucket: this.info.kind === TopListKind.Gallery,
            onOpenBucket: this.onOpenBucket,
            onOpenItem: this.onOpenItem
          })
        }
      }, (bucket: TopListBucket) => bucket.title)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, bottom: 14 })
    .onAppear(() => {
      if (this.initialScrollOffset > 0) {
        this.boardScroller.scrollTo({ xOffset: 0, yOffset: this.initialScrollOffset });
      }
    })
    .onScrollStop(() => {
      this.onScrollUpdate(this.boardScroller.currentOffset().yOffset);
    })
  }
}

@Component
export struct TopListBucketCard {
  bucket: TopListBucket = createEmptyTopListBucket();
  info: TopListInfo = createEmptyTopListInfo();
  canOpenBucket: boolean = false;
  onOpenBucket: (bucket: TopListBucket) => void = () => {};
  onOpenItem: (item: TopListItem, info: TopListInfo) => void = () => {};

  build() {
    Column() {
      Row() {
        Text(this.bucket.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.canOpenBucket ? '#2F6F8F' : '#17202A')
          .layoutWeight(1)
          .decoration({ type: this.canOpenBucket ? TextDecorationType.Underline : TextDecorationType.None })
          .onClick(() => {
            if (this.canOpenBucket) {
              this.onOpenBucket(this.bucket);
            }
          })
        Text(this.bucket.items.length.toString() + ' entries')
          .fontSize(12)
          .fontColor('#667085')
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.bucket.items, (item: TopListItem, index: number) => {
          TopListChip({
            item: item,
            color: topListChipColor(index),
            onTap: () => {
              this.onOpenItem(item, this.info);
            }
          })
        }, (item: TopListItem) => item.href + item.value)
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(6)
  }
}

@Component
export struct TopListChip {
  item: TopListItem = createEmptyTopListItem();
  color: string = '#2F6F8F';
  onTap: () => void = () => {};

  build() {
    Text(this.item.value)
      .fontSize(13)
      .fontColor(Color.White)
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .margin({ right: 8, bottom: 8 })
      .backgroundColor(this.color)
      .borderRadius(5)
      .onClick(() => {
        this.onTap();
      })
  }
}
