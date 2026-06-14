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
import { applyWindowPrivacyMode } from '../services/EhWindowPrivacy';
import { LANGUAGE_REVISION_KEY, notifyLanguageChanged } from '../shared/EhShared';
import { EhBackupBundle, DrawerItem, SettingsHeaderItem, SettingsRowItem, SessionMode, SettingsPanel, DRAWER_ITEMS, SETTINGS_HEADERS, STATUS_BAR_HEIGHT_KEY, ON_OFF_OPTIONS, shouldUseChineseUi, uiText, uiValue, uiStatusText, uiPageText, zhText, setActiveBackHandler, runActiveBackHandler, createEmptyGallery, createEmptyDownloadInfo, createDetailFromGallery, createEmptyDetail, createEmptyPreview, createEmptyPage, createEmptyTopListDetail, createEmptyTopListInfo, createEmptyTopListBucket, createEmptyTopListItem, cloneStringArray, cloneRequiredStringArray, cloneGalleryInfo, cloneGalleryInfos, padTwo, applyGalleryFilters, cloneGalleryTagGroups, cloneGalleryComments, cloneGalleryPreviews, cloneGalleryDetail, cloneGalleryPage, createReaderLoadingPage, cloneTopListItem, cloneTopListBucket, cloneTopListInfo, cloneTopListDetail, getAbilityContext, saveGalleryToHistory, saveGalleryReadPosition, readerStartIndex, downloadButtonText, toggleGalleryDownload, saveDownloadsQuietly, filterDownloadItems, downloadItemMatches, sortDownloadItems, nextDownloadStatusFilter, nextDownloadLabelFilter, nextDownloadSortMode, nextStringOption, nextDownloadState, nextDownloadLabel, downloadLabelName, downloadStateLabel, downloadStateColor, downloadProgressText, downloadSizeText, downloadImageUrlForPage, downloadThreadLimit, downloadPageIndexes, downloadQueueSummary, parseHistoryMaxSize, routeTitle, routeSubtitle, launchRouteFromSetting, settingsPanelTitle, settingsRowsForPanel, optionSettingsRow, textSettingsRow, staticSettingsRow, settingEntryValue, cloneStringOptions, settingMigrationMessage, nextOption, isValidProxyPortText, formatNetworkDiagnostics, listModeForRoute, routeUsesKeyword, usesGallerySearchToolbar, usesEmbeddedToolbar, defaultKeywordForRoute, gallerySearchTitle, currentGallerySite, effectiveListSite, gallerySiteName, galleryListFailureMessage, shouldRetryGalleryListOnE, withGalleryListMessage, readerPageReferer, readerDisplayImageUrl, cacheReaderImageForPage, cacheThumbnailImage, cloneGalleryPageWithCache, readerLocalImageSource, readerZoomSize, readerFullImageWidth, readerFullImageHeight, readerImageFit, readerShortUrl, readerPreloadCount, readerIsRightToLeft, categoryName, categoryColor, ratingText, galleryDisplayTitle, showGalleryPages, galleryListMode, galleryThumbWidth, galleryThumbHeight, galleryRowHeight, galleryTagPreview, detailTitleFontSize, detailTitleMaxLines, detailHeadingFontSize, readerShowProgress, readerShowClock, readerClockText, padTimeNumber, topListChipColor } from '../shared/EhShared';import { FilterPanel, MigrationScene } from './DownloadMigrationScenes';
@Component
export struct SessionScene {
  private client: EhHttpClient = new EhHttpClient();
  private webController: webview.WebviewController = new webview.WebviewController();

  @State mode: SessionMode = SessionMode.Password;
  @State username: string = '';
  @State password: string = '';
  @State cookieInput: string = '';
  @State memberId: string = '';
  @State passHash: string = '';
  @State igneous: string = '';
  @State signingIn: boolean = false;
  @State webCookieCaptured: boolean = false;
  @State webUrl: string = EhUrl.URL_SIGN_IN;
  @State statusText: string = 'Sign in with an E-Hentai forum account';
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  onSignedIn: () => void = () => {};

  aboutToAppear(): void {
    this.cookieInput = ehCookieStore.getEditableCookieHeader();
    const context = getAbilityContext();
    if (context !== undefined) {
      ehCookieStore.load(context).then(() => {
        this.cookieInput = ehCookieStore.getEditableCookieHeader();
        this.syncCookieFieldsFromInput(this.cookieInput, false);
        this.statusText = ehCookieStore.hasCookies() ? 'Persisted Cookie loaded' : 'No Cookie saved';
      }).catch((error: Error) => {
        this.statusText = 'Cookie load failed: ' + error.message;
      });
    }
  }

  private switchMode(mode: SessionMode): void {
    this.mode = mode;
    if (mode === SessionMode.Password) {
      this.statusText = 'Sign in with an E-Hentai forum account';
    } else if (mode === SessionMode.Cookie) {
      this.statusText = 'Enter ipb_member_id and ipb_pass_hash, or paste a full Cookie header';
    } else {
      this.statusText = 'Finish login in the web page; Cookie will be captured automatically';
      this.webCookieCaptured = false;
    }
  }

  private signInWithPassword(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Ability context is not ready';
      return;
    }
    if (this.signingIn) {
      return;
    }
    if (this.username.trim().length === 0) {
      this.statusText = 'Username cannot be empty';
      return;
    }
    if (this.password.length === 0) {
      this.statusText = 'Password cannot be empty';
      return;
    }

