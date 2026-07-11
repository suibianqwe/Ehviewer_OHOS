import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { ArchiveOption, ArchiverInfo, ArchiverOption, GalleryComment, GalleryDetail, GalleryPreview, GallerySite, HathArchiveList, TorrentInfo } from '../model/GalleryModels';
import { confirmCellularNetworkWarningForSession, shouldConfirmCellularNetworkOperation } from '../services/EhCellularNetworkGuard';
import { ehDownloadManager } from '../services/EhDownloadManager';
import { DownloadInfo, ehDownloadStore } from '../services/EhDownloadStore';
import { ehDownloadFileStore } from '../services/EhDownloadFileStore';
import { ehLocalFavoritesStore } from '../services/EhLocalFavoritesStore';
import {
  ArchiverDownloadResult,
  ArchiverLoadResult,
  EhHttpClient,
  GalleryDetailLoadResult,
  HathArchiveListLoadResult,
  HathArchiveSubmitResult,
  RateGalleryResult,
  ToggleFavoriteResult,
  TorrentListLoadResult,
  VoteCommentResult,
  VoteTagResult
} from '../services/EhHttpClient';
import { PublicDownloadStartResult, startPublicDownload } from '../services/PublicDownloadService';
import { EhUrl } from '../services/EhUrl';
import {
  archiveUnavailableReason,
  createCategorySearchRequest,
  createCoverSearchRequest,
  createSimilarGallerySearch,
  createTagSearchRequest,
  createUploaderSearchRequest,
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
  createGalleryDetailLinkFromUrl,
  GalleryDetailLink,
  GalleryDetailModuleLoadResult,
  initialDetailForLink,
  loadGalleryDetailModule
} from '../services/GalleryDetailModule';
import { DetailPreviewPager, loadGalleryPreviewPage, mergeGalleryPreviewSets, seedPreviewMap } from '../services/GalleryPreviewLoader';
import { readerImageCache } from '../services/ReaderImageCache';
import { AsyncRequestGate } from '../services/AsyncRequestGate';
import { createReaderSessionState, readerSessionStore } from '../services/ReaderSessionStore';
import { ehSettingsStore } from '../services/EhSettingsStore';
import {
  cloneGalleryDetail,
  cloneGalleryPreviews,
  categoryName,
  createEmptyDetail,
  createEmptyPage,
  getAbilityContext,
  pushDetailBackHandler,
  readerStartIndex,
  readerStartIndexAsync,
  readerPageImageCacheKey,
  saveGalleryToHistory,
  uiText
} from '../shared/EhShared';
import {
  themeDividerColor,
  themeFieldBackground,
  themePrimaryColor,
  themePrimaryText,
  themeScrimColor,
  themeSecondaryText,
  themeShadowColor,
  themeSurface,
  themeSurfaceVariant
} from '../shared/EhTheme';
import { GalleryDetailOverlayScene } from './GalleryDetailScenes';

interface DetailHostNavigationState {
  showInfo: boolean;
  showComments: boolean;
  commentGalleryLink: GalleryDetailLink;
}

const detailHostNavigationCache: Map<string, DetailHostNavigationState> = new Map<string, DetailHostNavigationState>();
const DEFAULT_FAV_SLOT_SETTING_KEY: string = 'default_fav_slot';
const DEFAULT_FAV_SLOT_ASK: string = 'Ask';
const FAVORITE_SLOT_ROW_HEIGHT: number = 52;
const FAVORITE_SLOT_PANEL_CHROME_HEIGHT: number = 112;

interface FavoriteSlotOption {
  slot: number;
  label: string;
}

function favoriteSlotOptions(): FavoriteSlotOption[] {
  const options: FavoriteSlotOption[] = [{ slot: -1, label: 'Local Favorites' }];
  for (let i = 0; i < 10; i++) {
    options.push({ slot: i, label: 'Favorites ' + i.toString() });
  }
  return options;
}

function parseDefaultFavoriteSlot(value: string): number | null {
  if (value === DEFAULT_FAV_SLOT_ASK || value.length === 0) {
    return null;
  }
  const parsed = Number.parseInt(value);
  if (Number.isNaN(parsed) || parsed < -1 || parsed > 9) {
    return null;
  }
  return parsed;
}

@Component
struct AddFavoriteDialog {
  @Prop remember: boolean = false;
  @Prop panelMaxHeight: number = 680;
  onRememberChange: (remember: boolean) => void = (_remember: boolean) => {};
  onSelect: (slot: number) => void = (_slot: number) => {};
  onClose: () => void = () => {};

  private listHeight(): number {
    const contentHeight = favoriteSlotOptions().length * FAVORITE_SLOT_ROW_HEIGHT;
    const availableHeight = Math.max(160, this.panelMaxHeight - FAVORITE_SLOT_PANEL_CHROME_HEIGHT);
    return Math.min(contentHeight, availableHeight);
  }

