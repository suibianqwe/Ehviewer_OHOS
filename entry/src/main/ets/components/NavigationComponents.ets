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
import { APP_THEME_COLOR, LANGUAGE_REVISION_KEY, themeSurfaceColor } from '../shared/EhShared';
import { EhBackupBundle, DrawerItem, SettingsHeaderItem, SettingsRowItem, SessionMode, SettingsPanel, DRAWER_ITEMS, SETTINGS_HEADERS, STATUS_BAR_HEIGHT_KEY, ON_OFF_OPTIONS, shouldUseChineseUi, uiText, uiValue, uiStatusText, uiPageText, zhText, setActiveBackHandler, runActiveBackHandler, createEmptyGallery, createEmptyDownloadInfo, createDetailFromGallery, createEmptyDetail, createEmptyPreview, createEmptyPage, createEmptyTopListDetail, createEmptyTopListInfo, createEmptyTopListBucket, createEmptyTopListItem, cloneStringArray, cloneRequiredStringArray, cloneGalleryInfo, cloneGalleryInfos, padTwo, applyGalleryFilters, cloneGalleryTagGroups, cloneGalleryComments, cloneGalleryPreviews, cloneGalleryDetail, cloneGalleryPage, createReaderLoadingPage, cloneTopListItem, cloneTopListBucket, cloneTopListInfo, cloneTopListDetail, getAbilityContext, saveGalleryToHistory, saveGalleryReadPosition, readerStartIndex, downloadButtonText, toggleGalleryDownload, saveDownloadsQuietly, filterDownloadItems, downloadItemMatches, sortDownloadItems, nextDownloadStatusFilter, nextDownloadLabelFilter, nextDownloadSortMode, nextStringOption, nextDownloadState, nextDownloadLabel, downloadLabelName, downloadStateLabel, downloadStateColor, downloadProgressText, downloadSizeText, downloadImageUrlForPage, downloadThreadLimit, downloadPageIndexes, downloadQueueSummary, parseHistoryMaxSize, routeTitle, routeSubtitle, launchRouteFromSetting, settingsPanelTitle, settingsRowsForPanel, optionSettingsRow, textSettingsRow, staticSettingsRow, settingEntryValue, cloneStringOptions, settingMigrationMessage, nextOption, isValidProxyPortText, formatNetworkDiagnostics, listModeForRoute, routeUsesKeyword, usesGallerySearchToolbar, usesEmbeddedToolbar, defaultKeywordForRoute, gallerySearchTitle, currentGallerySite, effectiveListSite, gallerySiteName, galleryListFailureMessage, shouldRetryGalleryListOnE, withGalleryListMessage, readerPageReferer, readerDisplayImageUrl, cacheReaderImageForPage, cacheThumbnailImage, cloneGalleryPageWithCache, readerLocalImageSource, readerZoomSize, readerFullImageWidth, readerFullImageHeight, readerImageFit, readerShortUrl, readerPreloadCount, readerIsRightToLeft, categoryName, categoryColor, ratingText, galleryDisplayTitle, showGalleryPages, galleryListMode, galleryThumbWidth, galleryThumbHeight, galleryRowHeight, galleryTagPreview, detailTitleFontSize, detailTitleMaxLines, detailHeadingFontSize, readerShowProgress, readerShowClock, readerClockText, padTimeNumber, topListChipColor } from '../shared/EhShared';
@Component
export struct AppToolbar {
  title: string = '';
  subtitle: string = '';
  onMenu: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    AppTopBar({
      title: this.title,
      subtitle: this.subtitle,
      symbol: $r('sys.symbol.open_sidebar'),
      onAction: this.onMenu
    })
  }
}

@Component
export struct AppSubToolbar {
  title: string = '';
  onBack: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    AppTopBar({
      title: this.title,
      subtitle: '',
      symbol: $r('sys.symbol.chevron_left'),
      onAction: this.onBack
    })
  }
}

@Component
export struct AppTopBar {
  title: string = '';
  subtitle: string = '';
  symbol: Resource = $r('sys.symbol.open_sidebar');
  onAction: () => void = () => {};

