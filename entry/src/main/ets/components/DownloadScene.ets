import { common } from '@kit.AbilityKit';
import { GalleryDetail, GalleryPage, GalleryPreview, GallerySite } from '../model/GalleryModels';
import { ehDownloadFileStore, RestoredDownloadGallery } from '../services/EhDownloadFileStore';
import { DownloadInfo, DownloadState, ehDownloadStore } from '../services/EhDownloadStore';
import { EhHttpClient } from '../services/EhHttpClient';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { EhUrl } from '../services/EhUrl';
import { galleryPageCache } from '../services/GalleryPageCache';
import { readerImageCache } from '../services/ReaderImageCache';
import { createReaderSessionState, readerSessionStore } from '../services/ReaderSessionStore';
import { applyAppChromeImmersiveMode, enterEmbeddedReaderFullscreen } from '../services/EhWindowImmersive';
import { LANGUAGE_REVISION_KEY, STATUS_BAR_HEIGHT_KEY } from '../shared/EhShared';
import {
  cloneGalleryPage,
  createDetailFromGallery,
  createEmptyDetail,
  createEmptyPage,
  currentGallerySite,
  downloadImageUrlForPage,
  downloadPageIndexes,
  downloadSizeText,
  downloadThreadLimit,
  filterDownloadItems,
  getAbilityContext,
  nextDownloadCategoryFilter,
  nextDownloadSortMode,
  nextDownloadStatusFilter,
  readerPageReferer,
  saveGalleryReadPosition,
  uiStatusText,
  uiText,
  uiValue
} from '../shared/EhShared';
import { themePageBackground, themePrimaryColor, themePrimaryText, themeSecondaryText, themeSurface } from '../shared/EhTheme';
import { EhNavBar } from './NavigationComponents';
import { ReaderPageState, ReaderScene } from './ReaderScenes';
import { DownloadRow } from './DownloadRow';

@Component
export struct DownloadScene {
  private client: EhHttpClient = new EhHttpClient();
  private shouldStop: boolean = false;
  private stoppedGids: number[] = [];
  private unsubscribeStore: () => void = () => {};
  onMenu: () => void = () => {};

