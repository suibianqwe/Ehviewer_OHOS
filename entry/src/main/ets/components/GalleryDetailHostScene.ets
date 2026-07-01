import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { ArchiveOption, ArchiverInfo, ArchiverOption, GalleryDetail, GalleryPreview, HathArchiveList } from '../model/GalleryModels';
import { confirmCellularNetworkWarningForSession, shouldConfirmCellularNetworkOperation } from '../services/EhCellularNetworkGuard';
import { ehDownloadManager } from '../services/EhDownloadManager';
import { DownloadInfo, ehDownloadStore } from '../services/EhDownloadStore';
import {
  ArchiverDownloadResult,
  ArchiverLoadResult,
  EhHttpClient,
  HathArchiveListLoadResult,
  HathArchiveSubmitResult,
  RateGalleryResult,
  ToggleFavoriteResult
} from '../services/EhHttpClient';
import { EhUrl } from '../services/EhUrl';
import {
  archiveUnavailableReason,
  createCoverSearchRequest,
  createSimilarGallerySearch,
  createTagSearchRequest,
  DetailSearchRequest,
  detailArchiveReferer,
  detailCoverCacheKey
} from '../services/GalleryDetailActionSupport';
import {
  createDownloadReaderSessionState,
  detailDownloadButtonText,
  DetailDownloadToggleResult,
  findDetailDownloadItem,
  refreshDetailDownloadItem,
  toggleDetailDownloadTask
} from '../services/GalleryDetailDownloadSupport';
import {
  createEmptyGalleryDetailLink,
  GalleryDetailLink,
  GalleryDetailModuleLoadResult,
  initialDetailForLink,
  loadGalleryDetailModule
} from '../services/GalleryDetailModule';
import { DetailPreviewPager, mergeGalleryPreviewSets, seedPreviewMap } from '../services/GalleryPreviewLoader';
import { readerImageCache } from '../services/ReaderImageCache';
import { createReaderSessionState, readerSessionStore } from '../services/ReaderSessionStore';
import { ehSettingsStore } from '../services/EhSettingsStore';
import {
  cloneGalleryDetail,
  createEmptyDetail,
  createEmptyPage,
  getAbilityContext,
  readerStartIndex,
  readerStartIndexAsync,
  readerPageImageCacheKey,
  saveGalleryToHistory,
  uiText
} from '../shared/EhShared';
import { themePrimaryColor, themeSecondaryText } from '../shared/EhTheme';
import { GalleryDetailOverlayScene } from './GalleryDetailScenes';

@Component
export struct GalleryDetailHostScene {
  @Prop detailLink: GalleryDetailLink = createEmptyGalleryDetailLink();
  listRequestUrl: string = '';
  initialDetailScrollOffset: number = 0;
  onBack: () => void = () => {};
  onShowEmbeddedReader: () => void = () => {};
  onOpenSearch: (request: DetailSearchRequest) => void = (_request: DetailSearchRequest) => {};
  onDetailLoaded: (detail: GalleryDetail) => void = (_detail: GalleryDetail) => {};
  onDetailScrollUpdate: (offset: number) => void = (_offset: number) => {};

  private client: EhHttpClient = new EhHttpClient();
  private detailPreviewPager: DetailPreviewPager = new DetailPreviewPager();
  private previewMap: Map<number, GalleryPreview> = new Map();
  private previewPageSize: number = 0;
  private unsubscribeDownloadStore: () => void = () => {};
  private cellularWarningDialogOpen: boolean = false;
  @State renderVersion: number = 0;
  @State showComments: boolean = false;
  @State detail: GalleryDetail = createEmptyDetail();
  @State detailLoaded: boolean = false;
  @State detailStatus: string = '';
  @State detailRequestUrl: string = '';
  @State detailDownloadText: string = 'Download';
  @State optimisticFavorite: boolean = false;
  @State favoriteBusy: boolean = false;
  @State archivePanelVisible: boolean = false;
  @State archivePanelMode: string = '';
  @State archivePanelStatus: string = '';
  @State archiveBusy: boolean = false;
  @State archiverInfo: ArchiverInfo = { funds: '', options: [] };
  @State hathArchiveList: HathArchiveList = { formParamOr: '', options: [] };