  build() {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph(this.symbol)
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(38)
      .height(38)
      .backgroundColor('rgba(255,255,255,0.15)')
      .onClick(() => {
        this.onAction();
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
    .height(62)
    .padding({ left: 14, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(APP_THEME_COLOR)
  }
}

@Component
export struct FloatingToolbar {
  @Prop visible: boolean = true;
  @Prop barHeight: number = 62;
  @Prop offsetY: number = 0;
  @BuilderParam content: () => void = this.EmptyContent;

  @Builder
  private EmptyContent() {
  }

  private toolbarOffset(): number {
    if (this.offsetY !== 0) {
      return this.offsetY;
    }
    return this.visible ? 0 : -this.barHeight;
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .translate({ y: this.toolbarOffset() })
    .zIndex(10)
  }
}

@Component
export struct FloatingToolbarHost {
  @Prop kind: string = 'title';
  @Prop title: string = '';
  @Prop keyword: string = '';
  @Prop filterActive: boolean = false;
  @Prop requestUrl: string = '';
  @Prop showClear: boolean = false;
  @Prop canClear: boolean = false;
  @Prop toolbarOffsetY: number = 0;
  @Prop toolbarHeight: number = 62;
  @BuilderParam content: () => void = this.EmptyContent;
  onKeywordChange: (value: string) => void = () => {};
  onMenu: () => void = () => {};
  onSearch: () => void = () => {};
  onRefresh: () => void = () => {};
  onClear: () => void = () => {};

  @Builder
  private EmptyContent() {
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()
      FloatingToolbar({ offsetY: this.toolbarOffsetY, barHeight: this.toolbarHeight }) {
        if (this.kind === 'search') {
          GallerySearchToolbar({
            keyword: this.keyword,
            title: this.title,
            filterActive: this.filterActive,
            requestUrl: this.requestUrl,
            onKeywordChange: this.onKeywordChange,
            onMenu: this.onMenu,
            onSearch: this.onSearch
          })
        } else {
          ActionTitleToolbar({
            title: this.title,
            requestUrl: this.requestUrl,
            showClear: this.showClear,
            canClear: this.canClear,
            onMenu: this.onMenu,
            onRefresh: this.onRefresh,
            onClear: this.onClear
          })
        }
      }
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct GallerySearchToolbar {
  @Prop keyword: string = '';
  @Prop title: string = '';
  @Prop filterActive: boolean = false;
  @Prop requestUrl: string = '';
  onKeywordChange: (value: string) => void = () => {};
  onMenu: () => void = () => {};
  onSearch: () => void = () => {};

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

        Stack({ alignContent: Alignment.BottomStart }) {
          TextInput({ text: this.keyword, placeholder: this.title.length === 0 ? uiText('Search galleries') : uiText(this.title) })
            .height(38)
            .width('100%')
            .backgroundColor(themeSurfaceColor())
            .borderRadius(19)
            .placeholderColor('rgba(47,111,143,0.5)')
            .fontColor('#17202A')
            .caretColor(APP_THEME_COLOR)
            .padding({ left: 16, right: 16 })
            .onChange((value: string) => {
              this.onKeywordChange(value);
            })
          if (this.filterActive) {
            Text(uiText('Filter mode'))
              .fontSize(9)
              .fontColor(Color.White)
              .backgroundColor('rgba(255,255,255,0.3)')
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .borderRadius(4)
              .margin({ left: 10, bottom: 6 })
          }
        }
        .height(38)
        .layoutWeight(1)
        .margin({ left: 10 })

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(38)
        .height(38)
        .backgroundColor('rgba(255,255,255,0.15)')
        .flexShrink(0)
        .margin({ left: 10 })
        .onClick(() => {
          this.onSearch();
        })
      }
      .width('100%')
      .height(62)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)

    }
    .width('100%')
    .backgroundColor(APP_THEME_COLOR)
  }
}

@Component
export struct ActionTitleToolbar {
  @Prop title: string = '';
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

        Text(uiText(this.title))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 12, right: 10 })

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.play_arrow_triangle_2_circlepath'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(38)
        .height(38)
        .backgroundColor('rgba(255,255,255,0.15)')
        .flexShrink(0)
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

    }
    .width('100%')
    .backgroundColor(APP_THEME_COLOR)
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
    .backgroundColor(APP_THEME_COLOR)
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