  @State items: DownloadInfo[] = [];
  @State query: string = '';
  @State statusFilter: string = 'All';
  @State sortMode: string = 'Default';
  @State categoryFilter: string = 'All';
  @State statusText: string = 'Downloads: idle';
  @State isProcessing: boolean = false;
  @State showReader: boolean = false;
  @State localReaderDetail: GalleryDetail = createEmptyDetail();
  @State localReaderPage: GalleryPage = createEmptyPage();
  @State localReaderPages: ReaderPageState[] = [];
  @State localReaderIndex: number = 0;
  @State localReaderStatus: string = 'Page loaded from downloads';
  @State localReaderRenderVersion: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    this.unsubscribeStore = ehDownloadStore.subscribe((items: DownloadInfo[]) => {
      this.items = items;
    });
    this.loadDownloads();
  }

  aboutToDisappear(): void {
    this.unsubscribeStore();
  }

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  private loadDownloads(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.items = ehDownloadStore.getItems();
      return;
    }

    ehDownloadStore.load(context).then(() => {
      this.statusText = this.items.length.toString() + ' download items';
    }).catch((error: Error) => {
      this.statusText = 'Download load failed: ' + error.message;
      this.items = ehDownloadStore.getItems();
    });
  }

  private persistDownloads(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehDownloadStore.save(context).catch((error: Error) => {
      this.statusText = 'Download save failed: ' + error.message;
    });
  }

  private visibleDownloadItems(): DownloadInfo[] {
    return filterDownloadItems(this.items, this.query, this.statusFilter, 'All', this.sortMode, this.categoryFilter);
  }

  private activeSummary(): string {
    let wait = 0;
    let active = 0;
    let done = 0;
    let failed = 0;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].state === DownloadState.Wait) {
        wait++;
      } else if (this.items[i].state === DownloadState.Downloading) {
        active++;
      } else if (this.items[i].state === DownloadState.Finish) {
        done++;
      } else if (this.items[i].state === DownloadState.Failed) {
        failed++;
      }
    }
    return wait.toString() + ' waiting  ' + active.toString() + ' active  ' + done.toString() + ' done  ' +
      failed.toString() + ' failed';
  }

  private startAll(): void {
    this.shouldStop = false;
    this.stoppedGids = [];
    ehDownloadStore.startAll();
    this.statusText = 'Queued idle and failed downloads';
    this.persistDownloads();
    this.runDownloadQueue();
  }

  private stopAll(): void {
    this.shouldStop = true;
    this.stoppedGids = [];
    ehDownloadStore.stopAll();
    this.statusText = 'Stopped waiting downloads';
    this.persistDownloads();
  }

  private clearFinished(): void {
    ehDownloadStore.clearFinished();
    this.statusText = 'Cleared finished downloads';
    this.persistDownloads();
  }

  private restoreDownloadedItems(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Restore needs app context';
      return;
    }
    const restored: RestoredDownloadGallery[] = ehDownloadFileStore.restoreDownloadedGalleries(context);
    let added = 0;
    for (let i = 0; i < restored.length; i++) {
      if (!ehDownloadStore.contains(restored[i].gallery.gid)) {
        const item = ehDownloadStore.addGallery(restored[i].gallery, '');
        if (item !== null) {
          ehDownloadStore.setState(item.gid, restored[i].finished >= restored[i].total && restored[i].total > 0 ?
            DownloadState.Finish : DownloadState.None);
          ehDownloadStore.setProgress(item.gid, restored[i].finished, restored[i].total, restored[i].finished);
          ehDownloadStore.setStorage(item.gid, restored[i].directory, restored[i].fileSize);
          added++;
        }
      }
    }
    this.statusText = 'Restored ' + added.toString() + '/' + restored.length.toString() + ' downloaded galleries';
    this.persistDownloads();
  }

  private cycleItemState(item: DownloadInfo): void {
    if (item.state === DownloadState.Wait || item.state === DownloadState.Downloading) {
      this.stopItem(item);
      return;
    }
    this.startItem(item);
  }

  private startItem(item: DownloadInfo): void {
    this.shouldStop = false;
    this.removeStoppedGid(item.gid);
    ehDownloadStore.startGallery(item.gid);
    this.statusText = 'Queued: ' + item.title;
    this.persistDownloads();
    this.runDownloadQueue();
  }

  private stopItem(item: DownloadInfo): void {
    this.addStoppedGid(item.gid);
    ehDownloadStore.stopGallery(item.gid);
    this.statusText = 'Stopped: ' + item.title;
    this.persistDownloads();
  }

  private removeItem(item: DownloadInfo): void {
    const context = getAbilityContext();
    if (context !== undefined) {
      ehDownloadFileStore.removeGalleryDirectory(context, item);
    }
    ehDownloadStore.removeGallery(item.gid);
    this.statusText = 'Removed: ' + item.title;
    this.persistDownloads();
  }

  private async runDownloadQueue(): Promise<void> {
    if (this.isProcessing) {
      return;
    }

    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Download needs app context';
      return;
    }

    this.isProcessing = true;
    try {
      const workerCount = downloadThreadLimit();
      this.statusText = 'Download workers: ' + workerCount.toString();
      while (!this.shouldStop) {
        const queue = ehDownloadStore.getItems();
        const batch: DownloadInfo[] = [];
        for (let i = 0; i < queue.length && batch.length < workerCount; i++) {
          if (queue[i].state === DownloadState.Wait) {
            batch.push(queue[i]);
          }
        }
        if (batch.length === 0) {
          break;
        }

        const tasks: Promise<void>[] = [];
        for (let i = 0; i < batch.length; i++) {
          tasks.push(this.downloadOne(context, batch[i]));
        }
        await Promise.all(tasks);
      }
    } finally {
      this.isProcessing = false;
      this.persistDownloads();
    }
  }

  private async downloadOne(context: common.UIAbilityContext, item: DownloadInfo): Promise<void> {
    ehDownloadStore.setState(item.gid, DownloadState.Downloading);
    ehDownloadStore.setTransfer(item.gid, 0, 0);
    this.statusText = 'Downloading: ' + item.title;
    this.persistDownloads();

    try {
      const detailResult = await this.client.loadGalleryDetail(item.gid, item.token, 0, currentGallerySite(),
        EhUrl.getReferer(currentGallerySite()));
      if (!detailResult.ok || detailResult.detail === null) {
        throw new Error(detailResult.message);
      }

      ehDownloadStore.updateGallery(detailResult.detail);
      const total = detailResult.detail.previewSet.length > 0 ? detailResult.detail.previewSet.length :
        detailResult.detail.pages;
      const downloadDirectory = ehDownloadFileStore.prepareGallery(context, detailResult.detail);
      ehDownloadStore.setProgress(item.gid, 0, total, 0);
      ehDownloadStore.setStorage(item.gid, downloadDirectory, 0);

      let finished = 0;
      let fileSize = ehDownloadFileStore.directorySize(context, detailResult.detail);
      for (let i = 0; i < detailResult.detail.previewSet.length; i++) {
        if (ehDownloadFileStore.findPageImage(context, detailResult.detail, i).length > 0) {
          finished++;
        }
      }
      if (finished > 0) {
        ehDownloadStore.setProgress(item.gid, finished, total, finished);
        ehDownloadStore.setStorage(item.gid, downloadDirectory, fileSize);
        this.statusText = 'Resumed ' + finished.toString() + '/' + total.toString() + ': ' + item.title;
        this.persistDownloads();
      }

      let lastBytes = fileSize;
      let lastTime = Date.now();
      const pageIndexes = downloadPageIndexes(detailResult.detail.previewSet.length);
      for (let orderIndex = 0; orderIndex < pageIndexes.length; orderIndex++) {
        const i = pageIndexes[orderIndex];
        if (this.shouldStop || this.isStopped(item.gid)) {
          ehDownloadStore.setState(item.gid, DownloadState.None);
          ehDownloadStore.setTransfer(item.gid, 0, 0);
          this.statusText = 'Stopped: ' + item.title;
          return;
        }

        const preview = detailResult.detail.previewSet[i];
        if (preview.pageUrl.length === 0 || ehDownloadFileStore.findPageImage(context, detailResult.detail, i).length > 0) {
          continue;
        }

        const pageResult = await this.client.loadGalleryPage(preview.pageUrl, currentGallerySite(),
          readerPageReferer(detailResult.url, detailResult.detail.previewSet, i, currentGallerySite()));
        if (!pageResult.ok || pageResult.page === null) {
          throw new Error(pageResult.message);
        }

        const imageUrl = downloadImageUrlForPage(pageResult.page);
        if (imageUrl.length === 0) {
          throw new Error('Image URL missing');
        }

        const cachedPath = await readerImageCache.ensureCached(context, imageUrl, pageResult.page.pageUrl, false);
        const savedPath = ehDownloadFileStore.savePageImage(context, detailResult.detail, pageResult.page, i, cachedPath);
        fileSize += ehDownloadFileStore.statFileSize(savedPath);
        finished++;

        const now = Date.now();
        const speed = Math.round(Math.max(0, fileSize - lastBytes) * 1000 / Math.max(1, now - lastTime));
        lastBytes = fileSize;
        lastTime = now;
        const averageBytes = finished > 0 ? Math.round(fileSize / finished) : 0;
        const remaining = speed > 0 ? Math.round(Math.max(0, total - finished) * averageBytes / speed) : 0;

        ehDownloadStore.setProgress(item.gid, finished, total, finished);
        ehDownloadStore.setStorage(item.gid, downloadDirectory, fileSize);
        ehDownloadStore.setTransfer(item.gid, speed, remaining);
        this.statusText = 'Downloaded ' + finished.toString() + '/' + total.toString() + ': ' + item.title;
        this.persistDownloads();
      }

      ehDownloadStore.setState(item.gid, DownloadState.Finish);
      ehDownloadStore.setProgress(item.gid, total, total, total);
      ehDownloadStore.setStorage(item.gid, downloadDirectory, fileSize);
      ehDownloadStore.setTransfer(item.gid, 0, 0);
      this.statusText = 'Download finished: ' + item.title;
      this.persistDownloads();
    } catch (error) {
      ehDownloadStore.setState(item.gid, DownloadState.Failed);
      ehDownloadStore.setTransfer(item.gid, 0, 0);
      this.statusText = 'Download failed: ' + String(error);
      this.persistDownloads();
    }
  }

  private openDownloadedItem(item: DownloadInfo): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Reader launch failed: Ability context is not ready';
      return;
    }
    const images = ehDownloadFileStore.listPageImages(context, item);
    if (images.length === 0) {
      this.statusText = item.state === DownloadState.Finish ? 'Downloaded files are missing: ' + item.title :
        'Download is not ready: ' + item.title;
      return;
    }

    const session = this.createLocalReaderSession(item, images);
    readerSessionStore.setSession(createReaderSessionState(session.detail, session.page, session.status,
      '', '', currentGallerySite(), session.index));

    if (ehSettingsStore.getValue('reader_standalone', 'On') !== 'On') {
      this.localReaderDetail = session.detail;
      this.localReaderPage = session.page;
      this.localReaderPages = session.pages;
      this.localReaderIndex = session.index;
      this.localReaderStatus = session.status;
      this.localReaderRenderVersion++;
      enterEmbeddedReaderFullscreen();
      this.showReader = true;
      return;
    }

    context.startAbility({
      bundleName: 'yt.ehviewer.huawei',
      moduleName: 'entry',
      abilityName: 'ReaderAbility'
    }).catch((error: Error) => {
      this.statusText = 'Reader launch failed: ' + error.message;
    });
  }

  private createLocalReaderSession(item: DownloadInfo, images: string[]): LocalReaderSession {
    const detail = createDetailFromGallery(item);
    const previews: GalleryPreview[] = [];
    const pages: ReaderPageState[] = [];
    for (let i = 0; i < images.length; i++) {
      const pageUrl = this.localPageUrl(item.gid, i);
      previews.push({
        index: i,
        pageUrl: pageUrl,
        imageUrl: '',
        width: 0,
        height: 0,
        xOffset: 0,
        yOffset: 0
      });
      const page: GalleryPage = {
        pageUrl: pageUrl,
        imageUrl: '',
        skipHathKey: '',
        originImageUrl: '',
        showKey: '',
        cachedImagePath: images[i]
      };
      galleryPageCache.put(pageUrl, page);
      pages.push({ index: i, page: cloneGalleryPage(page) });
    }
    detail.pages = images.length;
    detail.previewPages = 1;
    detail.previewSet = previews;
    const savedIndex = ehHistoryStore.getReadPage(item.gid);
    const index = savedIndex >= 0 && savedIndex < images.length ? savedIndex : 0;
    return {
      detail: detail,
      page: cloneGalleryPage(pages[index].page),
      pages: pages,
      index: index,
      status: 'Page loaded from downloads'
    };
  }

  private closeLocalReader(): void {
    this.showReader = false;
    this.localReaderStatus = 'Page loaded from downloads';
  }

  private jumpLocalReader(index: number): void {
    if (index < 0 || index >= this.localReaderPages.length) {
      return;
    }
    this.localReaderIndex = index;
    this.localReaderPage = cloneGalleryPage(this.localReaderPages[index].page);
    this.localReaderStatus = 'Page loaded from downloads';
    saveGalleryReadPosition(this.localReaderDetail.gid, index);
    this.localReaderRenderVersion++;
    readerSessionStore.updateSession(createReaderSessionState(this.localReaderDetail, this.localReaderPage,
      this.localReaderStatus, '', '', GallerySite.E, this.localReaderIndex));
  }

  private localPageUrl(gid: number, index: number): string {
    return 'ehviewer://download/' + gid.toString() + '/' + index.toString();
  }

  private isStopped(gid: number): boolean {
    for (let i = 0; i < this.stoppedGids.length; i++) {
      if (this.stoppedGids[i] === gid) {
        return true;
      }
    }
    return false;
  }

  private addStoppedGid(gid: number): void {
    if (!this.isStopped(gid)) {
      this.stoppedGids.push(gid);
    }
  }

  private removeStoppedGid(gid: number): void {
    const next: number[] = [];
    for (let i = 0; i < this.stoppedGids.length; i++) {
      if (this.stoppedGids[i] !== gid) {
        next.push(this.stoppedGids[i]);
      }
    }
    this.stoppedGids = next;
  }

  build() {
    if (this.showReader) {
      ReaderScene({
        renderVersion: this.localReaderRenderVersion,
        page: this.localReaderPage,
        readerPages: this.localReaderPages,
        statusText: this.localReaderStatus,
        pageIndex: this.localReaderIndex,
        totalPages: this.localReaderPages.length,
        restoreAppChromeOnExit: true,
        onBack: () => {
          this.closeLocalReader();
        },
        onPrev: () => {
          this.jumpLocalReader(this.localReaderIndex - 1);
        },
        onNext: () => {
          this.jumpLocalReader(this.localReaderIndex + 1);
        },
        onJump: (index: number) => {
          this.jumpLocalReader(index);
        },
        onRetry: () => {
          this.jumpLocalReader(this.localReaderIndex);
        }
      })
    } else {
      Column() {
      EhNavBar({
        statusBarHeight: this.statusBarVp(),
        title: 'Downloads',
        searchMode: true,
        keyword: this.query,
        onMenu: this.onMenu,
        onKeywordChange: (value: string) => {
          this.query = value;
        },
        onSearch: () => {},
        onRefresh: () => {
          this.loadDownloads();
        }
      })

      Column() {
        Row() {
          Button(uiText('Status') + ': ' + uiValue(this.statusFilter))
            .height(30)
            .fontSize(12)
            .onClick(() => {
              this.statusFilter = nextDownloadStatusFilter(this.statusFilter);
            })
          Button(uiText('Category') + ': ' + uiValue(this.categoryFilter))
            .height(30)
            .fontSize(12)
            .margin({ left: 8 })
            .onClick(() => {
              this.categoryFilter = nextDownloadCategoryFilter(this.categoryFilter);
            })
          Button(uiText('Sort') + ': ' + uiValue(this.sortMode))
            .height(30)
            .fontSize(12)
            .margin({ left: 8 })
            .onClick(() => {
              this.sortMode = nextDownloadSortMode(this.sortMode);
            })
        }
        .width('100%')

        Row() {
          Text(uiStatusText(this.statusText))
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.visibleDownloadItems().length.toString() + '/' + this.items.length.toString())
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 8 })

        Text(this.activeSummary())
          .fontSize(11)
          .fontColor(themeSecondaryText())
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(themeSurface())

      if (this.visibleDownloadItems().length === 0) {
        Column() {
          Text(uiText('Downloads'))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(themePrimaryText())
          Text(this.items.length === 0 ? uiText('Download items will be shown here') :
            uiText('No items match the current filter'))
            .fontSize(14)
            .fontColor(themeSecondaryText())
            .margin({ top: 10 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.visibleDownloadItems(), (item: DownloadInfo) => {
            ListItem() {
              DownloadRow({
                item: item,
                onOpen: () => {
                  this.openDownloadedItem(item);
                },
                onState: () => {
                  this.cycleItemState(item);
                },
                onRemove: () => {
                  this.removeItem(item);
                }
              })
            }
          }, (item: DownloadInfo) => item.gid.toString() + '-' + item.state + '-' + item.finished.toString() + '-' +
            item.total.toString() + '-' + item.speed.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
      }

      Row() {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(46)
        .height(46)
        .backgroundColor(themePrimaryColor())
        .onClick(() => {
          this.startAll();
        })

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.pause_fill'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(46)
        .height(46)
        .backgroundColor('#475467')
        .margin({ left: 12 })
        .onClick(() => {
          this.stopAll();
        })

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.play_arrow_triangle_2_circlepath'))
            .fontSize(19)
            .fontColor([Color.White])
        }
        .width(46)
        .height(46)
        .backgroundColor('#667085')
        .margin({ left: 12 })
        .onClick(() => {
          this.restoreDownloadedItems();
        })

        Blank()

        Button(uiText('Clear done'))
          .height(40)
          .fontSize(13)
          .enabled(this.items.length > 0)
          .onClick(() => {
            this.clearFinished();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 12 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(themePageBackground())
    }
  }
}

interface LocalReaderSession {
  detail: GalleryDetail;
  page: GalleryPage;
  pages: ReaderPageState[];
  index: number;
  status: string;
}