  aboutToAppear(): void {
    this.loadDetailFromLink();
    this.unsubscribeDownloadStore = ehDownloadStore.subscribe((_items: DownloadInfo[]) => {
      this.refreshDetailDownloadText();
    });
  }

  aboutToDisappear(): void {
    this.unsubscribeDownloadStore();
  }

  private loadDetailFromLink(): void {
    if (this.detailLink.gid <= 0 || this.detailLink.token.length === 0) {
      this.detail = createEmptyDetail();
      this.detailStatus = 'No gallery loaded';
      this.detailLoaded = false;
      this.renderVersion++;
      return;
    }
    this.closeArchivePanel();
    this.detailPreviewPager.start();
    this.previewMap.clear();
    this.previewPageSize = 0;
    this.showComments = false;
    this.detail = initialDetailForLink(this.detailLink);
    this.detailRequestUrl = this.detailLink.url;
    this.detailStatus = 'Loading detail for gid ' + this.detailLink.gid.toString() + '...';
    this.detailDownloadText = detailDownloadButtonText(this.detailLink.gid);
    this.detailLoaded = false;
    this.optimisticFavorite = this.detail.favoriteSlot >= 0;
    this.favoriteBusy = false;
    const requestGid = this.detailLink.gid;
    this.renderVersion++;
    loadGalleryDetailModule(this.client, this.detailLink).then((result: GalleryDetailModuleLoadResult) => {
      if (this.detailLink.gid !== requestGid || this.detail.gid !== requestGid) {
        return;
      }
      if (!result.ok) {
        this.detailRequestUrl = result.url;
        this.detailStatus = result.statusText;
        this.renderVersion++;
        return;
      }
      this.detail = result.detail;
      this.detailRequestUrl = result.url;
      this.detailStatus = result.statusText;
      this.detailLoaded = true;
      this.previewPageSize = seedPreviewMap(this.previewMap, this.detail.previewSet, this.previewPageSize);
      this.optimisticFavorite = this.detail.isFavorited;
      refreshDetailDownloadItem(this.detail);
      this.detailDownloadText = detailDownloadButtonText(this.detail.gid);
      saveGalleryToHistory(this.detail);
      this.onDetailLoaded(this.detail);
      this.renderVersion++;
    }).catch((error: Error) => {
      if (this.detailLink.gid === requestGid && this.detail.gid === requestGid) {
        this.detailStatus = 'Detail load failed: ' + error.message;
        this.renderVersion++;
      }
    });
  }

  private refreshDetailDownloadText(): void {
    if (this.detail.gid <= 0) {
      return;
    }
    this.detailDownloadText = detailDownloadButtonText(this.detail.gid);
    this.renderVersion++;
  }

  private openComments(): void {
    if (!this.detailLoaded || this.detail.comments.length === 0) {
      return;
    }
    this.showComments = true;
    this.renderVersion++;
  }

  private readDetail(): void {
    const downloadItem = findDetailDownloadItem(this.detail.gid);
    if (downloadItem !== null) {
      readerStartIndexAsync(this.detail).then((index: number) => {
        this.openDownloadedReaderAt(downloadItem, index);
      }).catch(() => {
        this.openDownloadedReaderAt(downloadItem, readerStartIndex(this.detail));
      });
      return;
    }
    readerStartIndexAsync(this.detail).then((index: number) => {
      this.openRemoteReaderAt(index);
    }).catch(() => {
      this.openRemoteReaderAt(readerStartIndex(this.detail));
    });
  }

  private openRemoteReaderAt(index: number): void {
    if (this.detail.gid <= 0 || (this.detail.pages <= 0 && this.detail.previewSet.length === 0)) {
      this.detailStatus = 'Read is waiting for preview pages';
      this.renderVersion++;
      return;
    }
    readerSessionStore.setSession(createReaderSessionState(this.detail, createEmptyPage(), 'Reader is ready',
      this.detailRequestUrl, this.listRequestUrl, this.detailLink.site, index));
    this.launchReader();
  }

