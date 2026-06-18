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
import { applyAppChromeImmersiveMode } from '../services/EhWindowImmersive';
import { APP_THEME_COLOR, LANGUAGE_REVISION_KEY } from '../shared/EhShared';
import { EhBackupBundle, DrawerItem, SettingsHeaderItem, SettingsRowItem, SessionMode, SettingsPanel, DRAWER_ITEMS, SETTINGS_HEADERS, STATUS_BAR_HEIGHT_KEY, ON_OFF_OPTIONS, shouldUseChineseUi, uiText, uiValue, uiStatusText, uiPageText, zhText, setActiveBackHandler, runActiveBackHandler, createEmptyGallery, createEmptyDownloadInfo, createDetailFromGallery, createEmptyDetail, createEmptyPreview, createEmptyPage, createEmptyTopListDetail, createEmptyTopListInfo, createEmptyTopListBucket, createEmptyTopListItem, cloneStringArray, cloneRequiredStringArray, cloneGalleryInfo, cloneGalleryInfos, padTwo, applyGalleryFilters, cloneGalleryTagGroups, cloneGalleryComments, cloneGalleryPreviews, cloneGalleryDetail, cloneGalleryPage, createReaderLoadingPage, cloneTopListItem, cloneTopListBucket, cloneTopListInfo, cloneTopListDetail, getAbilityContext, saveGalleryToHistory, saveGalleryReadPosition, readerStartIndex, downloadButtonText, toggleGalleryDownload, saveDownloadsQuietly, filterDownloadItems, downloadItemMatches, sortDownloadItems, nextDownloadStatusFilter, nextDownloadLabelFilter, nextDownloadSortMode, nextStringOption, nextDownloadState, nextDownloadLabel, downloadLabelName, downloadStateLabel, downloadStateColor, downloadProgressText, downloadSizeText, downloadImageUrlForPage, downloadThreadLimit, downloadPageIndexes, downloadQueueSummary, parseHistoryMaxSize, routeTitle, routeSubtitle, launchRouteFromSetting, settingsPanelTitle, settingsRowsForPanel, optionSettingsRow, textSettingsRow, staticSettingsRow, settingEntryValue, cloneStringOptions, settingMigrationMessage, nextOption, isValidProxyPortText, formatNetworkDiagnostics, listModeForRoute, routeUsesKeyword, usesGallerySearchToolbar, usesEmbeddedToolbar, defaultKeywordForRoute, gallerySearchTitle, currentGallerySite, effectiveListSite, gallerySiteName, galleryListFailureMessage, withGalleryListMessage, readerPageReferer, readerDisplayImageUrl, cacheReaderImageForPage, cacheThumbnailImage, cloneGalleryPageWithCache, readerLocalImageSource, readerZoomSize, readerFullImageWidth, readerFullImageHeight, readerImageFit, readerShortUrl, readerPreloadCount, readerIsRightToLeft, categoryName, categoryColor, ratingText, galleryDisplayTitle, showGalleryPages, galleryListMode, galleryThumbWidth, galleryThumbHeight, galleryRowHeight, galleryTagPreview, detailTitleFontSize, detailTitleMaxLines, detailHeadingFontSize, readerShowProgress, readerShowClock, readerClockText, padTimeNumber, topListChipColor } from '../shared/EhShared';
import { CategoryBadge, GalleryThumb, PlaceholderScene } from './GalleryScenes';
import { EhNavBar } from './NavigationComponents';
import { SessionScene, SettingsSubToolbar } from './SessionSettingsScenes';

@Component
export struct DownloadScene {
  private client: EhHttpClient = new EhHttpClient();
  private shouldStop: boolean = false;
  onMenu: () => void = () => {};