  private panelHeight(): number {
    return this.listHeight() + FAVORITE_SLOT_PANEL_CHROME_HEIGHT;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(themeScrimColor())
        .onClick(() => {
          this.onClose();
        })

      Column() {
        Row() {
          Text(uiText('Add to favorites'))
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .layoutWeight(1)

          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(20)
              .fontColor([themePrimaryText()])
          }
          .width(40)
          .height(40)
          .backgroundColor(themeFieldBackground())
          .onClick(() => {
            this.onClose();
          })
        }
        .width('100%')
        .height(56)
        .padding({ left: 18, right: 12 })
        .alignItems(VerticalAlign.Center)

        Divider().color(themeDividerColor()).strokeWidth(0.5)

        List() {
          ForEach(favoriteSlotOptions(), (item: FavoriteSlotOption) => {
            ListItem() {
              Row() {
                Column() {
                  SymbolGlyph(item.slot === -1 ? $r('sys.symbol.heart') : $r('sys.symbol.folder'))
                    .fontSize(21)
                    .fontColor([themePrimaryColor()])
                }
                .width(38)
                .height(38)
                .borderRadius(9)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .backgroundColor(themeSurfaceVariant())

                Text(uiText(item.label))
                  .fontSize(15)
                  .fontColor(themePrimaryText())
                  .layoutWeight(1)
                  .margin({ left: 12 })
              }
              .width('100%')
              .height(52)
              .padding({ left: 18, right: 18 })
              .onClick(() => {
                this.onSelect(item.slot);
              })
            }
          }, (item: FavoriteSlotOption) => item.slot.toString())
        }
        .width('100%')
        .height(this.listHeight())

        Divider().color(themeDividerColor()).strokeWidth(0.5)

        Row() {
          Checkbox()
            .select(this.remember)
            .selectedColor(themePrimaryColor())
            .onChange((value: boolean) => {
              this.onRememberChange(value);
            })

          Text(uiText('Remember favorite collection'))
            .fontSize(14)
            .fontColor(themeSecondaryText())
            .margin({ left: 8 })
            .layoutWeight(1)
        }
        .width('100%')
        .height(54)
        .padding({ left: 18, right: 18 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.onRememberChange(!this.remember);
        })
      }
      .width('78%')
      .height(this.panelHeight())
      .constraintSize({ maxWidth: 360, minWidth: 280, maxHeight: this.panelMaxHeight })
      .backgroundColor(themeSurface())
      .borderRadius(10)
      .shadow({ radius: 24, color: themeShadowColor(), offsetX: 0, offsetY: 8 })
    }
    .width('100%')
    .height('100%')
  }
}

function detailHostCacheKey(link: GalleryDetailLink): string {
  return link.site.toString() + '|' + link.gid.toString() + '|' + link.token + '|' + link.url;
}

function cloneDetailHostLink(link: GalleryDetailLink): GalleryDetailLink {
  return {
    gid: link.gid,
    token: link.token,
    url: link.url,
    referer: link.referer,
    site: link.site,
    seed: link.seed
  };
}

function detailPreviewPageSize(detail: GalleryDetail, currentPageSize: number): number {
  if (currentPageSize > 0) {
    return currentPageSize;
  }
  if (detail.previewPages > 1 && detail.pages > 0) {
    return Math.max(1, Math.ceil(detail.pages / detail.previewPages));
  }
  return Math.max(1, detail.previewSet.length);
}

function selectPreviewPage(previews: GalleryPreview[], pageIndex: number, pageSize: number): GalleryPreview[] {
  const start = Math.max(0, pageIndex) * Math.max(1, pageSize);
  const end = start + Math.max(1, pageSize);
  const selected: GalleryPreview[] = [];
  for (let i = 0; i < previews.length; i++) {
    if (previews[i].index >= start && previews[i].index < end) {
      selected.push(previews[i]);
    }
  }
  selected.sort((left: GalleryPreview, right: GalleryPreview) => left.index - right.index);
  return cloneGalleryPreviews(selected);
}

function mergePreviewList(current: GalleryPreview[], loaded: GalleryPreview[]): GalleryPreview[] {
  const byIndex: Map<number, GalleryPreview> = new Map();
  for (let i = 0; i < current.length; i++) {
    byIndex.set(current[i].index, current[i]);
  }
  for (let i = 0; i < loaded.length; i++) {
    byIndex.set(loaded[i].index, loaded[i]);
  }
  const merged = Array.from(byIndex.values());
  merged.sort((left: GalleryPreview, right: GalleryPreview) => left.index - right.index);
  return cloneGalleryPreviews(merged);
}

@Component
export struct GalleryDetailHostScene {
  @Prop @Watch('onDetailLinkChanged') detailLink: GalleryDetailLink = createEmptyGalleryDetailLink();
  listRequestUrl: string = '';
  initialDetailScrollOffset: number = 0;
  onBack: () => void = () => {};
  onShowEmbeddedReader: () => void = () => {};
  onOpenSearch: (request: DetailSearchRequest) => void = (_request: DetailSearchRequest) => {};
  onDetailLoaded: (detail: GalleryDetail) => void = (_detail: GalleryDetail) => {};
  onDetailScrollUpdate: (offset: number) => void = (_offset: number) => {};