  private openDownloadedReaderAt(item: DownloadInfo, requestedIndex: number): void {
    readerSessionStore.setSession(createDownloadReaderSessionState(item, requestedIndex, this.detailLink.site,
      this.detailRequestUrl, this.listRequestUrl, this.detail));
    this.launchReader();
  }

  private jumpPreviewPage(pageIndex: number): void {
    const total = this.detail.pages > 0 ? this.detail.pages : this.detail.previewSet.length;
    if (total <= 0) {
      this.detailStatus = 'Read is waiting for preview pages';
      this.renderVersion++;
      return;
    }
    const target = Math.max(0, Math.min(pageIndex, total - 1));
    const item = findDetailDownloadItem(this.detail.gid);
    if (item !== null) {
      this.openDownloadedReaderAt(item, target);
    } else {
      this.openRemoteReaderAt(target);
    }
  }

  private launchReader(): void {
    if (ehSettingsStore.getValue('reader_standalone', 'On') !== 'On') {
      this.onShowEmbeddedReader();
      return;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      this.detailStatus = 'Reader launch failed: Ability context is not ready';
      this.renderVersion++;
      return;
    }
    context.startAbility({
      bundleName: 'yt.ehviewer.huawei',
      moduleName: 'entry',
      abilityName: 'ReaderAbility'
    }).catch((error: Error) => {
      this.detailStatus = 'Reader launch failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private toggleDownloadDetail(): void {
    const result: DetailDownloadToggleResult = toggleDetailDownloadTask(this.detail);
    if (result.shouldStartQueue) {
      const context = getAbilityContext();
      if (context !== undefined) {
        this.startDownloadQueueWithCellularGuard(context);
      }
    }
    this.detailDownloadText = result.buttonText;
    this.detailStatus = result.statusText;
    this.renderVersion++;
  }

  private startDownloadQueueWithCellularGuard(context: common.UIAbilityContext): void {
    if (shouldConfirmCellularNetworkOperation()) {
      this.confirmMobileDataDownload(() => {
        ehDownloadManager.startQueue(context);
      });
      return;
    }
    ehDownloadManager.startQueue(context);
  }

  private confirmMobileDataDownload(onContinue: () => void): void {
    if (this.cellularWarningDialogOpen) {
      return;
    }
    this.cellularWarningDialogOpen = true;
    this.getUIContext().getPromptAction().showDialog({
      title: uiText('Mobile data warning'),
      message: uiText('You are using mobile data. Continue downloading?'),
      buttons: [
        { text: uiText('Cancel'), color: themeSecondaryText() },
        { text: uiText('Continue'), color: themePrimaryColor() }
      ]
    }).then((data) => {
      this.cellularWarningDialogOpen = false;
      if (data.index === 1) {
        confirmCellularNetworkWarningForSession();
        onContinue();
      } else {
        this.detailStatus = 'Download waits for Wi-Fi or confirmation';
        this.renderVersion++;
      }
    }).catch(() => {
      this.cellularWarningDialogOpen = false;
      this.detailStatus = 'Download waits for Wi-Fi or confirmation';
      this.renderVersion++;
    });
  }

  private toggleFavoriteDetail(): void {
    if (this.detail.gid <= 0 || this.favoriteBusy) {
      return;
    }
    const wasFavorited = this.detail.isFavorited;
    this.detailStatus = wasFavorited ? 'Removing from favorites...' : 'Adding to favorites...';
    this.favoriteBusy = true;
    this.optimisticFavorite = !wasFavorited;
    this.applyDetailFavoriteState(this.optimisticFavorite);
    this.renderVersion++;
    this.client.toggleFavorite(this.detail.gid, this.detail.token, wasFavorited, this.detailLink.site)
      .then((result: ToggleFavoriteResult) => {
        this.detailStatus = result.message;
        this.optimisticFavorite = result.ok ? result.nowFavorited : wasFavorited;
        this.applyDetailFavoriteState(this.optimisticFavorite);
        this.favoriteBusy = false;
        this.renderVersion++;
      }).catch((error: Error) => {
        this.detailStatus = 'Favorite failed: ' + error.message;
        this.optimisticFavorite = wasFavorited;
        this.applyDetailFavoriteState(wasFavorited);
        this.favoriteBusy = false;
        this.renderVersion++;
      });
  }

  private applyDetailFavoriteState(isFavorited: boolean): void {
    const nextDetail = cloneGalleryDetail(this.detail);
    nextDetail.isFavorited = isFavorited;
    nextDetail.favoriteSlot = isFavorited ? Math.max(0, nextDetail.favoriteSlot) : -2;
    this.detail = nextDetail;
  }

  private rateDetail(rating: number): void {
    if (this.detail.gid <= 0 || this.detail.apiUid < 0 || this.detail.apiKey.length === 0) {
      this.detailStatus = 'Rating needs a loaded gallery session';
      this.renderVersion++;
      return;
    }
    this.detailStatus = 'Submitting rating...';
    this.renderVersion++;
    this.client.rateGallery(this.detail.gid, this.detail.token, this.detail.apiUid, this.detail.apiKey, rating,
      this.detailLink.site).then((result: RateGalleryResult) => {
      this.detailStatus = result.message;
      if (result.ok) {
        const nextDetail = cloneGalleryDetail(this.detail);
        nextDetail.rating = result.rating;
        nextDetail.ratingCount = result.ratingCount > 0 ? result.ratingCount : nextDetail.ratingCount;
        nextDetail.rated = true;
        this.detail = nextDetail;
      }
      this.renderVersion++;
    }).catch((error: Error) => {
      this.detailStatus = 'Rating failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private copyDetailLink(url: string, label: string): void {
    if (url.length === 0) {
      this.detailStatus = label + ' link is unavailable';
      this.renderVersion++;
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.detailStatus = label + ' link copied to clipboard';
        this.renderVersion++;
      }).catch((error: Error) => {
        this.detailStatus = label + ' copy failed: ' + error.message;
        this.renderVersion++;
      });
      return;
    } catch (error) {
      this.detailStatus = label + ' copy failed: ' + String(error);
    }
    this.renderVersion++;
  }

  private closeArchivePanel(): void {
    this.archivePanelVisible = false;
    this.archivePanelMode = '';
    this.archivePanelStatus = '';
    this.archiveBusy = false;
    this.archiverInfo = { funds: '', options: [] };
    this.hathArchiveList = { formParamOr: '', options: [] };
  }

  private ensureArchiveSession(): boolean {
    const reason = archiveUnavailableReason(this.detailLoaded, this.detail);
    if (reason.length > 0) {
      this.detailStatus = reason;
      this.renderVersion++;
      return false;
    }
    return true;
  }

  private openArchiverPanel(): void {
    if (!this.ensureArchiveSession()) {
      return;
    }
    this.archivePanelVisible = true;
    this.archivePanelMode = 'archiver';
    this.archivePanelStatus = 'Loading...';
    this.archiveBusy = true;
    this.archiverInfo = { funds: '', options: [] };
    this.renderVersion++;
    this.client.loadArchiver(this.detail.gid, this.detail.token, this.detail.archiveUrl, this.detailLink.site)
      .then((result: ArchiverLoadResult) => {
        this.archiveBusy = false;
        this.archivePanelStatus = result.ok ? result.message : 'Archive failed: ' + result.message;
        this.archiverInfo = result.info === null ? { funds: '', options: [] } : result.info;
        this.renderVersion++;
      }).catch((error: Error) => {
        this.archiveBusy = false;
        this.archivePanelStatus = 'Archive failed: ' + error.message;
        this.renderVersion++;
      });
  }

  private openHathPanel(): void {
    if (!this.ensureArchiveSession()) {
      return;
    }
    this.archivePanelVisible = true;
    this.archivePanelMode = 'hath';
    this.archivePanelStatus = 'Loading...';
    this.archiveBusy = true;
    this.hathArchiveList = { formParamOr: '', options: [] };
    this.renderVersion++;
    this.client.loadHathArchiveList(this.detail.gid, this.detail.token, this.detail.archiveUrl, this.detailLink.site)
      .then((result: HathArchiveListLoadResult) => {
        this.archiveBusy = false;
        this.archivePanelStatus = result.ok ? result.message : 'H@H failed: ' + result.message;
        this.hathArchiveList = result.list === null ? { formParamOr: '', options: [] } : result.list;
        this.renderVersion++;
      }).catch((error: Error) => {
        this.archiveBusy = false;
        this.archivePanelStatus = 'H@H failed: ' + error.message;
        this.renderVersion++;
      });
  }

  private submitArchiverOption(option: ArchiverOption): void {
    if (this.archiveBusy) {
      return;
    }
    this.archiveBusy = true;
    this.archivePanelStatus = 'Submitting...';
    this.renderVersion++;
    const referer = detailArchiveReferer(this.detail, this.detailLink.site);
    this.client.requestArchiverDownload(option, referer, this.detailLink.site).then((result: ArchiverDownloadResult) => {
      this.archiveBusy = false;
      this.archivePanelStatus = result.message;
      if (result.ok && result.downloadUrl.length > 0) {
        this.copyDetailLink(result.downloadUrl, 'Archive');
      }
      this.renderVersion++;
    }).catch((error: Error) => {
      this.archiveBusy = false;
      this.archivePanelStatus = 'Archive failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private submitHathOption(option: ArchiveOption): void {
    if (this.archiveBusy) {
      return;
    }
    this.archiveBusy = true;
    this.archivePanelStatus = 'Submitting...';
    this.renderVersion++;
    this.client.submitHathArchive(this.detail.gid, this.detail.token, this.hathArchiveList.formParamOr, option.value,
      this.detailLink.site).then((result: HathArchiveSubmitResult) => {
      this.archiveBusy = false;
      this.archivePanelStatus = result.message;
      this.detailStatus = result.message;
      this.renderVersion++;
    }).catch((error: Error) => {
      this.archiveBusy = false;
      this.archivePanelStatus = 'H@H failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private openSimilarGalleryList(): void {
    if (!this.detailLoaded || this.detail.gid <= 0) {
      this.detailStatus = 'Similar search needs a loaded gallery';
      this.renderVersion++;
      return;
    }
    const request = createSimilarGallerySearch(this.detail);
    if (request !== null) {
      this.onOpenSearch(request);
    }
  }

  private openCoverSearch(): void {
    const context = getAbilityContext();
    const thumb = this.detail.thumb === undefined ? '' : this.detail.thumb;
    if (context === undefined) {
      this.detailStatus = 'Cover image is unavailable';
      this.renderVersion++;
      return;
    }
    if (this.coverSearchPreviewPageUrl().length === 0 && thumb.length === 0) {
      this.detailStatus = 'Cover image is unavailable';
      this.renderVersion++;
      return;
    }
    this.detailStatus = 'Preparing cover search...';
    this.renderVersion++;
    const referer = this.detailRequestUrl.length > 0 ? this.detailRequestUrl :
      EhUrl.getGalleryDetailUrl(this.detail.gid, this.detail.token, 0, false, this.detailLink.site);
    this.prepareCoverSearchImage(context, referer)
      .then((path: string) => {
        if (path.length === 0) {
          this.detailStatus = 'Cover image cache failed';
          this.renderVersion++;
          return;
        }
        this.onOpenSearch(createCoverSearchRequest(path));
      }).catch((error: Error) => {
        this.detailStatus = 'Cover search failed: ' + error.message;
        this.renderVersion++;
      });
  }

  private coverSearchPreviewPageUrl(): string {
    if (this.detail.previewSet.length === 0) {
      return '';
    }
    let best = this.detail.previewSet[0];
    for (let i = 1; i < this.detail.previewSet.length; i++) {
      if (this.detail.previewSet[i].index < best.index) {
        best = this.detail.previewSet[i];
      }
    }
    return best.pageUrl;
  }

  private async prepareCoverSearchImage(context: common.UIAbilityContext, referer: string): Promise<string> {
    const previewPageUrl = this.coverSearchPreviewPageUrl();
    if (previewPageUrl.length > 0) {
      try {
        const result = await this.client.loadGalleryPageFast(previewPageUrl, this.detailLink.site, referer);
        if (result.ok && result.page !== null && result.page.imageUrl.length > 0) {
          const pageReferer = result.page.pageUrl.length > 0 ? result.page.pageUrl : previewPageUrl;
          const path = await readerImageCache.ensureCached(context, result.page.imageUrl, pageReferer, true, undefined,
            readerPageImageCacheKey(result.page, false), { retryLimit: 3 });
          if (path.length > 0) {
            return path;
          }
        }
      } catch (error) {
      }
    }

    const thumb = this.detail.thumb === undefined ? '' : this.detail.thumb;
    if (thumb.length === 0) {
      return '';
    }
    return readerImageCache.ensureCached(context, thumb, referer, true, undefined, detailCoverCacheKey(this.detail));
  }

  private openTagSearch(namespace: string, tag: string): void {
    const request = createTagSearchRequest(namespace, tag);
    if (request !== null) {
      this.onOpenSearch(request);
    }
  }

  private async loadNextDetailPreviewPage(): Promise<void> {
    const referer = this.detailRequestUrl.length > 0 ? this.detailRequestUrl : this.detailLink.referer;
    await this.detailPreviewPager.loadNext({
      client: this.client,
      site: this.detailLink.site,
      referer: referer,
      getDetail: () => this.detail,
      isVisible: () => this.detail.gid === this.detailLink.gid,
      onMerge: (detail: GalleryDetail) => {
        const merged = mergeGalleryPreviewSets(this.detail, detail, this.previewMap, this.previewPageSize);
        this.detail = merged.detail;
        this.previewPageSize = merged.previewPageSize;
        this.renderVersion++;
      },
      onError: (message: string) => {
        this.detailStatus = 'Preview page load failed: ' + message;
        this.renderVersion++;
      }
    });
  }

  build() {
    GalleryDetailOverlayScene({
      renderVersion: this.renderVersion,
      showComments: this.showComments,
      detail: this.detail,
      isDetailLoaded: this.detailLoaded,
      isFavorited: this.optimisticFavorite || this.detail.isFavorited,
      statusText: this.detailStatus,
      requestUrl: this.detailRequestUrl,
      downloadText: this.detailDownloadText,
      archivePanelVisible: this.archivePanelVisible,
      archivePanelMode: this.archivePanelMode,
      archivePanelStatus: this.archivePanelStatus,
      archiveBusy: this.archiveBusy,
      archiverInfo: this.archiverInfo,
      hathArchiveList: this.hathArchiveList,
      initialDetailScrollOffset: this.initialDetailScrollOffset,
      onBack: this.onBack,
      onCloseComments: () => { this.showComments = false; this.renderVersion++; },
      onDownload: () => { this.toggleDownloadDetail(); },
      onRead: () => { this.readDetail(); },
      onSelectPreview: (preview: GalleryPreview) => {
        const item = findDetailDownloadItem(this.detail.gid);
        if (item !== null) {
          this.openDownloadedReaderAt(item, preview.index);
        } else {
          this.openRemoteReaderAt(preview.index);
        }
      },
      onJumpPreviewPage: (pageIndex: number) => {
        this.jumpPreviewPage(pageIndex);
      },
      onComments: () => { this.openComments(); },
      onFavorite: () => { this.toggleFavoriteDetail(); },
      onShare: () => {
        this.copyDetailLink(EhUrl.getGalleryDetailUrl(this.detail.gid, this.detail.token, 0, false, this.detailLink.site),
          'Gallery URL');
      },
      onRate: (rating: number) => { this.rateDetail(rating); },
      onTorrent: () => { this.copyDetailLink(this.detail.torrentUrl, 'Torrent'); },
      onArchive: () => { this.openArchiverPanel(); },
      onHath: () => { this.openHathPanel(); },
      onSimilar: () => { this.openSimilarGalleryList(); },
      onSearchCover: () => { this.openCoverSearch(); },
      onCloseArchivePanel: () => { this.closeArchivePanel(); },
      onSelectArchiverOption: (option: ArchiverOption) => { this.submitArchiverOption(option); },
      onSelectHathOption: (option: ArchiveOption) => { this.submitHathOption(option); },
      onLoadMorePreviews: () => {
        this.loadNextDetailPreviewPage();
      },
      onDetailScrollUpdate: this.onDetailScrollUpdate,
      onTagSearch: (namespace: string, tag: string) => { this.openTagSearch(namespace, tag); }
    })
  }
}