    this.signingIn = true;
    this.statusText = 'Signing in...';
    this.client.signIn(this.username.trim(), this.password).then((result: SignInResult) => {
      this.signingIn = false;
      if (!result.ok) {
        this.statusText = 'Sign in failed: ' + result.message;
        return;
      }

      ehCookieStore.save(context).then(() => {
        this.cookieInput = ehCookieStore.getEditableCookieHeader();
        this.statusText = result.message;
        this.onSignedIn();
      }).catch((error: Error) => {
        this.statusText = 'Signed in but Cookie save failed: ' + error.message;
      });
    }).catch((error: Error) => {
      this.signingIn = false;
      this.statusText = 'Sign in failed: ' + error.message;
    });
  }

  private prepareWebSignIn(): void {
    try {
      webview.WebCookieManager.configCookieSync(EhUrl.HOST_E, 'nw=1; path=/');
      webview.WebCookieManager.configCookieSync(EhUrl.HOST_EX, 'nw=1; path=/');
      webview.WebCookieManager.saveCookieSync();
    } catch (error) {
    }
    ehCookieStore.clear();
    this.webCookieCaptured = false;
    this.statusText = 'Web sign-in is ready; existing browser verification is kept';
  }

  private checkWebCookie(url: string): void {
    if (this.webCookieCaptured) {
      return;
    }

    const cookieHeader = collectWebCookies(url);
    if (cookieHeader.length > 0) {
      ehCookieStore.setCookieHeader(cookieHeader);
      this.cookieInput = ehCookieStore.getEditableCookieHeader();
    }
    if (!hasLoginCookie(cookieHeader)) {
      this.statusText = cookieHeader.length > 0 ? 'Web verification Cookie captured; waiting for login...' :
        'Waiting for web login...';
      return;
    }

    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Web Cookie found, but context is not ready';
      return;
    }

    this.webCookieCaptured = true;
    ehCookieStore.setCookieHeader(cookieHeader);
    ehCookieStore.save(context).then(() => {
      this.cookieInput = ehCookieStore.getEditableCookieHeader();
      this.statusText = 'Web Cookie captured';
      this.onSignedIn();
    }).catch((error: Error) => {
      this.webCookieCaptured = false;
      this.statusText = 'Web Cookie save failed: ' + error.message;
    });
  }

  private saveCookie(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Ability context is not ready';
      return;
    }

    const cookieHeader = this.buildCookieHeader();
    if (!this.validateCookieFields()) {
      return;
    }
    ehCookieStore.setCookieHeader(cookieHeader);
    ehCookieStore.save(context).then(() => {
      this.cookieInput = ehCookieStore.getEditableCookieHeader();
      this.statusText = ehCookieStore.hasCookies() ? 'Cookie saved' : 'Empty Cookie saved';
      if (ehCookieStore.hasCookies()) {
        this.onSignedIn();
      }
    }).catch((error: Error) => {
      this.statusText = 'Cookie save failed: ' + error.message;
    });
  }

  private buildCookieHeader(): string {
    const names: string[] = [];
    const values: string[] = [];
    absorbCookieHeaderText(this.cookieInput, names, values);
    if (this.memberId.trim().length > 0) {
      upsertCookiePair('ipb_member_id', this.memberId.trim(), names, values);
    }
    if (this.passHash.trim().length > 0) {
      upsertCookiePair('ipb_pass_hash', this.passHash.trim(), names, values);
    }
    if (this.igneous.trim().length > 0) {
      upsertCookiePair('igneous', this.igneous.trim(), names, values);
    }

    const parts: string[] = [];
    for (let i = 0; i < names.length; i++) {
      parts.push(names[i] + '=' + values[i]);
    }
    return parts.join('; ');
  }

  private syncCookieFieldsFromInput(value: string, showStatus: boolean): void {
    const parsed = parseCookieIdentity(value);
    let changed = false;
    if (parsed.memberId.length > 0) {
      this.memberId = parsed.memberId;
      changed = true;
    }
    if (parsed.passHash.length > 0) {
      this.passHash = parsed.passHash;
      changed = true;
    }
    if (parsed.igneous.length > 0) {
      this.igneous = parsed.igneous;
      changed = true;
    }
    if (showStatus) {
      this.statusText = changed ? 'Cookie fields detected' : 'No known Cookie fields detected';
    }
  }

  private validateCookieFields(): boolean {
    const id = this.memberId.trim();
    const hash = this.passHash.trim();
    if (id.length === 0) {
      this.statusText = 'ipb_member_id is empty';
      return false;
    }
    if (hash.length === 0) {
      this.statusText = 'ipb_pass_hash is empty';
      return false;
    }
    if (!checkIpbMemberId(id)) {
      this.statusText = 'ipb_member_id should contain digits only';
      return false;
    }
    if (!checkIpbPassHash(hash)) {
      this.statusText = 'ipb_pass_hash should be 32 lowercase letters or digits';
      return false;
    }
    return true;
  }

  private clearCookie(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      ehCookieStore.clear();
      this.cookieInput = '';
      this.statusText = 'Cookie cleared in memory';
      return;
    }

    ehCookieStore.clearPersisted(context).then(() => {
      this.cookieInput = '';
      this.memberId = '';
      this.passHash = '';
      this.igneous = '';
      this.statusText = 'Cookie cleared';
    }).catch((error: Error) => {
      this.statusText = 'Cookie clear failed: ' + error.message;
    });
  }

  build() {
    Column() {
      if (this.mode === SessionMode.Web) {
        this.WebSignInPanel()
      } else if (this.mode === SessionMode.Cookie) {
        this.CookieSignInPanel()
      } else {
        this.PasswordSignInPanel()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private PasswordSignInPanel() {
    Stack() {
      Scroll() {
        Column() {
          SignInMark({ label: 'EH' })

          Column() {
          TextInput({ text: this.username, placeholder: uiText('Username') })
              .height(46)
              .width('100%')
              .onChange((value: string) => {
                this.username = value;
              })
            TextInput({ text: this.password, placeholder: uiText('Password') })
              .height(46)
              .width('100%')
              .margin({ top: 10 })
              .type(InputType.Password)
              .onChange((value: string) => {
                this.password = value;
              })
          }
          .width('100%')
          .constraintSize({ maxWidth: 420 })
          .margin({ top: 8 })

          Text(uiStatusText(this.statusText))
            .fontSize(13)
            .fontColor('#0A6B45')
            .textAlign(TextAlign.Center)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .margin({ top: 12 })

          Blank()
            .layoutWeight(1)

          Row() {
            Button(uiText('Register'))
              .type(ButtonType.Normal)
              .fontColor('#2F6F8F')
              .backgroundColor(Color.Transparent)
              .layoutWeight(1)
            Button(this.signingIn ? uiText('Signing in...') : uiText('Sign in'))
              .type(ButtonType.Normal)
              .fontColor('#2F6F8F')
              .fontWeight(FontWeight.Bold)
              .backgroundColor(Color.Transparent)
              .layoutWeight(1)
              .enabled(!this.signingIn)
              .onClick(() => {
                this.signInWithPassword();
              })
          }
          .width('100%')
          .constraintSize({ maxWidth: 520 })
          .margin({ top: 22 })

          Text(uiText('Sign in via WebView'))
            .fontSize(14)
            .fontColor('#2F6F8F')
            .margin({ top: 8 })
            .onClick(() => {
              this.prepareWebSignIn();
              this.switchMode(SessionMode.Web);
            })
          Text(uiText('Sign in via Cookies'))
            .fontSize(14)
            .fontColor('#2F6F8F')
            .margin({ top: 10 })
            .onClick(() => {
              this.switchMode(SessionMode.Cookie);
            })
          Text(uiText('Guest mode'))
            .fontSize(14)
            .fontColor('#2F6F8F')
            .margin({ top: 10, bottom: 18 })
            .onClick(() => {
              this.onSignedIn();
            })
        }
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        .height('100%')
        .padding(20)
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private CookieSignInPanel() {
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
          this.switchMode(SessionMode.Password);
        })
        Text(uiText('Cookie Sign In'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#17202A')
          .margin({ left: 12 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12 })

      SignInMark({ label: 'CK' })
        .margin({ top: 6 })

      Scroll() {
        Column() {
          Text(uiText('Use this when password login needs captcha, or when importing an ExHentai session.'))
            .fontSize(13)
            .fontColor('#475467')
            .lineHeight(20)
            .width('100%')
            .constraintSize({ maxWidth: 420 })

          TextInput({ text: this.memberId, placeholder: 'ipb_member_id' })
            .height(46)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .margin({ top: 14 })
            .onChange((value: string) => {
              this.memberId = value;
            })
          TextInput({ text: this.passHash, placeholder: 'ipb_pass_hash' })
            .height(46)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .margin({ top: 10 })
            .onChange((value: string) => {
              this.passHash = value;
            })
          TextInput({ text: this.igneous, placeholder: 'igneous' })
            .height(46)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .margin({ top: 10 })
            .onChange((value: string) => {
              this.igneous = value;
            })
          TextArea({ text: this.cookieInput, placeholder: uiText('Full Cookie header') })
            .height(116)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .fontSize(13)
            .margin({ top: 12 })
            .onChange((value: string) => {
              this.cookieInput = value;
              this.syncCookieFieldsFromInput(value, true);
            })

          Text(uiStatusText(this.statusText))
            .fontSize(13)
            .fontColor('#0A6B45')
            .textAlign(TextAlign.Center)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .margin({ top: 12 })
        }
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 20 })
      }
      .layoutWeight(1)
      .width('100%')

      Row() {
        Button(uiText('Clear'))
          .type(ButtonType.Normal)
          .fontColor('#2F6F8F')
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onClick(() => {
            this.clearCookie();
          })
        Button(uiText('OK'))
          .type(ButtonType.Normal)
          .fontColor('#2F6F8F')
          .fontWeight(FontWeight.Bold)
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onClick(() => {
            this.saveCookie();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 12 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private WebSignInPanel() {
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
          this.switchMode(SessionMode.Password);
        })
        Text(uiStatusText(this.statusText))
          .fontSize(13)
          .fontColor('#667085')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(44)
      .padding({ left: 12, right: 12 })
      .backgroundColor(Color.White)

      Web({ src: this.webUrl, controller: this.webController })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onPageEnd((event: OnPageEndEvent) => {
          this.checkWebCookie(event.url);
        })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct SettingsScene {
  @State panel: SettingsPanel = SettingsPanel.Main;
  @State signedIn: boolean = ehCookieStore.hasCookies();
  @State statusText: string = '';
  @State themeName: string = 'Light';
  @State settingEntries: SettingEntry[] = defaultSettingEntries();
  @State optionPickerOpen: boolean = false;
  @State optionKey: string = '';
  @State optionTitle: string = '';
  @State optionSummary: string = '';
  @State optionValue: string = '';
  @State optionOptions: string[] = [];
  @State webViewUrl: string = '';
  @State webViewTitle: string = '';
  @State filterRules: FilterRule[] = [];
  @State filterNewText: string = '';
  @State filterNewMode: number = FILTER_MODE_TITLE;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  private webViewController: webview.WebviewController = new webview.WebviewController();
  private client: EhHttpClient = new EhHttpClient();
  onMenu: () => void = () => {};
  onSignedIn: () => void = () => {};

  aboutToAppear(): void {
    setActiveBackHandler(() => this.handleSystemBack());
    const context = getAbilityContext();
    if (context !== undefined) {
      ehCookieStore.load(context).then(() => {
        this.signedIn = ehCookieStore.hasCookies();
        this.statusText = this.signedIn ? 'Cookie session loaded' : 'Tourist mode';
      }).catch((error: Error) => {
        this.statusText = 'Cookie load failed: ' + error.message;
      });
      ehSettingsStore.load(context).then(() => {
        this.settingEntries = ehSettingsStore.getEntries();
        this.themeName = settingEntryValue(this.settingEntries, 'theme', 'Light');
      }).catch((error: Error) => {
        this.statusText = 'Settings load failed: ' + error.message;
      });
    } else {
      this.signedIn = ehCookieStore.hasCookies();
      this.statusText = this.signedIn ? 'Cookie session loaded' : 'Tourist mode';
      this.settingEntries = ehSettingsStore.getEntries();
      this.themeName = settingEntryValue(this.settingEntries, 'theme', 'Light');
    }
  }

  aboutToDisappear(): void {
    setActiveBackHandler(null);
  }

  private handleSystemBack(): boolean {
    if (this.optionPickerOpen) {
      this.optionPickerOpen = false;
      return true;
    }
    if (this.panel !== SettingsPanel.Main) {
      this.closePanel();
      return true;
    }
    return false;
  }

  private openPanel(panel: SettingsPanel): void {
    this.optionPickerOpen = false;
    this.panel = panel;
  }

  private closePanel(): void {
    this.optionPickerOpen = false;
    this.panel = SettingsPanel.Main;
    this.signedIn = ehCookieStore.hasCookies();
  }

  private signOut(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      ehCookieStore.clear();
      this.signedIn = false;
      this.statusText = 'Signed out in memory';
      return;
    }

    ehCookieStore.clearPersisted(context).then(() => {
      this.signedIn = false;
      this.statusText = 'Signed out';
    }).catch((error: Error) => {
      this.statusText = 'Sign out failed: ' + error.message;
    });
  }

  private cycleTheme(): void {
    this.saveSettingValue('theme', nextOption(this.themeName, ['Light', 'Dark', 'Black']));
    this.themeName = settingEntryValue(this.settingEntries, 'theme', 'Light');
    this.statusText = 'Theme preference saved: ' + this.themeName;
  }

  private saveSettingValue(key: string, value: string): void {
    if (key === 'proxy_port' && value.length > 0 && !isValidProxyPortText(value)) {
      this.statusText = 'Invalid proxy port: ' + value;
      return;
    }
    ehSettingsStore.setValue(key, value);
    this.settingEntries = ehSettingsStore.getEntries();
    this.themeName = settingEntryValue(this.settingEntries, 'theme', 'Light');
    if (key === this.optionKey) {
      this.optionValue = value;
    }
    if (key === 'app_language') {
      notifyLanguageChanged();
    }
    if (key === 'enable_secure') {
      applyWindowPrivacyMode(value === 'On', (status: string) => {
        this.statusText = status;
      });
    }
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = isNetworkSettingKey(key) ? 'Saved network setting in memory: ' + key + ' = ' + value +
        '. Refresh Homepage or run Network diagnostics.' : 'Saved in memory: ' + key + ' = ' + value;
      return;
    }
    ehSettingsStore.save(context).then(() => {
      this.statusText = isNetworkSettingKey(key) ? 'Saved network setting: ' + key + ' = ' + value +
        '. Refresh Homepage or run Network diagnostics.' : 'Saved: ' + key + ' = ' + value;
    }).catch((error: Error) => {
      this.statusText = 'Save failed: ' + error.message;
    });
  }

  private cycleSetting(row: SettingsRowItem): void {
    if (row.key === undefined) {
      this.statusText = row.title + ' is not available';
      return;
    }
    if (this.runSettingAction(row.key)) {
      return;
    }
    if (row.options === undefined || row.options.length === 0) {
      this.statusText = row.title + ' is not migrated yet';
      return;
    }
    if (row.type === 'switch') {
      this.saveSettingValue(row.key, row.value === 'On' ? 'Off' : 'On');
      return;
    }
    this.openOptionPicker(row);
  }

  private openOptionPicker(row: SettingsRowItem): void {
    if (row.key === undefined || row.options === undefined || row.options.length === 0) {
      this.statusText = row.title + ' is not available';
      return;
    }
    this.optionKey = row.key;
    this.optionTitle = row.title;
    this.optionSummary = row.summary;
    this.optionValue = settingEntryValue(this.settingEntries, row.key, row.value);
    this.optionOptions = cloneStringOptions(row.options);
    this.optionPickerOpen = true;
    this.statusText = '';
  }

  private closeOptionPicker(): void {
    this.optionPickerOpen = false;
    this.optionKey = '';
    this.optionTitle = '';
    this.optionSummary = '';
    this.optionValue = '';
    this.optionOptions = [];
  }

  private selectOptionValue(value: string): void {
    if (this.optionKey.length === 0) {
      this.statusText = 'No setting is selected';
      return;
    }
    this.saveSettingValue(this.optionKey, value);
    this.closeOptionPicker();
  }

  private runSettingAction(key: string): boolean {
    if (key === 'identity_cookie') {
      this.openPanel(SettingsPanel.Session);
      return true;
    }
    if (key === 'network_diagnostics') {
      this.runNetworkDiagnostics();
      return true;
    }
    if (key === 'restore_download_items') {
      this.restoreDownloadItems();
      return true;
    }
    if (key === 'clean_redundancy') {
      this.scanDownloadRedundancy();
      return true;
    }
    if (key === 'clear_download_path_cache') {
      this.refreshDownloadPathCache();
      return true;
    }
    if (key === 'clear_memory_cache') {
      this.clearMemoryCache();
      return true;
    }
    if (key === 'about_analytics') {
      this.statusText = 'Analytics is only recorded when enabled. The HarmonyOS port currently keeps this as a local preference.';
      return true;
    }
    if (key === 'declaration') {
      this.statusText = 'EhViewer_CN_SXJ HarmonyOS port keeps the original project notice and uses migrated local services where available.';
      return true;
    }
    if (key === 'author') {
      this.statusText = 'Original project: xiaojieonly/Ehviewer_CN_SXJ. HarmonyOS migration continues from the local workspace.';
      return true;
    }
    if (key === 'latest_release') {
      this.statusText = 'Latest release: https://github.com/xiaojieonly/Ehviewer_CN_SXJ/releases';
      return true;
    }
    if (key === 'issue_help') {
      this.statusText = 'Issue help: https://github.com/xiaojieonly/Ehviewer_CN_SXJ/issues';
      return true;
    }
    if (key === 'license') {
      this.statusText = 'License: GPL-compatible open-source project. Keep source disclosure for redistributed builds.';
      return true;
    }
    if (key === 'version') {
      this.statusText = 'Version: HarmonyOS port target 6.1.0 / API 6.1.1 (24), app version 0.1.3.';
      return true;
    }
    if (key === 'check_for_updates') {
      this.statusText = 'Update check uses the release page for now: https://github.com/xiaojieonly/Ehviewer_CN_SXJ/releases';
      return true;
    }
    if (key === 'donate') {
      this.statusText = 'Donate entry is retained from the original app; payment integration is not migrated yet.';
      return true;
    }
    if (key === 'dump_logcat') {
      this.statusText = 'Android logcat export has no direct HarmonyOS equivalent yet. Crash/log persistence settings are available above.';
      return true;
    }
    if (key === 'u_config') {
      if (!this.signedIn) {
        this.statusText = 'UConfig requires a signed-in session';
        return true;
      }
      const isEx = ehSettingsStore.getValue('gallery_site', 'E-Hentai') === 'ExHentai';
      this.webViewUrl = isEx ? 'https://exhentai.org/uconfig.php' : 'https://e-hentai.org/uconfig.php';
      this.webViewTitle = 'UConfig';
      this.openPanel(SettingsPanel.WebView);
      return true;
    }
    if (key === 'my_tags') {
      if (!this.signedIn) {
        this.statusText = 'My Tags requires a signed-in session';
        return true;
      }
      const isEx = ehSettingsStore.getValue('gallery_site', 'E-Hentai') === 'ExHentai';
      this.webViewUrl = isEx ? 'https://exhentai.org/mytags' : 'https://e-hentai.org/mytags';
      this.webViewTitle = 'My Tags';
      this.openPanel(SettingsPanel.WebView);
      return true;
    }
    if (key === 'filter' || key === 'blacklist') {
      const context = getAbilityContext();
      if (context !== undefined) {
        ehFilterStore.load(context).then(() => {
          this.filterRules = ehFilterStore.getRules();
          this.openPanel(SettingsPanel.Filter);
        }).catch((error: Error) => {
          this.filterRules = ehFilterStore.getRules();
          this.openPanel(SettingsPanel.Filter);
          this.statusText = 'Filter load warning: ' + error.message;
        });
      } else {
        this.filterRules = ehFilterStore.getRules();
        this.openPanel(SettingsPanel.Filter);
      }
      return true;
    }
    if (key === 'pattern_protection') {
      this.runBiometricLock();
      return true;
    }
    if (key === 'export_data') {
      this.exportData();
      return true;
    }
    if (key === 'import_data') {
      this.importData();
      return true;
    }
    if (key === 'wifi_transfer') {
      this.statusText = settingMigrationMessage(key);
      return true;
    }
    return false;
  }

  private runBiometricLock(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Biometric lock requires an ability context';
      return;
    }
    const enabled = ehSettingsStore.getValue('pattern_protection', 'Off') === 'On';
    const next = enabled ? 'Off' : 'On';
    ehSettingsStore.setValue('pattern_protection', next);
    this.settingEntries = ehSettingsStore.getEntries();
    ehSettingsStore.save(context).catch((error: Error) => {
      this.statusText = 'Save failed: ' + error.message;
    });
    this.statusText = next === 'On'
      ? 'Biometric lock enabled: app will prompt for fingerprint/face on resume'
      : 'Biometric lock disabled';
  }

  private exportData(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Export needs an ability context';
      return;
    }
    this.statusText = 'Preparing export...';
    const now = new Date();
    const stamp = now.getFullYear().toString() +
      padTwo(now.getMonth() + 1) + padTwo(now.getDate()) + '_' +
      padTwo(now.getHours()) + padTwo(now.getMinutes()) + padTwo(now.getSeconds());
    const fileName = 'ehviewer_backup_' + stamp + '.json';

    Promise.all([
      ehSettingsStore.load(context),
      ehHistoryStore.load(context),
      ehDownloadStore.load(context),
      ehFilterStore.load(context)
    ]).then(() => {
      const bundle: EhBackupBundle = {
        version: 1,
        exportedAt: now.toISOString(),
        cookies: ehCookieStore.getCookieHeader(),
        settings: ehSettingsStore.getEntries(),
        history: ehHistoryStore.getItems(),
        downloadItems: ehDownloadStore.getItems(),
        downloadLabels: ehDownloadStore.getLabels(),
        filterRules: ehFilterStore.getRules()
      };
      const json = JSON.stringify(bundle, null, 2);

      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [fileName];
      const documentPicker = new picker.DocumentViewPicker(context);
      documentPicker.save(saveOptions).then((uris: string[]) => {
        if (uris.length === 0) {
          this.statusText = 'Export cancelled';
          return;
        }
        const uri = uris[0];
        try {
          const file = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
          fs.writeSync(file.fd, json);
          fs.closeSync(file.fd);
          this.statusText = 'Export saved: ' + uri;
        } catch (error) {
          this.statusText = 'Export write failed: ' + String(error);
        }
      }).catch((error: Error) => {
        this.statusText = 'Export picker failed: ' + error.message;
      });
    }).catch((error: Error) => {
      this.statusText = 'Export load failed: ' + error.message;
    });
  }

  private importData(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Import needs an ability context';
      return;
    }
    this.statusText = 'Select backup file to import...';

    const selectOptions = new picker.DocumentSelectOptions();
    const documentPicker = new picker.DocumentViewPicker(context);
    documentPicker.select(selectOptions).then((uris: string[]) => {
      if (uris.length === 0) {
        this.statusText = 'Import cancelled';
        return;
      }
      const uri = uris[0];
      try {
        const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        const stat = fs.statSync(file.fd);
        const buf = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buf);
        fs.closeSync(file.fd);
        const decoder = util.TextDecoder.create('utf-8');
        const json = decoder.decodeToString(new Uint8Array(buf));
        const bundle = JSON.parse(json) as EhBackupBundle;

        if (typeof bundle.version !== 'number') {
          this.statusText = 'Import failed: not a valid EhViewer backup file';
          return;
        }

        const saves: Promise<void>[] = [];

        if (typeof bundle.cookies === 'string' && bundle.cookies.length > 0) {
          ehCookieStore.setCookieHeader(bundle.cookies);
          saves.push(ehCookieStore.save(context));
          this.signedIn = ehCookieStore.hasCookies();
        }

        let languageChanged = false;
        if (Array.isArray(bundle.settings)) {
          for (let i = 0; i < bundle.settings.length; i++) {
            const e = bundle.settings[i] as SettingEntry;
            if (typeof e.key === 'string' && typeof e.value === 'string') {
              if (e.key === 'app_language' && ehSettingsStore.getValue('app_language', 'System') !== e.value) {
                languageChanged = true;
              }
              ehSettingsStore.setValue(e.key, e.value);
            }
          }
          saves.push(ehSettingsStore.save(context));
          this.settingEntries = ehSettingsStore.getEntries();
          this.themeName = settingEntryValue(this.settingEntries, 'theme', 'Light');
          if (languageChanged) {
            notifyLanguageChanged();
          }
        }

        if (Array.isArray(bundle.history)) {
          for (let i = 0; i < bundle.history.length; i++) {
            ehHistoryStore.addGallery(bundle.history[i] as GalleryInfo);
          }
          saves.push(ehHistoryStore.save(context));
        }

        if (Array.isArray(bundle.downloadLabels)) {
          for (let i = 0; i < bundle.downloadLabels.length; i++) {
            const lbl = bundle.downloadLabels[i] as DownloadLabel;
            if (typeof lbl.label === 'string') {
              ehDownloadStore.addLabel(lbl.label);
            }
          }
        }

        if (Array.isArray(bundle.downloadItems)) {
          for (let i = 0; i < bundle.downloadItems.length; i++) {
            const dl = bundle.downloadItems[i] as DownloadInfo;
            if (typeof dl.gid === 'number' && dl.gid > 0 && typeof dl.token === 'string') {
              ehDownloadStore.addGallery(dl as GalleryInfo, typeof dl.label === 'string' ? dl.label : '');
            }
          }
          saves.push(ehDownloadStore.save(context));
        }

        if (Array.isArray(bundle.filterRules)) {
          for (let i = 0; i < bundle.filterRules.length; i++) {
            const r = bundle.filterRules[i] as FilterRule;
            if (typeof r.text === 'string' && typeof r.mode === 'number') {
              ehFilterStore.addRule(r.mode, r.text);
            }
          }
          saves.push(ehFilterStore.save(context));
          this.filterRules = ehFilterStore.getRules();
        }

        Promise.all(saves).then(() => {
          this.statusText = 'Import complete';
        }).catch((error: Error) => {
          this.statusText = 'Import save failed: ' + error.message;
        });

      } catch (error) {
        this.statusText = 'Import failed: ' + String(error);
      }
    }).catch((error: Error) => {
      this.statusText = 'Import picker failed: ' + error.message;
    });
  }

  private restoreDownloadItems(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Restore download items needs an ability context';
      return;
    }
    this.statusText = 'Scanning downloaded folders...';
    ehDownloadStore.load(context).then(() => {
      const restored: RestoredDownloadGallery[] = ehDownloadFileStore.restoreDownloadedGalleries(context);
      let added = 0;
      let updated = 0;
      let totalBytes = 0;
      for (let i = 0; i < restored.length; i++) {
        const item = restored[i];
        const existed = ehDownloadStore.contains(item.gallery.gid);
        if (ehDownloadStore.addGallery(item.gallery, '') !== null) {
          const total = Math.max(item.total, item.finished);
          ehDownloadStore.setProgress(item.gallery.gid, item.finished, total, item.finished);
          ehDownloadStore.setStorage(item.gallery.gid, item.directory, item.fileSize);
          ehDownloadStore.setState(item.gallery.gid,
            total > 0 && item.finished >= total ? DownloadState.Finish : DownloadState.None);
          totalBytes += item.fileSize;
          if (existed) {
            updated++;
          } else {
            added++;
          }
        }
      }
      return ehDownloadStore.save(context).then(() => {
        this.statusText = 'Restored downloads: ' + added.toString() + ' added, ' + updated.toString() +
          ' updated, ' + downloadSizeText(totalBytes) + '.';
      });
    }).catch((error: Error) => {
      this.statusText = 'Restore downloads failed: ' + error.message;
    });
  }

  private scanDownloadRedundancy(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Clean redundancy needs an ability context';
      return;
    }
    ehDownloadStore.load(context).then(() => {
      const items = ehDownloadStore.getItems();
      const keepGids: number[] = [];
      for (let i = 0; i < items.length; i++) {
        keepGids.push(items[i].gid);
      }
      const result: DownloadDirectoryScanResult = ehDownloadFileStore.scanRedundantDirectories(context, keepGids);
      this.statusText = 'Redundancy scan: ' + result.directories.toString() + ' folders, ' +
        result.files.toString() + ' images, ' + downloadSizeText(result.bytes) +
        '. Restore downloads before deleting any folder manually.';
    }).catch((error: Error) => {
      this.statusText = 'Redundancy scan failed: ' + error.message;
    });
  }

  private refreshDownloadPathCache(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Download path cache needs an ability context';
      return;
    }
    ehDownloadStore.load(context).then(() => {
      const items = ehDownloadStore.getItems();
      let updated = 0;
      let totalBytes = 0;
      for (let i = 0; i < items.length; i++) {
        const size = ehDownloadFileStore.directorySize(context, items[i]);
        if (size > 0) {
          ehDownloadStore.setStorage(items[i].gid, ehDownloadFileStore.galleryDirectory(context, items[i]), size);
          totalBytes += size;
          updated++;
        }
      }
      return ehDownloadStore.save(context).then(() => {
        this.statusText = 'Download path cache refreshed: ' + updated.toString() + ' items, ' +
          downloadSizeText(totalBytes) + '.';
      });
    }).catch((error: Error) => {
      this.statusText = 'Refresh download path cache failed: ' + error.message;
    });
  }

  private clearMemoryCache(): void {
    const pageCount = galleryPageCache.clear();
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Cleared page cache: ' + pageCount.toString() + ' entries.';
      return;
    }
    const imageResult: CacheClearResult = readerImageCache.clear(context);
    this.statusText = 'Cleared cache: ' + pageCount.toString() + ' pages, ' +
      imageResult.files.toString() + ' images, ' + downloadSizeText(imageResult.bytes) + '.';
  }

  private runNetworkDiagnostics(): void {
    this.statusText = 'Running network diagnostics...';
    this.client.runNetworkDiagnostics().then((results: NetworkDiagnosticResult[]) => {
      this.statusText = formatNetworkDiagnostics(results);
    }).catch((error: Error) => {
      this.statusText = 'Network diagnostics failed: ' + error.message;
    });
  }

  private addFilterRule(): void {
    const text = this.filterNewText.trim();
    if (text.length === 0) {
      this.statusText = 'Enter a filter text first';
      return;
    }
    const added = ehFilterStore.addRule(this.filterNewMode, text);
    if (!added) {
      this.statusText = 'Rule already exists: ' + text;
      return;
    }
    this.filterRules = ehFilterStore.getRules();
    this.filterNewText = '';
    this.statusText = 'Filter rule added: ' + text;
    this.saveFilterRules();
  }

  private removeFilterRule(id: number): void {
    ehFilterStore.removeRule(id);
    this.filterRules = ehFilterStore.getRules();
    this.statusText = 'Filter rule removed';
    this.saveFilterRules();
  }

  private toggleFilterRule(id: number): void {
    ehFilterStore.toggleRule(id);
    this.filterRules = ehFilterStore.getRules();
    this.saveFilterRules();
  }

  private saveFilterRules(): void {
    const context = getAbilityContext();
    if (context !== undefined) {
      ehFilterStore.save(context).catch((error: Error) => {
        this.statusText = 'Filter save failed: ' + error.message;
      });
    }
  }


  build() {
    if (this.optionPickerOpen) {
      SettingsOptionPanel({
        title: this.optionTitle,
        summary: this.optionSummary,
        value: this.optionValue,
        options: this.optionOptions,
        onBack: () => {
          this.closeOptionPicker();
        },
        onSelect: (value: string) => {
          this.selectOptionValue(value);
        }
      })
    } else if (this.panel === SettingsPanel.Filter) {
      FilterPanel({
        rules: this.filterRules,
        newText: this.filterNewText,
        newMode: this.filterNewMode,
        statusText: this.statusText,
        onBack: () => {
          this.closePanel();
        },
        onNewTextChange: (text: string) => {
          this.filterNewText = text;
        },
        onNewModeChange: (mode: number) => {
          this.filterNewMode = mode;
        },
        onAdd: () => {
          this.addFilterRule();
        },
        onRemove: (id: number) => {
          this.removeFilterRule(id);
        },
        onToggle: (id: number) => {
          this.toggleFilterRule(id);
        }
      })
    } else if (this.panel === SettingsPanel.WebView) {
      Column() {
        SettingsSubToolbar({
          title: uiText(this.webViewTitle),
          onBack: () => {
            this.closePanel();
          }
        })
        Web({ src: this.webViewUrl, controller: this.webViewController })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .width('100%')
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    } else if (this.panel === SettingsPanel.Session) {
      Column() {
        SettingsSubToolbar({
          title: uiText('Sign in'),
          onBack: () => {
            this.closePanel();
          }
        })
        SessionScene({
          onSignedIn: () => {
            this.signedIn = ehCookieStore.hasCookies();
            this.statusText = this.signedIn ? 'Signed in' : 'Guest mode';
            this.closePanel();
            this.onSignedIn();
          }
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    } else if (this.panel === SettingsPanel.Migration) {
      Column() {
        SettingsSubToolbar({
          title: uiText('Migration'),
          onBack: () => {
            this.closePanel();
          }
        })
        MigrationScene()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    } else if (this.panel === SettingsPanel.Main) {
      SettingsHomePanel({
        signedIn: this.signedIn,
        statusText: this.statusText,
        onMenu: this.onMenu,
        onOpen: (panel: SettingsPanel) => {
          this.openPanel(panel);
        }
      })
    } else {
      SettingsDetailPanel({
        panel: this.panel,
        signedIn: this.signedIn,
        statusText: this.statusText,
        themeName: this.themeName,
        settingEntries: this.settingEntries,
        onBack: () => {
          this.closePanel();
        },
        onOpenSession: () => {
          this.openPanel(SettingsPanel.Session);
        },
        onOpenMigration: () => {
          this.openPanel(SettingsPanel.Migration);
        },
        onSignOut: () => {
          this.signOut();
        },
        onCycleTheme: () => {
          this.cycleTheme();
        },
        onCycleSetting: (row: SettingsRowItem) => {
          this.cycleSetting(row);
        },
        onSetSetting: (key: string, value: string) => {
          this.saveSettingValue(key, value);
        }
      })
    }
  }
}

@Component
export struct SettingsHomePanel {
  @Prop signedIn: boolean = false;
  @Prop statusText: string = '';
  onMenu: () => void = () => {};
  onOpen: (panel: SettingsPanel) => void = () => {};

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
        .onClick(() => {
          this.onMenu();
        })
        Column() {
          Text(uiText('Settings'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
          Text(this.signedIn ? uiText('Signed in') : uiText('Guest mode'))
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.7)')
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })
        Text(this.signedIn ? 'EH' : '?')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#2F6F8F')
          .textAlign(TextAlign.Center)
          .width(36)
          .height(36)
          .backgroundColor(Color.White)
          .borderRadius(18)
      }
      .width('100%')
      .height(60)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor('#2F6F8F')

      if (this.statusText.length > 0) {
        Row() {
          Text(uiStatusText(this.statusText))
            .fontSize(11)
            .fontColor('#40566F')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(28)
        .padding({ left: 14, right: 14 })
        .backgroundColor('#EAF3F8')
      }

      List({ space: 8 }) {
        ForEach(SETTINGS_HEADERS, (item: SettingsHeaderItem) => {
          ListItem() {
            SettingsHeaderRow({
              item: item,
              onTap: () => {
                this.onOpen(item.panel);
              }
            })
          }
        }, (item: SettingsHeaderItem) => item.panel)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 10, bottom: 14 })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct SettingsHeaderRow {
  item: SettingsHeaderItem = { panel: SettingsPanel.Eh, title: '', icon: '', summary: '' };
  onTap: () => void = () => {};

  build() {
    Row() {
      Text(this.item.icon)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .width(36)
        .height(36)
        .backgroundColor('#2F6F8F')
        .borderRadius(18)
        .padding({ top: 9 })
      Column() {
        Text(uiText(this.item.title))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#17202A')
        Text(uiText(this.item.summary))
          .fontSize(12)
          .fontColor('#667085')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
      Text('>')
        .fontSize(16)
        .fontColor('#98A2B3')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Color.White)
    .borderRadius(6)
    .onClick(() => {
      this.onTap();
    })
  }
}

@Component
export struct SettingsDetailPanel {
  panel: SettingsPanel = SettingsPanel.Eh;
  @Prop signedIn: boolean = false;
  @Prop statusText: string = '';
  @Prop themeName: string = 'Light';
  @Prop settingEntries: SettingEntry[] = [];
  onBack: () => void = () => {};
  onOpenSession: () => void = () => {};
  onOpenMigration: () => void = () => {};
  onSignOut: () => void = () => {};
  onCycleTheme: () => void = () => {};
  onCycleSetting: (row: SettingsRowItem) => void = () => {};
  onSetSetting: (key: string, value: string) => void = () => {};

  build() {
    Column() {
      SettingsSubToolbar({
        title: uiText(settingsPanelTitle(this.panel)),
        onBack: this.onBack
      })

      if (this.statusText.length > 0) {
        Text(uiStatusText(this.statusText))
          .fontSize(12)
          .fontColor('#0A6B45')
          .width('100%')
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor('#F0FBF6')
      }

      List({ space: 8 }) {
        if (this.panel === SettingsPanel.Eh) {
          ListItem() {
            SettingsActionRow({
              title: this.signedIn ? uiText('Account session') : uiText('Sign in'),
              summary: this.signedIn ? uiText('Cookie session is available. Open to replace or inspect cookies.') :
                uiText('Open password, WebView or Cookie sign-in. This matches the original startup sign-in flow.'),
              value: this.signedIn ? uiText('Signed in') : uiText('Tourist'),
              onTap: this.onOpenSession
            })
          }
          ListItem() {
            SettingsActionRow({
              title: uiText('Sign out'),
              summary: uiText('Clear the persisted identity cookies'),
              value: this.signedIn ? uiText('Available') : uiText('No session'),
              isEnabled: this.signedIn,
              onTap: this.onSignOut
            })
          }
          ForEach(settingsRowsForPanel(this.panel, this.themeName, this.settingEntries), (row: SettingsRowItem) => {
            ListItem() {
              SettingsStaticRow({
                row: row,
                onTextChange: (key: string, value: string) => {
                  this.onSetSetting(key, value);
                },
                onSwitchChange: (key: string, isOn: boolean) => {
                  this.onSetSetting(key, isOn ? 'On' : 'Off');
                },
                onOptionSelect: (key: string, value: string) => {
                  this.onSetSetting(key, value);
                },
                onTap: () => {
                  this.onCycleSetting(row);
                }
              })
            }
          }, (row: SettingsRowItem) => settingsRowRenderKey(row))
          ListItem() {
            SettingsActionRow({
              title: uiText('Theme'),
              summary: uiText('Original app cycles Light, Dark and Black from drawer/footer and Settings'),
              value: uiValue(this.themeName),
              onTap: this.onCycleTheme
            })
          }
        } else if (this.panel === SettingsPanel.About) {
          ForEach(settingsRowsForPanel(this.panel, this.themeName, this.settingEntries), (row: SettingsRowItem) => {
            ListItem() {
              SettingsStaticRow({
                row: row,
                onTextChange: (key: string, value: string) => {
                  this.onSetSetting(key, value);
                },
                onSwitchChange: (key: string, isOn: boolean) => {
                  this.onSetSetting(key, isOn ? 'On' : 'Off');
                },
                onOptionSelect: (key: string, value: string) => {
                  this.onSetSetting(key, value);
                },
                onTap: () => {
                  this.onCycleSetting(row);
                }
              })
            }
          }, (row: SettingsRowItem) => settingsRowRenderKey(row))
          ListItem() {
            SettingsActionRow({
              title: uiText('Migration status'),
              summary: uiText('Open the HarmonyOS port checklist'),
              value: uiText('Open'),
              onTap: this.onOpenMigration
            })
          }
        } else {
          ForEach(settingsRowsForPanel(this.panel, this.themeName, this.settingEntries), (row: SettingsRowItem) => {
            ListItem() {
              SettingsStaticRow({
                row: row,
                onTextChange: (key: string, value: string) => {
                  this.onSetSetting(key, value);
                },
                onSwitchChange: (key: string, isOn: boolean) => {
                  this.onSetSetting(key, isOn ? 'On' : 'Off');
                },
                onOptionSelect: (key: string, value: string) => {
                  this.onSetSetting(key, value);
                },
                onTap: () => {
                  this.onCycleSetting(row);
                }
              })
            }
          }, (row: SettingsRowItem) => settingsRowRenderKey(row))
        }

      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 10, bottom: 14 })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct SettingsOptionPanel {
  title: string = '';
  summary: string = '';
  value: string = '';
  options: string[] = [];
  onBack: () => void = () => {};
  onSelect: (value: string) => void = () => {};

  build() {
    Column() {
      SettingsSubToolbar({
        title: this.title,
        onBack: this.onBack
      })

      if (this.summary.length > 0) {
        Text(uiText(this.summary))
          .fontSize(12)
          .fontColor('#667085')
          .lineHeight(18)
          .width('100%')
          .padding({ left: 14, right: 14, top: 12, bottom: 10 })
          .backgroundColor(Color.White)
      }

      List({ space: 8 }) {
        ForEach(this.options, (option: string) => {
          ListItem() {
            Row() {
              Text(uiValue(option))
                .fontSize(15)
                .fontWeight(option === this.value ? FontWeight.Medium : FontWeight.Regular)
                .fontColor('#17202A')
                .layoutWeight(1)
              if (option === this.value) {
                Text(uiText('Selected'))
                  .fontSize(12)
                  .fontColor('#2F6F8F')
              }
            }
            .width('100%')
            .padding(14)
            .backgroundColor(Color.White)
            .borderRadius(6)
            .onClick(() => {
              this.onSelect(option);
            })
          }
        }, (option: string) => option)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 10, bottom: 14 })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct SettingsSubToolbar {
  title: string = '';
  onBack: () => void = () => {};

  build() {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(38)
      .height(38)
      .backgroundColor('rgba(255,255,255,0.15)')
      .onClick(() => {
        this.onBack();
      })
      Text(uiText(this.title))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .margin({ left: 12 })
        .layoutWeight(1)
    }
    .width('100%')
    .height(60)
    .padding({ left: 14, right: 14 })
    .backgroundColor('#2F6F8F')
  }
}

@Component
export struct SettingsActionRow {
  title: string = '';
  summary: string = '';
  value: string = '';
  isEnabled: boolean = true;
  onTap: () => void = () => {};

  build() {
    Row() {
      Column() {
        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isEnabled ? '#17202A' : '#98A2B3')
        Text(this.summary)
          .fontSize(12)
          .fontColor('#667085')
          .lineHeight(18)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(this.value)
        .fontSize(12)
        .fontColor(this.isEnabled ? '#2F6F8F' : '#98A2B3')
        .margin({ left: 12 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Color.White)
    .borderRadius(6)
    .onClick(() => {
      if (this.isEnabled) {
        this.onTap();
      }
    })
  }
}

@Component
export struct SettingsStaticRow {
  row: SettingsRowItem = { title: '', summary: '', value: '', type: '' };
  onTap: () => void = () => {};
  onTextChange: (key: string, value: string) => void = () => {};
  onSwitchChange: (key: string, isOn: boolean) => void = () => {};
  onOptionSelect: (key: string, value: string) => void = () => {};

  build() {
    Row() {
      Column() {
        Text(uiText(this.row.title))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#17202A')
        Text(uiText(this.row.summary))
          .fontSize(12)
          .fontColor('#667085')
          .lineHeight(18)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.row.type === 'input') {
        TextInput({ text: this.row.value, placeholder: this.row.summary })
          .width(150)
          .height(38)
          .fontSize(13)
          .margin({ left: 12 })
          .onChange((value: string) => {
            if (this.row.key !== undefined) {
              this.onTextChange(this.row.key, value.trim());
            }
          })
      } else if (this.row.type === 'switch') {
        Row() {
          Text(this.row.value === 'On' ? uiText('On') : uiText('Off'))
            .fontSize(12)
            .fontColor(this.row.value === 'On' ? '#2F6F8F' : '#98A2B3')
            .margin({ right: 8 })
          Toggle({ type: ToggleType.Switch, isOn: this.row.value === 'On' })
            .selectedColor('#2F6F8F')
            .switchPointColor(Color.White)
            .onChange((isOn: boolean) => {
              if (this.row.key !== undefined) {
                this.onSwitchChange(this.row.key, isOn);
              }
            })
        }
        .alignItems(VerticalAlign.Center)
        .margin({ left: 12 })
      } else if (this.row.type === 'list' && this.row.options !== undefined && this.row.options.length > 0) {
        Select(buildSelectOptions(this.row.options))
          .selected(optionIndex(this.row.options, this.row.value))
          .value(uiValue(this.row.value))
          .font({ size: 13 })
          .fontColor('#2F6F8F')
          .selectedOptionBgColor('#EDF7FA')
          .selectedOptionFontColor('#2F6F8F')
          .optionBgColor(Color.White)
          .optionFont({ size: 13 })
          .margin({ left: 8 })
          .onSelect((index: number) => {
            if (this.row.key !== undefined && this.row.options !== undefined) {
              this.onOptionSelect(this.row.key, this.row.options[index]);
            }
          })
      } else {
        Button(settingsRowActionText(this.row))
          .height(34)
          .fontSize(12)
          .fontColor('#40566F')
          .backgroundColor('#F2F4F7')
          .margin({ left: 12 })
          .onClick(() => {
            this.onTap();
          })
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Color.White)
    .borderRadius(6)
    .onClick(() => {
      if (this.row.type !== 'input' && this.row.type !== 'switch' && this.row.type !== 'list') {
        this.onTap();
      }
    })
  }
}

function settingsRowActionText(row: SettingsRowItem): string {
  if (row.value.length > 0) {
    return uiValue(row.value);
  }
  return uiText('Open');
}

function buildSelectOptions(options: string[]): SelectOption[] {
  const result: SelectOption[] = [];
  for (let i = 0; i < options.length; i++) {
    result.push({ value: uiValue(options[i]) });
  }
  return result;
}

function optionIndex(options: string[], value: string): number {
  for (let i = 0; i < options.length; i++) {
    if (options[i] === value) {
      return i;
    }
  }
  return 0;
}

function settingsRowRenderKey(row: SettingsRowItem): string {
  return row.title + ':' + row.value + ':' + row.type;
}

function isNetworkSettingKey(key: string): boolean {
  return key === 'proxy' || key === 'proxy_host' || key === 'proxy_port' || key === 'built_in_hosts' ||
    key === 'built_ex_hosts' || key === 'dns_over_https' || key === 'domain_fronting';
}

@Component
export struct SignInMark {
  label: string = '';

  build() {
    Text(this.label)
      .fontSize(24)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .textAlign(TextAlign.Center)
      .width(72)
      .height(72)
      .backgroundColor('#2F6F8F')
      .borderRadius(18)
      .padding({ top: 18 })
  }
}

function collectWebCookies(currentUrl: string): string {
  const names: string[] = [];
  const values: string[] = [];
  absorbCookieHeader(currentUrl, names, values);
  absorbCookieHeader(EhUrl.HOST_E, names, values);
  absorbCookieHeader(EhUrl.HOST_EX, names, values);
  absorbCookieHeader(EhUrl.FORUM_ORIGIN, names, values);
  absorbCookieHeader(EhUrl.URL_SIGN_IN, names, values);

  const parts: string[] = [];
  for (let i = 0; i < names.length; i++) {
    parts.push(names[i] + '=' + values[i]);
  }
  return parts.join('; ');
}

interface CookieIdentity {
  memberId: string;
  passHash: string;
  igneous: string;
}

function parseCookieIdentity(text: string): CookieIdentity {
  const names: string[] = [];
  const values: string[] = [];
  absorbCookieHeaderText(text, names, values);
  return {
    memberId: findCookieValue('ipb_member_id', names, values),
    passHash: findCookieValue('ipb_pass_hash', names, values),
    igneous: findCookieValue('igneous', names, values)
  };
}

function absorbCookieHeaderText(text: string, names: string[], values: string[]): void {
  if (text.trim().length === 0) {
    return;
  }

  const rows = text.replace(/\r/g, '\n').split('\n');
  for (let i = 0; i < rows.length; i++) {
    absorbCookieRow(rows[i], names, values);
  }
}

function absorbCookieRow(row: string, names: string[], values: string[]): void {
  const trimmed = row.trim();
  if (trimmed.length === 0) {
    return;
  }

  const colon = trimmed.indexOf(':');
  if (colon > 0) {
    const key = trimmed.substring(0, colon).trim();
    const value = trimmed.substring(colon + 1).trim();
    if (isKnownCookieName(key) && value.length > 0) {
      upsertCookiePair(key, value, names, values);
      return;
    }
  }

  const normalized = trimmed.startsWith('Cookie:') ? trimmed.substring(7).trim() : trimmed;
  const pieces = normalized.split(';');
  for (let i = 0; i < pieces.length; i++) {
    const piece = pieces[i].trim();
    const eq = piece.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const key = piece.substring(0, eq).trim();
    const value = piece.substring(eq + 1).trim();
    if (key.length === 0 || value.length === 0 || isCookieAttribute(key)) {
      continue;
    }
    upsertCookiePair(key, value, names, values);
  }
}

function findCookieValue(name: string, names: string[], values: string[]): string {
  for (let i = 0; i < names.length; i++) {
    if (names[i] === name) {
      return values[i];
    }
  }
  return '';
}

function absorbCookieHeader(url: string, names: string[], values: string[]): void {
  if (url.length === 0) {
    return;
  }

  let header = '';
  try {
    header = webview.WebCookieManager.fetchCookieSync(url);
  } catch (error) {
    header = '';
  }
  if (header.length === 0) {
    return;
  }

  const pairs = header.split(';');
  for (let i = 0; i < pairs.length; i++) {
    const pair = pairs[i].trim();
    const index = pair.indexOf('=');
    if (index <= 0) {
      continue;
    }
    upsertCookiePair(pair.substring(0, index), pair.substring(index + 1), names, values);
  }
}

function upsertCookiePair(name: string, value: string, names: string[], values: string[]): void {
  for (let i = 0; i < names.length; i++) {
    if (names[i] === name) {
      values[i] = value;
      return;
    }
  }
  names.push(name);
  values.push(value);
}

function hasLoginCookie(cookieHeader: string): boolean {
  return cookieHeader.indexOf('ipb_member_id=') >= 0 && cookieHeader.indexOf('ipb_pass_hash=') >= 0;
}

function isKnownCookieName(name: string): boolean {
  return name === 'ipb_member_id' || name === 'ipb_pass_hash' || name === 'igneous' ||
    name === 'cf_clearance' || name === 'sk' || name === 'yay' || name === 'sl';
}

function isCookieAttribute(name: string): boolean {
  const lower = name.toLowerCase();
  return lower === 'domain' || lower === 'path' || lower === 'expires' || lower === 'max-age' ||
    lower === 'secure' || lower === 'httponly' || lower === 'samesite';
}

function checkIpbMemberId(id: string): boolean {
  if (id.length === 0) {
    return false;
  }
  for (let i = 0; i < id.length; i++) {
    const code = id.charCodeAt(i);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}

function checkIpbPassHash(hash: string): boolean {
  if (hash.length !== 32) {
    return false;
  }
  for (let i = 0; i < hash.length; i++) {
    const code = hash.charCodeAt(i);
    const digit = code >= 48 && code <= 57;
    const lower = code >= 97 && code <= 122;
    if (!digit && !lower) {
      return false;
    }
  }
  return true;
}