  @State items: DownloadInfo[] = [];
  @State labels: DownloadLabel[] = [];
  @State query: string = '';
  @State statusFilter: string = 'All';
  @State labelFilter: string = 'All';
  @State sortMode: string = 'Default';
  @State newLabel: string = '';
  @State statusText: string = 'Download queue is ready';
  @State isProcessing: boolean = false;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    this.loadDownloads();
  }

  private loadDownloads(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.items = ehDownloadStore.getItems();
      this.labels = ehDownloadStore.getLabels();
      return;
    }

    ehDownloadStore.load(context).then(() => {
      this.items = ehDownloadStore.getItems();
      this.labels = ehDownloadStore.getLabels();
      this.statusText = this.items.length.toString() + ' download items';
    }).catch((error: Error) => {
      this.statusText = 'Download load failed: ' + error.message;
      this.items = ehDownloadStore.getItems();
      this.labels = ehDownloadStore.getLabels();
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
    return filterDownloadItems(this.items, this.query, this.statusFilter, this.labelFilter, this.sortMode);
  }

  private startAll(): void {
    this.shouldStop = false;
    ehDownloadStore.startAll();
    this.items = ehDownloadStore.getItems();
    this.statusText = 'Queued idle and failed downloads';
    this.persistDownloads();
    this.runDownloadQueue();
  }

  private stopAll(): void {
    this.shouldStop = true;
    ehDownloadStore.stopAll();
    this.items = ehDownloadStore.getItems();
    this.statusText = 'Stopped waiting downloads';
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
      this.items = ehDownloadStore.getItems();
      this.persistDownloads();
    }
  }

  private async downloadOne(context: common.UIAbilityContext, item: DownloadInfo): Promise<void> {
    ehDownloadStore.setState(item.gid, DownloadState.Downloading);
    this.items = ehDownloadStore.getItems();
    this.statusText = 'Downloading: ' + item.title;
    this.persistDownloads();

    try {
      const detailResult = await this.client.loadGalleryDetail(item.gid, item.token, 0, currentGallerySite(), EhUrl.getReferer(currentGallerySite()));
      if (!detailResult.ok || detailResult.detail === null) {
        throw new Error(detailResult.message);
      }

      ehDownloadStore.updateGallery(detailResult.detail);
      const total = detailResult.detail.previewSet.length > 0 ? detailResult.detail.previewSet.length : detailResult.detail.pages;
      const downloadDirectory = ehDownloadFileStore.prepareGallery(context, detailResult.detail);
      ehDownloadStore.setProgress(item.gid, 0, total, 0);
      ehDownloadStore.setStorage(item.gid, downloadDirectory, 0);
      this.items = ehDownloadStore.getItems();

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
        this.items = ehDownloadStore.getItems();
        this.statusText = 'Resumed ' + finished.toString() + '/' + total.toString() + ': ' + item.title;
        this.persistDownloads();
      }

      const pageIndexes = downloadPageIndexes(detailResult.detail.previewSet.length);
      for (let orderIndex = 0; orderIndex < pageIndexes.length; orderIndex++) {
        const i = pageIndexes[orderIndex];
        if (this.shouldStop) {
          ehDownloadStore.setState(item.gid, DownloadState.None);
          this.statusText = 'Stopped: ' + item.title;
          return;
        }

        const preview = detailResult.detail.previewSet[i];
        if (preview.pageUrl.length === 0) {
          continue;
        }

        if (ehDownloadFileStore.findPageImage(context, detailResult.detail, i).length > 0) {
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
        ehDownloadStore.setProgress(item.gid, finished, total, finished);
        ehDownloadStore.setStorage(item.gid, downloadDirectory, fileSize);
        this.items = ehDownloadStore.getItems();
        this.statusText = 'Downloaded ' + finished.toString() + '/' + total.toString() + ': ' + item.title;
        this.persistDownloads();
      }

      ehDownloadStore.setState(item.gid, DownloadState.Finish);
      ehDownloadStore.setProgress(item.gid, total, total, total);
      ehDownloadStore.setStorage(item.gid, downloadDirectory, fileSize);
      this.statusText = 'Download finished: ' + item.title;
      this.items = ehDownloadStore.getItems();
      this.persistDownloads();
    } catch (error) {
      ehDownloadStore.setState(item.gid, DownloadState.Failed);
      this.items = ehDownloadStore.getItems();
      this.statusText = 'Download failed: ' + String(error);
      this.persistDownloads();
    }
  }

  private clearFinished(): void {
    ehDownloadStore.clearFinished();
    this.items = ehDownloadStore.getItems();
    this.statusText = 'Cleared finished downloads';
    this.persistDownloads();
  }

  private addLabel(): void {
    if (ehDownloadStore.addLabel(this.newLabel)) {
      this.labels = ehDownloadStore.getLabels();
      this.statusText = 'Added label: ' + this.newLabel.trim();
      this.newLabel = '';
      this.persistDownloads();
    } else {
      this.statusText = 'Label is empty or already exists';
    }
  }

  private removeSelectedLabel(): void {
    if (this.labelFilter === 'All' || this.labelFilter === 'Default') {
      this.statusText = 'Select a custom label before deleting';
      return;
    }
    ehDownloadStore.removeLabel(this.labelFilter);
    this.labels = ehDownloadStore.getLabels();
    this.items = ehDownloadStore.getItems();
    this.statusText = 'Deleted label: ' + this.labelFilter;
    this.labelFilter = 'All';
    this.persistDownloads();
  }

  private removeItem(item: DownloadInfo): void {
    ehDownloadStore.removeGallery(item.gid);
    this.items = ehDownloadStore.getItems();
    this.statusText = 'Removed: ' + item.title;
    this.persistDownloads();
  }

  private cycleItemState(item: DownloadInfo): void {
    ehDownloadStore.setState(item.gid, nextDownloadState(item.state));
    this.items = ehDownloadStore.getItems();
    this.statusText = 'Updated state: ' + item.title;
    this.persistDownloads();
  }

  private cycleItemLabel(item: DownloadInfo): void {
    const label = nextDownloadLabel(item.label, this.labels);
    ehDownloadStore.setLabel(item.gid, label);
    this.items = ehDownloadStore.getItems();
    this.statusText = label.length === 0 ? 'Moved to default label: ' + item.title : 'Moved to label ' + label + ': ' + item.title;
    this.persistDownloads();
  }

  build() {
    Column() {
      EhNavBar({
        statusBarHeight: this.statusBarVp(),
        title: 'Search downloads',
        searchMode: true,
        keyword: this.query,
        onMenu: this.onMenu,
        onKeywordChange: (value: string) => {
          this.query = value;
        },
        onSearch: () => {
          this.loadDownloads();
        },
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
          Button(uiText('Label') + ': ' + uiValue(this.labelFilter))
            .height(30)
            .fontSize(12)
            .margin({ left: 8 })
            .onClick(() => {
              this.labelFilter = nextDownloadLabelFilter(this.labelFilter, this.labels);
            })
          Button(uiText('Sort') + ': ' + uiValue(this.sortMode))
            .height(30)
            .fontSize(12)
            .margin({ left: 8 })
            .onClick(() => {
              this.sortMode = nextDownloadSortMode(this.sortMode);
            })
          Blank()
          Text(this.visibleDownloadItems().length.toString() + '/' + this.items.length.toString())
            .fontSize(12)
            .fontColor('#667085')
        }
        .width('100%')

        Row() {
          TextInput({ text: this.newLabel, placeholder: uiText('New label') })
            .height(34)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.newLabel = value;
            })
          Button(uiText('Add'))
            .height(34)
            .fontSize(12)
            .margin({ left: 8 })
            .onClick(() => {
              this.addLabel();
            })
          Button(uiText('Delete'))
            .height(34)
            .fontSize(12)
            .margin({ left: 8 })
            .enabled(this.labelFilter !== 'All' && this.labelFilter !== 'Default')
            .onClick(() => {
              this.removeSelectedLabel();
            })
        }
        .width('100%')
        .margin({ top: 6 })

        Row() {
          Text(uiStatusText(this.statusText))
            .fontSize(11)
            .fontColor('#40566F')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(uiStatusText(downloadQueueSummary(this.items)))
            .fontSize(11)
            .fontColor('#667085')
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(Color.White)
      .margin({ left: 12, right: 12, top: 12, bottom: 8 })

      if (this.visibleDownloadItems().length === 0) {
        Column() {
          Text(uiText('Downloads'))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#17202A')
          Text(this.items.length === 0 ? uiText('Download items will be shown here') : uiText('No items match the current filter'))
            .fontSize(14)
            .fontColor('#667085')
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
                onState: () => {
                  this.cycleItemState(item);
                },
                onLabel: () => {
                  this.cycleItemLabel(item);
                },
                onRemove: () => {
                  this.removeItem(item);
                }
              })
            }
          }, (item: DownloadInfo) => item.gid.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 8, right: 8, bottom: 8 })
      }

      Row() {
        Button(uiText('Start all'))
          .height(42)
          .layoutWeight(1)
          .onClick(() => {
            this.startAll();
          })
        Button(uiText('Stop all'))
          .height(42)
          .layoutWeight(1)
          .margin({ left: 8 })
          .onClick(() => {
            this.stopAll();
          })
        Button(uiText('Clear done'))
          .height(42)
          .layoutWeight(1)
          .margin({ left: 8 })
          .onClick(() => {
            this.clearFinished();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F3F5F7')
  }
}

@Component
export struct DownloadRow {
  item: DownloadInfo = createEmptyDownloadInfo();
  onState: () => void = () => {};
  onLabel: () => void = () => {};
  onRemove: () => void = () => {};

  build() {
    Row() {
      GalleryThumb({
        url: this.item.thumb === undefined ? '' : this.item.thumb,
        widthValue: galleryThumbWidth(),
        heightValue: galleryThumbHeight()
      })

      Column() {
        Row() {
          Text(galleryDisplayTitle(this.item))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#17202A')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(uiValue(downloadStateLabel(this.item.state)))
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(downloadStateColor(this.item.state))
            .borderRadius(3)
        }
        .width('100%')

        Row() {
          CategoryBadge({ category: this.item.category })
          if (showGalleryPages()) {
            Text(this.item.pages.toString() + 'p')
              .fontSize(12)
              .fontColor('#667085')
              .margin({ left: 8 })
          }
          Text(this.item.label.length === 0 ? uiText('Default') : this.item.label)
            .fontSize(12)
            .fontColor('#667085')
            .margin({ left: 8 })
          Blank()
          Text(downloadProgressText(this.item))
            .fontSize(12)
            .fontColor('#667085')
        }
        .width('100%')
        .margin({ top: 8 })

        if (this.item.archiveUri.length > 0 || this.item.fileSize > 0) {
          Row() {
            Text(downloadSizeText(this.item.fileSize))
              .fontSize(11)
              .fontColor('#667085')
            Text(this.item.archiveUri)
              .fontSize(11)
              .fontColor('#98A2B3')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .margin({ left: 8 })
          }
          .width('100%')
          .margin({ top: 6 })
        }

        Row() {
          Text(this.item.uploader === undefined || this.item.uploader.length === 0 ? uiText('unknown uploader') : this.item.uploader)
            .fontSize(12)
            .fontColor('#98A2B3')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Button(uiText('State'))
            .height(30)
            .onClick(() => {
              this.onState();
            })
          Button(uiText('Label'))
            .height(30)
            .margin({ left: 6 })
            .onClick(() => {
              this.onLabel();
            })
          Button(uiText('Remove'))
            .height(30)
            .margin({ left: 6 })
            .onClick(() => {
              this.onRemove();
            })
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .height(galleryRowHeight())
      .layoutWeight(1)
      .margin({ left: 10 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(8)
    .backgroundColor(Color.White)
    .borderRadius(6)
  }
}

@Component
export struct FilterPanel {
  rules: FilterRule[] = [];
  newText: string = '';
  newMode: number = FILTER_MODE_TITLE;
  statusText: string = '';
  onBack: () => void = () => {};
  onNewTextChange: (text: string) => void = () => {};
  onNewModeChange: (mode: number) => void = () => {};
  onAdd: () => void = () => {};
  onRemove: (id: number) => void = () => {};
  onToggle: (id: number) => void = () => {};

  private filterModeName(mode: number): string {
    if (mode === FILTER_MODE_UPLOADER) {
      return uiText('Uploader');
    }
    if (mode === FILTER_MODE_TAG) {
      return uiText('Tag');
    }
    if (mode === FILTER_MODE_TAG_NAMESPACE) {
      return uiText('Tag:Namespace');
    }
    return uiText('Title');
  }

  private cycleMode(): void {
    const next = (this.newMode + 1) % 4;
    this.onNewModeChange(next);
  }

  build() {
    Column() {
      SettingsSubToolbar({
        title: uiText('Filter rules'),
        onBack: this.onBack
      })

      Column() {
        Row() {
          TextInput({ text: this.newText, placeholder: uiText('Filter text') })
            .layoutWeight(1)
            .height(40)
            .onChange((value: string) => {
              this.onNewTextChange(value);
            })
          Button(this.filterModeName(this.newMode))
            .height(40)
            .margin({ left: 8 })
            .onClick(() => {
              this.cycleMode();
            })
          Button(uiText('Add'))
            .height(40)
            .margin({ left: 8 })
            .fontWeight(FontWeight.Bold)
            .onClick(() => {
              this.onAdd();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 4 })

        if (this.statusText.length > 0) {
          Text(uiStatusText(this.statusText))
            .fontSize(12)
            .fontColor('#667085')
            .padding({ left: 16, right: 16, bottom: 8 })
            .width('100%')
        }

        Text(uiText('Mode: tap to cycle ¡ª Title / Uploader / Tag / Tag:Namespace'))
          .fontSize(11)
          .fontColor('#95A1B0')
          .padding({ left: 16, right: 16, bottom: 10 })
          .width('100%')
      }
      .backgroundColor(Color.White)

      if (this.rules.length === 0) {
        PlaceholderScene({
          title: 'No filters',
          detail: 'Add a filter rule above to hide matching galleries from lists.'
        })
      } else {
        List({ space: 0 }) {
          ForEach(this.rules, (rule: FilterRule) => {
            ListItem() {
              Row() {
                Column() {
                  Text(rule.text)
                    .fontSize(14)
                    .fontColor(rule.enabled ? '#17202A' : '#95A1B0')
                    .fontWeight(rule.enabled ? FontWeight.Medium : FontWeight.Normal)
                  Text(this.filterModeName(rule.mode))
                    .fontSize(11)
                    .fontColor('#667085')
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button(rule.enabled ? uiText('On') : uiText('Off'))
                  .height(30)
                  .fontSize(12)
                  .fontColor(rule.enabled ? '#0A6B45' : '#95A1B0')
                  .backgroundColor(rule.enabled ? '#EDFAF3' : '#F5F5F5')
                  .margin({ left: 8 })
                  .onClick(() => {
                    this.onToggle(rule.id);
                  })
                Button(uiText('Remove'))
                  .height(30)
                  .fontSize(12)
                  .fontColor('#C33A2C')
                  .backgroundColor('#FDF0EE')
                  .margin({ left: 6 })
                  .onClick(() => {
                    this.onRemove(rule.id);
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 12, top: 12, bottom: 12 })
              .backgroundColor(Color.White)
            }
          }, (rule: FilterRule) => rule.id.toString())
        }
        .divider({ strokeWidth: 1, color: '#F0F0F0' })
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }
}

@Component
export struct MigrationScene {
  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
  }

  build() {
    List({ space: 10 }) {
      ForEach(migrationTasks, (task: MigrationTask) => {
        ListItem() {
          Column() {
            Text(task.name)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#17202A')
            Text(task.source)
              .fontSize(12)
              .fontColor('#667085')
              .margin({ top: 6 })
            Row() {
              Text(task.target)
                .fontSize(12)
                .fontColor('#40566F')
                .layoutWeight(1)
              Text(task.status)
                .fontSize(12)
                .fontColor(task.status.startsWith('started') || task.status.startsWith('done') ? '#0A6B45' : '#6B7280')
            }
            .margin({ top: 8 })
          }
          .width('100%')
          .padding(14)
          .backgroundColor(Color.White)
          .borderRadius(6)
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 16 })
  }
}
