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
@Component
export struct AppToolbar {
  title: string = '';
  subtitle: string = '';
  onMenu: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.open_sidebar'))
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(38)
      .height(38)
      .backgroundColor('rgba(255,255,255,0.15)')
      .onClick(() => {
        this.onMenu();
      })

      Column() {
        Text(uiText(this.title))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle.length > 0) {
          Text(uiText(this.subtitle))
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.7)')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('100%')
    .height(60)
    .padding({ left: 14, right: 16 })
    .backgroundColor('#2F6F8F')
  }
}

@Component
export struct DrawerPanel {
  @Prop activeRoute: GalleryRoute = GalleryRoute.Home;
  onSelect: (route: GalleryRoute) => void = () => {};
  @State signedIn: boolean = false;
  @State downloadSummary: string = 'Downloads: idle';
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  private downloadRefreshTimer: number = -1;

  aboutToAppear(): void {
    this.signedIn = ehCookieStore.hasCookies();
    this.refreshDownloadSummary();
    const context = getAbilityContext();
    if (context !== undefined) {
      ehDownloadStore.load(context).then(() => {
        this.refreshDownloadSummary();
      }).catch(() => {
        this.downloadSummary = 'Downloads: unavailable';
      });
    }
    this.downloadRefreshTimer = setInterval(() => {
      this.refreshDownloadSummary();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.downloadRefreshTimer >= 0) {
      clearInterval(this.downloadRefreshTimer);
      this.downloadRefreshTimer = -1;
    }
  }

  private refreshDownloadSummary(): void {
    this.downloadSummary = 'Downloads: ' + downloadQueueSummary(ehDownloadStore.getItems());
  }

  build() {
    Column() {
      DrawerHeader({ signedIn: this.signedIn })

      List({ space: 2 }) {
        ForEach(DRAWER_ITEMS, (item: DrawerItem) => {
          ListItem() {
            DrawerRow({
              item: item,
              selected: item.route === this.activeRoute,
              onTapItem: () => {
                this.onSelect(item.route);
              }
            })
          }
        }, (item: DrawerItem) => item.route + ':' + this.activeRoute)
      }
      .layoutWeight(1)
      .width('100%')

      Column() {
        Text(uiStatusText(this.downloadSummary))
          .fontSize(11)
          .fontColor('#98A2B3')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .backgroundColor('#F8FAFC')
    }
    .width(248)
    .height('100%')
    .backgroundColor(Color.White)
  }
}

@Component
export struct DrawerHeader {
  signedIn: boolean = false;

  build() {
    Column() {
      Row() {
        Column() {
          Text(this.signedIn ? 'EH' : '?')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#2F6F8F')
            .textAlign(TextAlign.Center)
            .width(52)
            .height(52)
            .backgroundColor(Color.White)
            .borderRadius(26)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column() {
          Text('EhViewer')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
          Text(this.signedIn ? uiText('Signed in') : uiText('Guest mode'))
            .fontSize(12)
            .fontColor('rgba(255,255,255,0.7)')
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 14 })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 24, bottom: 20 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor('#2F6F8F')
  }
}

@Component
export struct DrawerRow {
  item: DrawerItem = { route: GalleryRoute.Home, title: '', icon: '', subtitle: '' };
  selected: boolean = false;
  onTapItem: () => void = () => {};

  build() {
    Row() {
      Column()
        .width(3)
        .height(32)
        .borderRadius(2)
        .backgroundColor(this.selected ? '#2F6F8F' : 'transparent')
        .margin({ right: 10 })

      Text(this.item.icon)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.selected ? '#2F6F8F' : '#6B8FAA')
        .textAlign(TextAlign.Center)
        .width(34)
        .height(34)
        .backgroundColor(this.selected ? '#D6EBF5' : '#F4F7FA')
        .borderRadius(10)

      Column() {
        Text(uiText(this.item.title))
          .fontSize(14)
          .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.selected ? '#2F6F8F' : '#2D3A45')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(uiText(this.item.subtitle))
          .fontSize(11)
          .fontColor('#98A2B3')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 1 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 8, right: 14, top: 8, bottom: 8 })
    .backgroundColor(this.selected ? '#F0F8FC' : Color.White)
    .onClick(() => {
      this.onTapItem();
    })
  }
}