  private client: EhHttpClient = new EhHttpClient();
  private detailRequestGate: AsyncRequestGate = new AsyncRequestGate();
  private detailPreviewPager: DetailPreviewPager = new DetailPreviewPager();
  private previewMap: Map<number, GalleryPreview> = new Map();
  private previewPageSize: number = 0;
  private previewJumpSerial: number = 0;
  private previewJumpLoading: boolean = false;
  private unsubscribeDownloadStore: () => void = () => {};
  private unregisterDetailBackHandler: () => void = () => {};
  private cellularWarningDialogOpen: boolean = false;
  @State renderVersion: number = 0;
  @State showInfo: boolean = false;
  @State showComments: boolean = false;
  @State detail: GalleryDetail = createEmptyDetail();
  @State visiblePreviews: GalleryPreview[] = [];
  @State detailLoaded: boolean = false;
  @State detailStatus: string = '';
  @State detailRequestUrl: string = '';
  @State detailDownloadText: string = 'Download';
  @State optimisticFavorite: boolean = false;
  @State favoriteBusy: boolean = false;
  @State addFavoriteDialogVisible: boolean = false;
  @State rememberFavoriteSlot: boolean = false;
  @State archivePanelVisible: boolean = false;
  @State archivePanelMode: string = '';
  @State archivePanelStatus: string = '';
  @State archiveBusy: boolean = false;
  @State archiverInfo: ArchiverInfo = { funds: '', options: [] };
  @State hathArchiveList: HathArchiveList = { formParamOr: '', options: [] };
  @State torrentList: TorrentInfo[] = [];
  @State commentGalleryLink: GalleryDetailLink = createEmptyGalleryDetailLink();
  @State viewportHeight: number = 0;

  aboutToAppear(): void {
    this.loadDetailFromLink();
    this.unregisterDetailBackHandler = pushDetailBackHandler(() => this.handleDetailSystemBack());
    this.unsubscribeDownloadStore = ehDownloadStore.subscribe((_items: DownloadInfo[]) => {
      this.refreshDetailDownloadText();
    });
  }

  aboutToDisappear(): void {
    this.saveNavigationState();
    this.unsubscribeDownloadStore();
    this.unregisterDetailBackHandler();
  }

  onPageHide(): void {
    this.saveNavigationState();
  }

  onDetailLinkChanged(): void {
    if (this.detailLink.gid <= 0 || this.detailLink.token.length === 0) {
      return;
    }
    if (this.detail.gid === this.detailLink.gid && this.detail.token === this.detailLink.token) {
      return;
    }
    this.loadDetailFromLink();
  }

  private handleDetailSystemBack(): boolean {
    if (this.commentGalleryLink.gid > 0) {
      this.commentGalleryLink = createEmptyGalleryDetailLink();
      this.saveNavigationState();
      this.renderVersion++;
      return true;
    }
    if (this.showInfo) {
      this.showInfo = false;
      this.saveNavigationState();
      this.renderVersion++;
      return true;
    }
    if (this.showComments) {
      this.showComments = false;
      this.saveNavigationState();
      this.renderVersion++;
      return true;
    }
    return false;
  }

  private saveNavigationState(): void {
    if (this.detailLink.gid <= 0 || this.detailLink.token.length === 0) {
      return;
    }
    detailHostNavigationCache.set(detailHostCacheKey(this.detailLink), {
      showInfo: this.showInfo,
      showComments: this.showComments,
      commentGalleryLink: cloneDetailHostLink(this.commentGalleryLink)
    });
  }

  private restoreNavigationState(): DetailHostNavigationState {
    const saved = detailHostNavigationCache.get(detailHostCacheKey(this.detailLink));
    if (saved === undefined) {
      return {
        showInfo: false,
        showComments: false,
        commentGalleryLink: createEmptyGalleryDetailLink()
      };
    }
    return {
      showInfo: saved.showInfo === true,
      showComments: saved.showComments,
      commentGalleryLink: cloneDetailHostLink(saved.commentGalleryLink)
    };
  }

  private loadDetailFromLink(done?: () => void): void {
    if (this.detailLink.gid <= 0 || this.detailLink.token.length === 0) {
      this.detail = createEmptyDetail();
      this.detailStatus = 'No gallery loaded';
      this.detailLoaded = false;
      this.renderVersion++;
      if (done !== undefined) {
        done();
      }
      return;
    }
    const requestGeneration = this.detailRequestGate.begin();
    const navigationState = this.restoreNavigationState();
    this.closeArchivePanel();
    this.detailPreviewPager.start();
    this.previewMap.clear();
    this.previewPageSize = 0;
    this.previewJumpSerial++;
    this.previewJumpLoading = false;
    this.visiblePreviews = [];
    this.showInfo = navigationState.showInfo;
    this.showComments = navigationState.showComments;
    this.commentGalleryLink = navigationState.commentGalleryLink;
    this.detail = initialDetailForLink(this.detailLink);
    this.detailRequestUrl = this.detailLink.url;
    this.detailStatus = 'Loading detail for gid ' + this.detailLink.gid.toString() + '...';
    this.detailDownloadText = detailDownloadButtonText(this.detailLink.gid);
    this.detailLoaded = false;
    this.optimisticFavorite = this.detail.favoriteSlot >= 0;
    this.syncLocalFavoriteState();
    this.favoriteBusy = false;
    const requestGid = this.detailLink.gid;
    this.renderVersion++;
    loadGalleryDetailModule(this.client, this.detailLink).then((result: GalleryDetailModuleLoadResult) => {
      if (!this.detailRequestGate.isCurrent(requestGeneration) || this.detailLink.gid !== requestGid ||
        this.detail.gid !== requestGid) {
        if (done !== undefined) {
          done();
        }
        return;
      }
      if (!result.ok) {
        this.detailRequestUrl = result.url;
        this.detailStatus = result.statusText;
        this.renderVersion++;
        if (done !== undefined) {
          done();
        }
        return;
      }
      this.detail = result.detail;
      this.visiblePreviews = cloneGalleryPreviews(this.detail.previewSet);
      this.detailRequestUrl = result.url;
      this.detailStatus = result.statusText;
      this.detailLoaded = true;
      this.previewPageSize = seedPreviewMap(this.previewMap, this.detail.previewSet, this.previewPageSize);
      this.optimisticFavorite = this.detail.isFavorited;
      this.syncLocalFavoriteState();
      refreshDetailDownloadItem(this.detail);
      this.detailDownloadText = detailDownloadButtonText(this.detail.gid);
      saveGalleryToHistory(this.detail);
      this.onDetailLoaded(this.detail);
      this.renderVersion++;
      if (done !== undefined) {
        done();
      }
    }).catch((error: Error) => {
      if (this.detailRequestGate.isCurrent(requestGeneration) && this.detailLink.gid === requestGid &&
        this.detail.gid === requestGid) {
        this.detailStatus = 'Detail load failed: ' + error.message;
        this.renderVersion++;
      }
      if (done !== undefined) {
        done();
      }
    });
  }

  private refreshCurrentDetail(done: () => void): void {
    this.detailStatus = 'Refreshing detail...';
    this.renderVersion++;
    this.loadDetailFromLink(done);
  }

  private refreshDetailDownloadText(): void {
    if (this.detail.gid <= 0) {
      return;
    }
    this.detailDownloadText = detailDownloadButtonText(this.detail.gid);
    this.renderVersion++;
  }

  private displayDetail(): GalleryDetail {
    const detail = cloneGalleryDetail(this.detail);
    detail.previewSet = cloneGalleryPreviews(this.visiblePreviews);
    return detail;
  }

  private openComments(): void {
    if (!this.detailLoaded || this.detail.comments.length === 0) {
      return;
    }
    this.showInfo = false;
    this.showComments = true;
    this.saveNavigationState();
    this.renderVersion++;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: uiText(message) });
    } catch (error) {
    }
  }

  private openCommentGalleryLink(url: string): void {
    const site = url.indexOf('exhentai.org') >= 0 ? GallerySite.Ex :
      (url.indexOf('e-hentai.org') >= 0 ? GallerySite.E : this.detailLink.site);
    const link = createGalleryDetailLinkFromUrl(url, site, this.detailRequestUrl.length > 0 ?
      this.detailRequestUrl : this.detailLink.url);
    if (link === null) {
      return;
    }
    this.commentGalleryLink = link;
    this.saveNavigationState();
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
    const total = this.detail.previewPages;
    if (total <= 0) {
      this.detailStatus = 'Preview pages are unavailable';
      this.renderVersion++;
      return;
    }
    const target = Math.max(0, Math.min(pageIndex, total - 1));
    const activeJumpSerial = ++this.previewJumpSerial;
    const pageSize = detailPreviewPageSize(this.detail, this.previewPageSize);
    this.previewPageSize = pageSize;
    this.detailPreviewPager.setNextPageIndex(target + 1);
    this.visiblePreviews = selectPreviewPage(this.detail.previewSet, target, pageSize);
    this.previewJumpLoading = target > 0;
    if (target === 0) {
      this.previewJumpLoading = false;
      this.detailStatus = 'Preview page ' + (target + 1).toString() + '/' + total.toString() + ' loaded';
      this.renderVersion++;
      return;
    }
    this.detailStatus = 'Loading preview page ' + (target + 1).toString() + '/' + total.toString() + '...';
    this.renderVersion++;
    const referer = this.detailRequestUrl.length > 0 ? this.detailRequestUrl : this.detailLink.referer;
    loadGalleryPreviewPage({
      client: this.client,
      site: this.detailLink.site,
      referer: referer,
      pageIndex: target,
      getDetail: () => this.detail,
      isCurrent: () => activeJumpSerial === this.previewJumpSerial && this.detail.gid === this.detailLink.gid,
      onMerge: (detail: GalleryDetail) => {
        const merged = mergeGalleryPreviewSets(this.detail, detail, this.previewMap, this.previewPageSize);
        this.detail = merged.detail;
        this.previewPageSize = merged.previewPageSize;
        this.visiblePreviews = cloneGalleryPreviews(detail.previewSet);
        this.previewJumpLoading = false;
        this.detailStatus = 'Preview page ' + (target + 1).toString() + '/' + total.toString() + ' loaded';
        this.onDetailLoaded(this.detail);
        this.renderVersion++;
      },
      onError: (message: string) => {
        if (activeJumpSerial !== this.previewJumpSerial) {
          return;
        }
        this.previewJumpLoading = false;
        this.detailStatus = 'Preview page load failed: ' + message;
        this.renderVersion++;
      }
    }).then((loaded: boolean) => {
      if (activeJumpSerial !== this.previewJumpSerial) {
        return;
      }
      this.previewJumpLoading = false;
      if (!loaded && this.detailStatus.indexOf('Preview page load failed') !== 0) {
        this.detailStatus = 'Preview page ' + (target + 1).toString() + '/' + total.toString() + ' unavailable';
        this.renderVersion++;
      }
    }).catch((error: Error) => {
      if (activeJumpSerial !== this.previewJumpSerial) {
        return;
      }
      this.previewJumpLoading = false;
      this.detailStatus = 'Preview page load failed: ' + error.message;
      this.renderVersion++;
    });
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
    if (!wasFavorited) {
      this.showAddFavoriteDialog();
      return;
    }
    if (this.detail.favoriteSlot === -1) {
      this.favoriteBusy = true;
      this.detailStatus = 'Removing from local favorites...';
      this.optimisticFavorite = false;
      this.applyDetailFavoriteState(false, -2);
      this.renderVersion++;
      this.removeLocalFavoriteIfNeeded();
      this.detailStatus = 'Removed from local favorites';
      this.favoriteBusy = false;
      this.renderVersion++;
      return;
    }
    this.detailStatus = 'Removing from favorites...';
    this.favoriteBusy = true;
    this.optimisticFavorite = false;
    this.applyDetailFavoriteState(false, -2);
    this.renderVersion++;
    this.removeLocalFavoriteIfNeeded();
    this.client.toggleFavorite(this.detail.gid, this.detail.token, wasFavorited, this.detailLink.site)
      .then((result: ToggleFavoriteResult) => {
        this.detailStatus = result.message;
        this.optimisticFavorite = result.ok ? result.nowFavorited : wasFavorited;
        this.applyDetailFavoriteState(this.optimisticFavorite, this.optimisticFavorite ? 0 : -2);
        this.favoriteBusy = false;
        this.renderVersion++;
      }).catch((error: Error) => {
        this.detailStatus = 'Favorite failed: ' + error.message;
        this.optimisticFavorite = wasFavorited;
        this.applyDetailFavoriteState(wasFavorited, wasFavorited ? Math.max(0, this.detail.favoriteSlot) : -2);
        this.favoriteBusy = false;
        this.renderVersion++;
      });
  }

  private showAddFavoriteDialog(): void {
    const defaultSlot = parseDefaultFavoriteSlot(ehSettingsStore.getValue(DEFAULT_FAV_SLOT_SETTING_KEY,
      DEFAULT_FAV_SLOT_ASK));
    if (defaultSlot !== null) {
      this.addFavoriteToSlot(defaultSlot);
      return;
    }
    this.rememberFavoriteSlot = false;
    this.addFavoriteDialogVisible = true;
    this.renderVersion++;
  }

  private addFavoriteDialogMaxHeight(): number {
    if (this.viewportHeight <= 0) {
      return 620;
    }
    return Math.max(280, this.viewportHeight - 96);
  }

  private selectFavoriteSlot(slot: number): void {
    this.addFavoriteDialogVisible = false;
    if (this.rememberFavoriteSlot) {
      ehSettingsStore.setValue(DEFAULT_FAV_SLOT_SETTING_KEY, slot.toString());
    } else {
      ehSettingsStore.setValue(DEFAULT_FAV_SLOT_SETTING_KEY, DEFAULT_FAV_SLOT_ASK);
    }
    this.addFavoriteToSlot(slot);
  }

  private addFavoriteToSlot(slot: number): void {
    if (slot === -1) {
      this.addLocalFavorite();
    } else {
      this.addCloudFavorite(Math.max(0, Math.min(9, slot)));
    }
  }

  private addLocalFavorite(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.detailStatus = 'Local favorites unavailable';
      this.renderVersion++;
      return;
    }
    this.favoriteBusy = true;
    this.detailStatus = 'Adding to local favorites...';
    this.renderVersion++;
    ehLocalFavoritesStore.ensureLoaded(context).then(() => {
      ehLocalFavoritesStore.addGallery(this.detail);
      this.optimisticFavorite = true;
      this.applyDetailFavoriteState(true, -1);
      this.detailStatus = 'Added to local favorites';
      this.favoriteBusy = false;
      this.renderVersion++;
    }).catch((error: Error) => {
      this.detailStatus = 'Favorite failed: ' + error.message;
      this.favoriteBusy = false;
      this.renderVersion++;
    });
  }

  private addCloudFavorite(slot: number): void {
    this.detailStatus = 'Adding to favorites...';
    this.favoriteBusy = true;
    this.optimisticFavorite = true;
    this.applyDetailFavoriteState(true, slot);
    this.renderVersion++;
    this.client.toggleFavorite(this.detail.gid, this.detail.token, false, this.detailLink.site, slot)
      .then((result: ToggleFavoriteResult) => {
        this.detailStatus = result.message;
        this.optimisticFavorite = result.ok ? result.nowFavorited : false;
        this.applyDetailFavoriteState(this.optimisticFavorite, this.optimisticFavorite ? slot : -2);
        this.favoriteBusy = false;
        this.renderVersion++;
      }).catch((error: Error) => {
        this.detailStatus = 'Favorite failed: ' + error.message;
        this.optimisticFavorite = false;
        this.applyDetailFavoriteState(false, -2);
        this.favoriteBusy = false;
        this.renderVersion++;
      });
  }

  private removeLocalFavoriteIfNeeded(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehLocalFavoritesStore.ensureLoaded(context).then(() => {
      ehLocalFavoritesStore.removeGallery(this.detail.gid);
    }).catch(() => {});
  }

  private syncLocalFavoriteState(): void {
    const context = getAbilityContext();
    if (context === undefined || this.detail.gid <= 0) {
      return;
    }
    const targetGid = this.detail.gid;
    ehLocalFavoritesStore.ensureLoaded(context).then(() => {
      if (this.detail.gid !== targetGid || !ehLocalFavoritesStore.contains(targetGid)) {
        return;
      }
      this.applyDetailFavoriteState(true, -1);
      this.optimisticFavorite = true;
      this.renderVersion++;
    }).catch(() => {});
  }

  private applyDetailFavoriteState(isFavorited: boolean, favoriteSlot: number): void {
    const nextDetail = cloneGalleryDetail(this.detail);
    nextDetail.isFavorited = isFavorited;
    nextDetail.favoriteSlot = isFavorited ? favoriteSlot : -2;
    nextDetail.favoriteName = favoriteSlot === -1 ? undefined : nextDetail.favoriteName;
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

  private shareGallery(): void {
    const context = getAbilityContext();
    if (context === undefined || !this.detailLoaded) {
      return;
    }
    const url = EhUrl.getGalleryDetailUrl(this.detail.gid, this.detail.token, 0, false, this.detailLink.site);
    const shareData = new systemShare.SharedData({
      utd: utd.UniformDataType.PLAIN_TEXT,
      content: url,
      title: this.detail.title,
      description: 'EhViewer'
    });
    const controller = new systemShare.ShareController(shareData);
    controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DETAIL
    }).catch(() => {});
  }

  private openTorrentPanel(): void {
    if (!this.detailLoaded || this.detail.torrentUrl.length === 0) {
      this.detailStatus = 'Torrent URL is unavailable';
      this.renderVersion++;
      return;
    }
    this.archivePanelVisible = true;
    this.archivePanelMode = 'torrent';
    this.archivePanelStatus = 'Loading...';
    this.archiveBusy = true;
    this.torrentList = [];
    this.renderVersion++;
    this.client.loadTorrentList(this.detail.torrentUrl, this.detail.gid, this.detail.token, this.detailLink.site)
      .then((result: TorrentListLoadResult) => {
        this.archiveBusy = false;
        this.archivePanelStatus = result.ok ? '' : result.message;
        this.torrentList = result.torrents;
        this.renderVersion++;
      }).catch((error: Error) => {
        this.archiveBusy = false;
        this.archivePanelStatus = 'Torrent failed: ' + error.message;
        this.renderVersion++;
      });
  }

  private copyTorrentMagnet(torrent: TorrentInfo): void {
    if (torrent.magnetUrl.length === 0) {
      this.showToast('Magnet link unavailable');
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, torrent.magnetUrl);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.closeArchivePanel();
        this.detailStatus = 'Magnet link copied';
        this.showToast('Magnet link copied');
        this.renderVersion++;
      }).catch(() => {
        this.showToast('Copy failed');
      });
    } catch (error) {
      this.showToast('Copy failed');
    }
  }

  private closeArchivePanel(): void {
    this.archivePanelVisible = false;
    this.archivePanelMode = '';
    this.archivePanelStatus = '';
    this.archiveBusy = false;
    this.archiverInfo = { funds: '', options: [] };
    this.hathArchiveList = { formParamOr: '', options: [] };
    this.torrentList = [];
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
        this.archivePanelStatus = result.ok ? '' : 'Archive failed: ' + result.message;
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
      this.archivePanelStatus = result.message;
      if (result.ok && result.downloadUrl.length > 0) {
        this.startArchiveDownload(result.downloadUrl).then(() => {
          this.archiveBusy = false;
          this.closeArchivePanel();
          this.detailStatus = 'Archive download started';
          this.showToast('Archive download started');
          this.renderVersion++;
        }).catch((error: Error) => {
          this.archiveBusy = false;
          this.archivePanelStatus = 'Archive failed: ' + error.message;
          this.showToast('Archive download failed');
          this.renderVersion++;
        });
        return;
      }
      this.archiveBusy = false;
      this.renderVersion++;
    }).catch((error: Error) => {
      this.archiveBusy = false;
      this.archivePanelStatus = 'Archive failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private async startArchiveDownload(url: string): Promise<PublicDownloadStartResult> {
    const context = getAbilityContext();
    if (context === undefined) {
      throw new Error('App context is unavailable');
    }
    const directory = await this.ensurePublicDownloadDirectory(context);
    const title = this.detail.title.length > 0 ? this.detail.title : this.detail.gid.toString();
    const fileName = title + ' (' + this.detail.gid.toString() + ').zip';
    return startPublicDownload(context, url, detailArchiveReferer(this.detail, this.detailLink.site), directory,
      fileName, title);
  }

  private async ensurePublicDownloadDirectory(context: common.UIAbilityContext): Promise<string> {
    try {
      return ehDownloadFileStore.publicDownloadRoot(context);
    } catch (error) {
    }
    const saveOptions = new picker.DocumentSaveOptions();
    saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
    const documentPicker = new picker.DocumentViewPicker(context);
    const result = await documentPicker.save(saveOptions);
    if (result.length === 0 || result[0].length === 0) {
      throw new Error('Downloads access was not granted');
    }
    const directory = new fileUri.FileUri(result[0]).path + '/EhViewer';
    ehDownloadFileStore.rememberPublicDownloadRoot(directory);
    await ehSettingsStore.save(context);
    return directory;
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
      if (result.ok) {
        this.closeArchivePanel();
        this.showToast('H@H download request submitted');
      } else {
        this.showToast(result.message);
      }
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

  private openUploaderGalleryList(): void {
    const uploader = this.detail.uploader === undefined ? '' : this.detail.uploader;
    const request = createUploaderSearchRequest(uploader);
    if (request !== null) {
      this.onOpenSearch(request);
    }
  }

  private openCategoryGalleryList(): void {
    const request = createCategorySearchRequest(this.detail.category, categoryName(this.detail.category));
    this.onOpenSearch(request);
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

  private voteDetailTag(fullTag: string, vote: number): void {
    if (!this.detailLoaded || this.detail.apiUid < 0 || this.detail.apiKey.length === 0) {
      this.detailStatus = 'Tag vote requires gallery API key';
      this.showToast(this.detailStatus);
      this.renderVersion++;
      return;
    }
    this.detailStatus = vote > 0 ? 'Submitting tag vote up...' : 'Submitting tag vote down...';
    this.renderVersion++;
    this.client.voteGalleryTag(this.detail.gid, this.detail.token, this.detail.apiUid, this.detail.apiKey, fullTag, vote,
      this.detailLink.site).then((result: VoteTagResult) => {
      if (!result.ok) {
        this.detailStatus = 'Tag vote failed: ' + result.message;
        this.showToast(this.detailStatus);
        this.renderVersion++;
        return;
      }
      this.detailStatus = result.message;
      this.showToast('Tag vote submitted');
      this.reloadCurrentDetailAfterTagChange();
    }).catch((error: Error) => {
      this.detailStatus = 'Tag vote failed: ' + error.message;
      this.showToast(this.detailStatus);
      this.renderVersion++;
    });
  }

  private addDetailTag(fullTag: string): void {
    this.voteDetailTag(fullTag, 1);
  }

  private reloadCurrentDetailAfterTagChange(): void {
    const requestGid = this.detail.gid;
    const referer = this.detailRequestUrl.length > 0 ? this.detailRequestUrl : this.detailLink.referer;
    this.client.loadGalleryDetail(this.detail.gid, this.detail.token, 0, this.detailLink.site, referer)
      .then((result: GalleryDetailLoadResult) => {
        if (this.detail.gid !== requestGid || result.detail === null) {
          this.renderVersion++;
          return;
        }
        if (!result.ok) {
          this.detailStatus = 'Tag refresh failed: ' + result.message;
          this.renderVersion++;
          return;
        }
        const next = cloneGalleryDetail(result.detail);
        next.previewSet = cloneGalleryPreviews(this.detail.previewSet);
        next.previewPages = Math.max(next.previewPages, this.detail.previewPages);
        this.detail = next;
        this.onDetailLoaded(this.detail);
        this.renderVersion++;
      }).catch((error: Error) => {
        this.detailStatus = 'Tag refresh failed: ' + error.message;
        this.renderVersion++;
      });
  }

  private openTagDefinition(fullTag: string): void {
    const name = fullTag.replace(/^[a-z]+:\s*/i, '').trim();
    if (name.length === 0) {
      return;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      this.detailStatus = 'Tag definition unavailable';
      this.renderVersion++;
      return;
    }
    context.startAbility({
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: 'https://ehwiki.org/wiki/' + encodeURIComponent(name).replace(/%20/g, '_'),
      parameters: {
        'ohos.ability.params.showDefaultPicker': true
      }
    }).catch((error: Error) => {
      this.detailStatus = 'Tag definition failed: ' + error.message;
      this.renderVersion++;
    });
  }

  private async loadNextDetailPreviewPage(): Promise<void> {
    if (this.previewJumpLoading) {
      return;
    }
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
        this.visiblePreviews = mergePreviewList(this.visiblePreviews, detail.previewSet);
        this.renderVersion++;
      },
      onError: (message: string) => {
        this.detailStatus = 'Preview page load failed: ' + message;
        this.renderVersion++;
      }
    });
  }

  private voteDetailComment(comment: GalleryComment, vote: number): void {
    if (!this.detailLoaded || this.detail.apiUid < 0 || this.detail.apiKey.length === 0) {
      this.detailStatus = 'Comment vote requires gallery API key';
      this.renderVersion++;
      return;
    }
    this.client.voteComment(this.detail.gid, this.detail.token, this.detail.apiUid, this.detail.apiKey, comment.id,
      vote, this.detailLink.site).then((result: VoteCommentResult) => {
      if (!result.ok) {
        this.detailStatus = 'Comment vote failed: ' + result.message;
        this.showToast(this.detailStatus);
        this.renderVersion++;
        return;
      }
      this.applyCommentVoteResult(result);
    }).catch((error: Error) => {
      this.detailStatus = 'Comment vote failed: ' + error.message;
      this.showToast(this.detailStatus);
      this.renderVersion++;
    });
  }

  private applyCommentVoteResult(result: VoteCommentResult): void {
    const targetId = result.commentId.length > 0 ? result.commentId : '';
    const next = cloneGalleryDetail(this.detail);
    let changed = false;
    for (let i = 0; i < next.comments.length; i++) {
      if (next.comments[i].id !== targetId) {
        continue;
      }
      next.comments[i].score = result.score;
      if (result.expectedVote > 0) {
        next.comments[i].voteUpEd = result.vote !== 0;
        next.comments[i].voteDownEd = false;
      } else {
        next.comments[i].voteDownEd = result.vote !== 0;
        next.comments[i].voteUpEd = false;
      }
      changed = true;
      break;
    }
    if (!changed) {
      this.detailStatus = 'Comment vote submitted';
      this.showToast(this.detailStatus);
      this.renderVersion++;
      return;
    }
    this.detail = next;
    this.detailStatus = 'Comment vote submitted';
    this.showToast(this.detailStatus);
    this.onDetailLoaded(this.detail);
    this.renderVersion++;
  }

  build() {
    Stack() {
      GalleryDetailOverlayScene({
        renderVersion: this.renderVersion,
        showInfo: this.showInfo,
        showComments: this.showComments,
        detail: this.displayDetail(),
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
        torrentList: this.torrentList,
        initialDetailScrollOffset: this.initialDetailScrollOffset,
        onBack: this.onBack,
        onShowInfo: () => {
          this.showInfo = true;
          this.showComments = false;
          this.saveNavigationState();
          this.renderVersion++;
        },
        onCloseInfo: () => {
          this.showInfo = false;
          this.saveNavigationState();
          this.renderVersion++;
        },
        onCloseComments: () => {
          this.commentGalleryLink = createEmptyGalleryDetailLink();
          this.showComments = false;
          this.saveNavigationState();
          this.renderVersion++;
        },
        onDownload: () => { this.toggleDownloadDetail(); },
        onRead: () => { this.readDetail(); },
        onUploaderSearch: () => { this.openUploaderGalleryList(); },
        onCategorySearch: () => { this.openCategoryGalleryList(); },
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
        onVoteComment: (comment: GalleryComment, vote: number) => { this.voteDetailComment(comment, vote); },
        onOpenCommentGalleryLink: (url: string) => { this.openCommentGalleryLink(url); },
        onFavorite: () => { this.toggleFavoriteDetail(); },
        onShare: () => { this.shareGallery(); },
        onRate: (rating: number) => { this.rateDetail(rating); },
        onTorrent: () => { this.openTorrentPanel(); },
        onArchive: () => { this.openArchiverPanel(); },
        onHath: () => { this.openHathPanel(); },
        onSimilar: () => { this.openSimilarGalleryList(); },
        onSearchCover: () => { this.openCoverSearch(); },
        onCloseArchivePanel: () => { this.closeArchivePanel(); },
        onSelectArchiverOption: (option: ArchiverOption) => { this.submitArchiverOption(option); },
        onSelectHathOption: (option: ArchiveOption) => { this.submitHathOption(option); },
        onSelectTorrent: (torrent: TorrentInfo) => { this.copyTorrentMagnet(torrent); },
        onLoadMorePreviews: () => {
          this.loadNextDetailPreviewPage();
        },
        onRefreshDetail: (done: () => void) => {
          this.refreshCurrentDetail(done);
        },
        onDetailScrollUpdate: this.onDetailScrollUpdate,
        onTagSearch: (namespace: string, tag: string) => { this.openTagSearch(namespace, tag); },
        onVoteTag: (fullTag: string, vote: number) => { this.voteDetailTag(fullTag, vote); },
        onAddTag: (fullTag: string) => { this.addDetailTag(fullTag); },
        onShowTagDefinition: (fullTag: string) => { this.openTagDefinition(fullTag); }
      })

      if (this.commentGalleryLink.gid > 0) {
        GalleryDetailHostScene({
          detailLink: this.commentGalleryLink,
          listRequestUrl: this.detailRequestUrl,
          onBack: () => {
            this.commentGalleryLink = createEmptyGalleryDetailLink();
            this.saveNavigationState();
            this.renderVersion++;
          },
          onShowEmbeddedReader: this.onShowEmbeddedReader,
          onOpenSearch: this.onOpenSearch
        })
        .transition(TransitionEffect.move(TransitionEdge.END).animation({ duration: 220, curve: Curve.EaseOut }))
        .zIndex(20)
      }

      if (this.addFavoriteDialogVisible) {
        AddFavoriteDialog({
          remember: this.rememberFavoriteSlot,
          panelMaxHeight: this.addFavoriteDialogMaxHeight(),
          onRememberChange: (remember: boolean) => {
            this.rememberFavoriteSlot = remember;
            this.renderVersion++;
          },
          onSelect: (slot: number) => {
            this.selectFavoriteSlot(slot);
          },
          onClose: () => {
            this.addFavoriteDialogVisible = false;
            this.renderVersion++;
          }
        })
          .zIndex(40)
          .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const h = newArea.height as number;
      if (h > 0 && !Number.isNaN(h)) {
        this.viewportHeight = h;
      }
    })
  }
}
