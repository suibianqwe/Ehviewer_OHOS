import { common } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { GalleryInfo, GallerySite } from '../model/GalleryModels';
import { ehBookmarkStore } from '../services/EhBookmarkStore';
import { ehCookieStore } from '../services/EhCookieStore';
import {
  DOWNLOAD_LOCATION_APP_FILES,
  DOWNLOAD_LOCATION_DOWNLOADS,
  DownloadDirectoryScanResult,
  ehDownloadFileStore
} from '../services/EhDownloadFileStore';
import { DownloadInfo, DownloadLabel, ehDownloadStore } from '../services/EhDownloadStore';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehLocalFavoritesStore } from '../services/EhLocalFavoritesStore';
import {
  DownloadMetadataRestoreResult,
  rebuildImportedHistoryMetadata
} from '../services/DownloadMetadataRestore';
import {
  DownloadRestoreResult,
  DownloadZipImportResult,
  restoreDownloadedItemsAndArchives
} from '../services/DownloadZipImportService';
import {
  HISTORY_INFO_SIZE_KEY,
  ehSettingsStore,
  historyInfoSizeLimitFromValue,
  normalizeHistoryInfoSizeOption,
  SettingEntry,
  defaultSettingEntries
} from '../services/EhSettingsStore';
import {
  SavedTranslationApi,
  cloneSavedTranslationApis,
  createSavedTranslationApi,
  findSavedTranslationApi,
  parseSavedTranslationApis,
  serializeSavedTranslationApis,
  uniqueTranslationApiName
} from '../services/TranslationApiConfigSupport';
import { EhHttpClient, NetworkDiagnosticResult } from '../services/EhHttpClient';
import {
  currentDnsOverHttpsStatusText,
  isEhDirectConnectionProbeEnabled,
  startEhDirectConnectionProbe,
  startEhFrontingBenchmark
} from '../services/EhNetworkConfig';
import { EhUrl } from '../services/EhUrl';
import { ehUpdateChecker, ReleaseInfo, UpdateCheckResult } from '../services/EhUpdateChecker';
import { TRANSLATION_ENABLED_KEY, ehTranslationService } from '../services/EhTranslationService';
import { galleryPageCache } from '../services/GalleryPageCache';
import { CacheClearResult, CachePruneResult, readerImageCache } from '../services/ReaderImageCache';
import { FilterRule, FILTER_MODE_RATING, FILTER_MODE_TITLE, ehFilterStore } from '../services/EhFilterStore';
import {
  applyAppChromeImmersiveMode,
  mainContentWidthFallbackVp,
  rememberMainContentWidthVp
} from '../services/EhWindowImmersive';
import { applyWindowPrivacyMode } from '../services/EhWindowPrivacy';
import { ehAppLog } from '../services/EhAppLog';
import { ehParseErrorBodyStore, ParseErrorBodyEntry } from '../services/EhParseErrorBodyStore';
import {
  AndroidDataImportSummary,
  importAndroidDatabaseBackup,
  isAndroidDatabaseBackup
} from '../services/AndroidDataImporter';
import {
  EH_APP_VERSION_CODE,
  EH_APP_VERSION_NAME,
  EH_AUTHOR_NAME,
  EH_AUTHOR_URL,
  EH_ISSUES_URL,
  EH_RELEASE_URL,
  EH_REPOSITORY_URL,
  EH_TARGET_PLATFORM
} from '../services/EhBuildInfo';
import {
  IDENTITY_AUTH_LOCKED_KEY,
  LANGUAGE_REVISION_KEY,
  notifyGalleryTitleChanged,
  notifyLanguageChanged,
  notifyThemeChanged
} from '../shared/EhShared';
import {
  currentThemeName,
  themeFieldBackground,
  themeOnPrimaryText,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeScrimColor,
  themeSelectedBackground,
  themeSurface,
  themeSurfaceVariant,
  themeTertiaryText
} from '../shared/EhTheme';
import { EhBackupBundle, SettingsHeaderItem, SettingsRowItem, SettingsPanel, SETTINGS_HEADERS, uiText, uiValue, uiStatusText, setActiveBackHandler, padTwo, getAbilityContext, downloadSizeText, settingsPanelTitle, settingsRowsForPanel, settingEntryValue, cloneStringOptions, settingMigrationMessage, isValidProxyHostText, isValidProxyPortText, normalizeProxyOption, formatNetworkDiagnostics, normalizeAutoTransferTimeOption, normalizeBrightnessLevelOption, normalizeIdentityAuthenticationOption, normalizeReaderCacheSizeOption } from '../shared/EhShared';
import { FilterPanel } from './DownloadMigrationScenes';
import { BlockingBusyOverlay } from './BlockingBusyOverlay';
import { MyTagsPanel } from './MyTagsPanel';
import { AppSubToolbar, AppToolbar } from './NavigationComponents';
import { collectWebCookies, hasLoginCookie, SessionScene, syncCookieHeaderToWebView } from './SessionScene';
import { UpdatePromptOverlay } from './UpdatePromptOverlay';
import {
  areaDimensionToVp,
  markCurrentRouteRightPane,
  normalizeSplitPaneFocus,
  saveSplitPaneRatio,
  SPLIT_PANE_BREAKPOINT,
  SPLIT_PANE_FOCUS_LEFT,
  SPLIT_PANE_FOCUS_RIGHT,
  SPLIT_PANE_RATIO_REVISION_KEY,
  shouldFadeRestoredRightPane,
  splitPaneCurrentRatio,
  SplitPaneDivider,
  splitPaneListWidth,
  splitPaneModeEnabled,
  splitPaneRatioForWidth,
  splitPaneSideWidth,
  splitPaneWidthFromDrag,
  shouldUpdateSplitPaneFocus
} from './SplitPaneSupport';

const DIAGNOSTIC_LOG_TAG: string = 'SettingsScene';
const LOG_EXPORT_CHUNK_BYTES: number = 64 * 1024;
const EH_LICENSE_URL: string = 'https://github.com/suibianqwe/Ehviewer_OHOS/blob/main/LICENSE';

function cloneSettingsPanelStack(stack: SettingsPanel[]): SettingsPanel[] {
  const result: SettingsPanel[] = [];
  for (let i = 0; i < stack.length; i++) {
    result.push(stack[i]);
  }
  return result;
}

interface SettingsNavigationCache {
  activeSplitPane: string;
  panel: SettingsPanel;
  panelStack: SettingsPanel[];
  webViewUrl: string;
  webViewTitle: string;
  filterNewText: string;
  filterNewMode: number;
}

let settingsNavigationCache: SettingsNavigationCache | null = null;

@Component
export struct SettingsScene {
  @State panel: SettingsPanel = SettingsPanel.Main;
  @State panelStack: SettingsPanel[] = [SettingsPanel.Main];
  @State signedIn: boolean = ehCookieStore.hasCookies();
  @State statusText: string = '';
  @State blockingBusyVisible: boolean = false;
  @State blockingBusyMessage: string = 'Loading...';
  @State themeName: string = 'Light';
  @State settingEntries: SettingEntry[] = defaultSettingEntries();
  @State optionPickerOpen: boolean = false;
  @State optionKey: string = '';
  @State optionTitle: string = '';
  @State optionSummary: string = '';
  @State optionValue: string = '';
  @State optionOptions: string[] = [];
  @State optionDescriptions: string[] = [];
  @State optionAllowCustomInput: boolean = false;
  @State downloadMigrationDialogOpen: boolean = false;
  @State downloadMigrationCurrent: string = DOWNLOAD_LOCATION_APP_FILES;
  @State downloadMigrationTarget: string = DOWNLOAD_LOCATION_APP_FILES;
  @State webViewUrl: string = '';
  @State webViewTitle: string = '';
  @State filterRules: FilterRule[] = [];
  @State filterNewText: string = '';
  @State filterNewMode: number = FILTER_MODE_TITLE;
  @State settingsRenderRevision: number = 0;
  @State sceneContentWidth: number = 0;
  @State splitListRatio: number = splitPaneCurrentRatio();
  @State splitDragging: boolean = false;
  @State activeSplitPane: string = SPLIT_PANE_FOCUS_LEFT;
  @State restorePanelWithFade: boolean = false;
  @State updateDialogVisible: boolean = false;
  @State updateCurrentVersion: string = '';
  @State updateRelease: ReleaseInfo | null = null;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp(SPLIT_PANE_RATIO_REVISION_KEY) @Watch('onSplitPaneRatioRevisionChange') splitPaneRatioRevision: number = 0;
  private client: EhHttpClient = new EhHttpClient();
  private splitDragStartWidth: number = 0;
  @Prop @Watch('onResetVersionChanged') resetVersion: number = 0;
  onMenu: () => void = () => {};
  onSignedIn: () => void = () => {};

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    this.syncSceneContentWidthFromWindow();
    this.restoreNavigationCache();
    markCurrentRouteRightPane(this.useSplitLayout());
    setActiveBackHandler(() => this.handleSystemBack());
    const context = getAbilityContext();
    if (context !== undefined) {
      ehCookieStore.ensureLoaded(context).then(() => {
        this.signedIn = ehCookieStore.hasCookies();
        this.statusText = this.signedIn ? 'Cookie session loaded' : 'Tourist mode';
      }).catch((error: Error) => {
        this.statusText = 'Cookie load failed: ' + error.message;
      });
      ehSettingsStore.ensureLoaded(context).then(() => {
        this.settingEntries = ehSettingsStore.getEntries();
        this.themeName = currentThemeName();
      }).catch((error: Error) => {
        this.statusText = 'Settings load failed: ' + error.message;
      });
      ehDownloadStore.load(context).then(() => {
        this.settingsRenderRevision++;
      }).catch(() => {
      });
    } else {
      this.signedIn = ehCookieStore.hasCookies();
      this.statusText = this.signedIn ? 'Cookie session loaded' : 'Tourist mode';
      this.settingEntries = ehSettingsStore.getEntries();
      this.themeName = currentThemeName();
    }
  }

  aboutToDisappear(): void {
    this.saveNavigationCache();
  }

  onResetVersionChanged(): void {
    this.resetToTopLevel();
  }

  private handleSystemBack(): boolean {
    if (this.optionPickerOpen) {
      this.closeOptionPicker();
      return true;
    }
    if (this.downloadMigrationDialogOpen) {
      this.closeDownloadMigrationDialog();
      return true;
    }
    if (this.updateDialogVisible) {
      this.updateDialogVisible = false;
      return true;
    }
    if (this.panel !== SettingsPanel.Main) {
      this.closePanel();
      return true;
    }
    return false;
  }

  private resetToTopLevel(): void {
    this.optionPickerOpen = false;
    this.downloadMigrationDialogOpen = false;
    this.updateDialogVisible = false;
    this.webViewUrl = '';
    this.webViewTitle = '';
    this.panel = SettingsPanel.Main;
    this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
    this.panelStack = [SettingsPanel.Main];
    this.restorePanelWithFade = false;
    markCurrentRouteRightPane(false);
    this.restoreBackHandler();
    this.clearNavigationCache();
  }

  private openPanel(panel: SettingsPanel): void {
    this.restorePanelWithFade = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    this.optionPickerOpen = false;
    if (this.panel === panel) {
      return;
    }
    const nextStack: SettingsPanel[] = [];
    for (let i = 0; i < this.panelStack.length; i++) {
      nextStack.push(this.panelStack[i]);
    }
    nextStack.push(panel);
    this.panelStack = nextStack;
    this.panel = panel;
    markCurrentRouteRightPane(this.useSplitLayout());
    this.saveNavigationCache();
    this.restoreBackHandler();
  }

  private openPrimaryPanel(panel: SettingsPanel): void {
    this.restorePanelWithFade = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    this.optionPickerOpen = false;
    if (splitPaneModeEnabled() && this.sceneContentWidth >= SPLIT_PANE_BREAKPOINT) {
      this.panelStack = [SettingsPanel.Main, panel];
      this.panel = panel;
      markCurrentRouteRightPane(this.useSplitLayout());
      this.saveNavigationCache();
      this.restoreBackHandler();
      return;
    }
    this.openPanel(panel);
  }

  private closePanel(): void {
    this.restorePanelWithFade = false;
    this.optionPickerOpen = false;
    if (this.panelStack.length <= 1) {
      this.panelStack = [SettingsPanel.Main];
      this.panel = SettingsPanel.Main;
      this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
    } else {
      const nextStack: SettingsPanel[] = [];
      for (let i = 0; i < this.panelStack.length - 1; i++) {
        nextStack.push(this.panelStack[i]);
      }
      this.panelStack = nextStack.length > 0 ? nextStack : [SettingsPanel.Main];
      this.panel = this.panelStack[this.panelStack.length - 1];
    }
    this.signedIn = ehCookieStore.hasCookies();
    markCurrentRouteRightPane(this.useSplitLayout());
    this.saveNavigationCache();
    this.restoreBackHandler();
  }

  private restoreNavigationCache(): void {
    if (settingsNavigationCache === null) {
      return;
    }
    this.panel = settingsNavigationCache.panel;
    this.activeSplitPane = normalizeSplitPaneFocus(settingsNavigationCache.activeSplitPane,
      settingsNavigationCache.panel !== SettingsPanel.Main);
    this.panelStack = cloneSettingsPanelStack(settingsNavigationCache.panelStack);
    this.webViewUrl = settingsNavigationCache.webViewUrl;
    this.webViewTitle = settingsNavigationCache.webViewTitle;
    this.filterNewText = settingsNavigationCache.filterNewText;
    this.filterNewMode = settingsNavigationCache.filterNewMode;
    this.restorePanelWithFade = this.settingsDetailLayerPanel() !== SettingsPanel.Main && shouldFadeRestoredRightPane();
  }

  private saveNavigationCache(): void {
    settingsNavigationCache = {
      activeSplitPane: this.activeSplitPane,
      panel: this.panel,
      panelStack: cloneSettingsPanelStack(this.panelStack),
      webViewUrl: this.webViewUrl,
      webViewTitle: this.webViewTitle,
      filterNewText: this.filterNewText,
      filterNewMode: this.filterNewMode
    };
  }

  private clearNavigationCache(): void {
    settingsNavigationCache = null;
  }

  private restoreBackHandler(): void {
    setTimeout(() => {
      setActiveBackHandler(() => this.handleSystemBack());
    }, 0);
  }

  private isSettingsDetailPanel(panel: SettingsPanel): boolean {
    return panel === SettingsPanel.Eh || panel === SettingsPanel.Read || panel === SettingsPanel.Download ||
      panel === SettingsPanel.Privacy || panel === SettingsPanel.Translation || panel === SettingsPanel.Advanced ||
      panel === SettingsPanel.About;
  }

  private settingsDetailLayerPanel(): SettingsPanel {
    for (let i = this.panelStack.length - 1; i >= 0; i--) {
      if (this.isSettingsDetailPanel(this.panelStack[i])) {
        return this.panelStack[i];
      }
    }
    return SettingsPanel.Main;
  }

  private updateSceneContentWidth(width: number): void {
    const normalized = Math.floor(width);
    if (normalized <= 0 || Number.isNaN(normalized) || Math.abs(this.sceneContentWidth - normalized) < 1) {
      return;
    }
    this.sceneContentWidth = normalized;
    rememberMainContentWidthVp(normalized);
    markCurrentRouteRightPane(this.useSplitLayout());
  }

  private syncSceneContentWidthFromWindow(): void {
    const width = mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value));
    if (width >= 240) {
      this.updateSceneContentWidth(width);
    }
  }

  onSplitPaneRatioRevisionChange(): void {
    if (!this.splitDragging) {
      this.splitListRatio = splitPaneCurrentRatio();
    }
  }

  private useSplitLayout(): boolean {
    return splitPaneModeEnabled() && this.sceneContentWidth >= SPLIT_PANE_BREAKPOINT &&
      this.settingsDetailLayerPanel() !== SettingsPanel.Main;
  }

  private splitListPaneWidth(): number {
    return splitPaneListWidth(this.sceneContentWidth, this.splitListRatio);
  }

  private splitSidePaneWidth(): number {
    if (!this.useSplitLayout()) {
      return this.sceneContentWidth > 0 ? this.sceneContentWidth : 0;
    }
    return splitPaneSideWidth(this.sceneContentWidth, this.splitListPaneWidth());
  }

  private settingsLayerWidth(): number | string {
    return this.useSplitLayout() ? this.splitSidePaneWidth() : '100%';
  }

  private settingsLayerTranslateX(): number {
    return this.useSplitLayout() ? this.splitListPaneWidth() + 1 : 0;
  }

  private updateSplitPaneByOffset(offsetX: number): void {
    const targetWidth = splitPaneWidthFromDrag(this.sceneContentWidth, this.splitDragStartWidth, offsetX);
    this.splitListRatio = splitPaneRatioForWidth(this.sceneContentWidth, targetWidth);
  }

  private finishSplitPaneDrag(): void {
    this.splitDragging = false;
    saveSplitPaneRatio(this.splitListRatio);
  }

  private currentGallerySite(): GallerySite {
    return ehSettingsStore.getValue('gallery_site', 'E-Hentai') === 'ExHentai' ? GallerySite.Ex : GallerySite.E;
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

  private saveSettingValue(key: string, value: string): void {
    if (key === 'download_location') {
      this.requestDownloadLocationChange(value);
      return;
    }
    this.commitSettingValue(key, value);
  }

  private commitSettingValue(key: string, value: string): void {
    if (this.updateCustomTranslationApiField(key, value)) {
      return;
    }
    if (key === 'proxy_host' && !isValidProxyHostText(value)) {
      this.statusText = 'Invalid proxy host: ' + value;
      return;
    }
    if (key === 'proxy_port' && value.length > 0 && !isValidProxyPortText(value)) {
      this.statusText = 'Invalid proxy port: ' + value;
      return;
    }
    const normalizedValue = this.normalizedSettingValue(key, value);
    ehSettingsStore.setValue(key, normalizedValue);
    if (key === 'translation_provider' && normalizedValue === 'Custom API') {
      this.ensureCustomTranslationApi();
    }
    if (key === 'translation_buttons_enabled' && normalizedValue !== 'On') {
      ehTranslationService.setEnabled(false);
    }
    if (isTranslationSettingKey(key)) {
      ehTranslationService.clearCache();
    }
    if (key === 'follow_system_dark_mode' && normalizedValue === 'On' &&
      ehSettingsStore.getValue('theme', 'Light') === 'Light') {
      ehSettingsStore.setValue('theme', 'Dark');
    }
    if (key === 'reading_direction' && normalizedValue === 'Top to bottom') {
      ehSettingsStore.setValue('screen_rotation', 'Default');
      ehSettingsStore.setValue('page_scaling', 'Fixed scale');
    }
    this.settingEntries = ehSettingsStore.getEntries();
    this.themeName = currentThemeName();
    if (key === this.optionKey) {
      this.optionValue = normalizedValue;
    }
    if (key === 'app_language' || key === 'show_tag_translations') {
      notifyLanguageChanged();
    }
    if (key === 'show_jpn_title') {
      notifyGalleryTitleChanged();
    }
    if (key === 'theme' || key === 'follow_system_dark_mode') {
      notifyThemeChanged();
      this.settingsRenderRevision++;
      applyAppChromeImmersiveMode();
    }
    if (key === 'pattern_protection') {
      if (normalizedValue === 'Off') {
        AppStorage.setOrCreate<boolean>(IDENTITY_AUTH_LOCKED_KEY, false);
      }
      this.statusText = normalizedValue === 'Off'
        ? 'Identity authentication disabled'
        : 'Identity authentication mode: ' + normalizedValue;
    }
    if (key === 'enable_secure') {
      applyWindowPrivacyMode(value === 'On', (status: string) => {
        this.statusText = status;
      }, getAbilityContext());
    }
    if (isNetworkSettingKey(key)) {
      this.refreshNetworkRuntime();
    }
    const context = getAbilityContext();
    if (context === undefined) {
      if (key === HISTORY_INFO_SIZE_KEY) {
        ehHistoryStore.trim(historyInfoSizeLimitFromValue(normalizedValue));
      }
      const displayValue = settingDisplayValueForStatus(key, normalizedValue);
      this.statusText = isNetworkSettingKey(key) ? 'Saved network setting in memory: ' + key + ' = ' + displayValue +
        '. Refresh Homepage or run Network diagnostics.' : 'Saved in memory: ' + key + ' = ' + displayValue;
      return;
    }
    let cachePrune: CachePruneResult | null = null;
    if (key === 'read_cache_size') {
      cachePrune = readerImageCache.prune(context);
      this.settingsRenderRevision++;
    }
    if (key === HISTORY_INFO_SIZE_KEY) {
      ehHistoryStore.ensureLoaded(context).then(() => {
        ehHistoryStore.trim(historyInfoSizeLimitFromValue(normalizedValue));
        ehHistoryStore.save(context).catch(() => {});
      }).catch(() => {});
    }
    ehSettingsStore.save(context).then(() => {
      const displayValue = settingDisplayValueForStatus(key, normalizedValue);
      this.statusText = isNetworkSettingKey(key) ? 'Saved network setting: ' + key + ' = ' + displayValue +
        '. Refresh Homepage or run Network diagnostics.' : 'Saved: ' + key + ' = ' + displayValue;
      if (key === 'theme' || key === 'follow_system_dark_mode') {
        this.statusText = 'Theme refreshed';
      }
      if (cachePrune !== null && key === 'read_cache_size') {
        this.statusText = 'Cache limit saved: ' + normalizedValue + '. Cleared oldest cache: ' +
          downloadSizeText(cachePrune.bytes) + '.';
      }
    }).catch((error: Error) => {
      this.statusText = 'Save failed: ' + error.message;
    });
  }

  private normalizedSettingValue(key: string, value: string): string {
    if (key === 'screen_rotation' &&
      settingEntryValue(this.settingEntries, 'reading_direction', 'Right to left') === 'Top to bottom' &&
      value === 'Match image') {
      return 'Default';
    }
    if (key === 'page_scaling' &&
      settingEntryValue(this.settingEntries, 'reading_direction', 'Right to left') === 'Top to bottom' &&
      (value === 'Fit height' || value === 'Fit screen')) {
      return 'Fixed scale';
    }
    if (key === 'pattern_protection') {
      return normalizeIdentityAuthenticationOption(value);
    }
    if (key === 'read_cache_size') {
      return normalizeReaderCacheSizeOption(value);
    }
    if (key === HISTORY_INFO_SIZE_KEY) {
      return normalizeHistoryInfoSizeOption(value);
    }
    if (key === 'detail_size') {
      if (value === 'Default') {
        return 'Medium';
      }
      if (value === 'Compact' || value === 'Medium' || value === 'Loose') {
        return value;
      }
      if (value === 'Large') {
        return 'Loose';
      }
      return 'Medium';
    }
    if (key === 'thumb_size') {
      if (value === 'Small' || value === 'Medium' || value === 'Large' || value === 'XLarge') {
        return value;
      }
      return 'Medium';
    }
    if (key === 'theme' && ehSettingsStore.getValue('follow_system_dark_mode', 'Off') === 'On') {
      return value === 'Black' ? 'Black' : 'Dark';
    }
    if (key === 'proxy') {
      return normalizeProxyOption(value);
    }
    if (key === 'proxy_host') {
      return value.trim();
    }
    if (key === 'proxy_port') {
      return value.trim();
    }
    if (key === 'proxy_exclusion_list') {
      return normalizeProxyExclusionListText(value);
    }
    return value;
  }

  private requestDownloadLocationChange(value: string): void {
    const target = normalizeSettingsDownloadLocation(value);
    const current = normalizeSettingsDownloadLocation(ehSettingsStore.getValue('download_location', DOWNLOAD_LOCATION_APP_FILES));
    if (target === current) {
      this.commitSettingValue('download_location', target);
      return;
    }
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Download location needs app context';
      return;
    }
    this.statusText = target === DOWNLOAD_LOCATION_DOWNLOADS ? 'Preparing public Downloads access...' :
      'Preparing app internal storage...';
    this.prepareDownloadLocationTarget(context, target).then((ready: boolean) => {
      if (!ready) {
        return;
      }
      this.showDownloadLocationMigrationDialog(current, target);
    }).catch((error: Error) => {
      this.statusText = 'Download location change failed: ' + error.message;
    });
  }

  private async prepareDownloadLocationTarget(context: common.UIAbilityContext, target: string): Promise<boolean> {
    return this.ensureDownloadLocationAccess(context, target);
  }

  private async ensureDownloadLocationAccess(context: common.UIAbilityContext, location: string): Promise<boolean> {
    const normalized = normalizeSettingsDownloadLocation(location);
    if (normalized === DOWNLOAD_LOCATION_APP_FILES) {
      return true;
    }
    if (ehDownloadFileStore.canUseLocation(context, normalized)) {
      return true;
    }
    const pickedRoot = await this.pickDownloadDirectoryRoot(context);
    if (pickedRoot.length > 0) {
      ehDownloadFileStore.rememberPublicDownloadRoot(pickedRoot);
      if (ehDownloadFileStore.canUseLocation(context, normalized)) {
        return true;
      }
    }
    this.statusText = 'Downloads access was not granted';
    return false;
  }

  private async pickDownloadDirectoryRoot(context: common.UIAbilityContext): Promise<string> {
    try {
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const documentPicker = new picker.DocumentViewPicker(context);
      const result = await documentPicker.save(saveOptions);
      if (result.length === 0 || result[0].length === 0) {
        return '';
      }
      return new fileUri.FileUri(result[0]).path;
    } catch (error) {
      return '';
    }
  }

  private showDownloadLocationMigrationDialog(current: string, target: string): void {
    this.downloadMigrationCurrent = current;
    this.downloadMigrationTarget = target;
    this.downloadMigrationDialogOpen = true;
  }

  private closeDownloadMigrationDialog(): void {
    this.downloadMigrationDialogOpen = false;
  }

  private applyDownloadLocationChange(context: common.UIAbilityContext, current: string, target: string,
    migrate: boolean): void {
    this.applyDownloadLocationChangeAsync(context, current, target, migrate).catch((error: Error) => {
      this.hideBlockingBusy();
      this.statusText = 'Download migration failed: ' + error.message;
    });
  }

  private chooseDownloadLocationMigration(migrate: boolean): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Download location needs app context';
      return;
    }
    this.applyDownloadLocationChange(context, this.downloadMigrationCurrent, this.downloadMigrationTarget, migrate);
  }

  private async applyDownloadLocationChangeAsync(context: common.UIAbilityContext, current: string, target: string,
    migrate: boolean): Promise<void> {
    this.closeDownloadMigrationDialog();
    this.showBlockingBusy(migrate ? 'Migrating downloaded files...' : 'Switching download location...');
    if (migrate) {
      try {
        if (!await this.ensureDownloadLocationAccess(context, current)) {
          this.hideBlockingBusy();
          return;
        }
        if (!await this.ensureDownloadLocationAccess(context, target)) {
          this.hideBlockingBusy();
          return;
        }
        const result = ehDownloadFileStore.migrateDownloadLocation(context, current, target);
        this.hideBlockingBusy();
        this.showFloatingStatus('Migrated downloads: ' + result.files.toString() + ' files, ' +
          downloadSizeText(result.bytes) + '.');
      } catch (error) {
        this.hideBlockingBusy();
        this.showFloatingStatus('Download migration failed: ' + String(error));
        return;
      }
    } else {
      this.hideBlockingBusy();
      this.showFloatingStatus('Download location switched without migration');
    }
    this.commitSettingValue('download_location', target);
  }

  private cycleSetting(row: SettingsRowItem): void {
    if (row.key === undefined) {
      this.statusText = row.title + ' is not available';
      return;
    }
    if (this.runSettingAction(row.key)) {
      return;
    }
    if (row.type === 'model') {
      this.openTranslationModelPicker(row);
      return;
    }
    if (row.options === undefined || row.options.length === 0) {
      this.statusText = row.title + ' is not available yet';
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
    this.optionValue = row.value;
    this.optionOptions = cloneStringOptions(row.options);
    this.optionDescriptions = row.optionDescriptions === undefined ? [] : cloneStringOptions(row.optionDescriptions);
    this.optionAllowCustomInput = false;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    this.optionPickerOpen = true;
    this.statusText = '';
  }

  private openAccountWebPage(title: string, url: string): void {
    this.prepareAccountWebViewCookies(url);
    this.webViewUrl = url;
    this.webViewTitle = title;
    this.openPanel(SettingsPanel.WebView);
  }

  private prepareAccountWebViewCookies(url: string): void {
    const cookieHeader = ehCookieStore.getCookieHeader();
    if (cookieHeader.length === 0) {
      return;
    }

    syncCookieHeaderToWebView(url, cookieHeader);
    syncCookieHeaderToWebView(EhUrl.HOST_E, cookieHeader);
    syncCookieHeaderToWebView(EhUrl.HOST_EX, cookieHeader);
    syncCookieHeaderToWebView(EhUrl.FORUM_ORIGIN, cookieHeader);
    try {
      webview.WebCookieManager.configCookieSync(EhUrl.HOST_E, 'nw=1; path=/');
      webview.WebCookieManager.configCookieSync(EhUrl.HOST_EX, 'nw=1; path=/');
      webview.WebCookieManager.saveCookieSync();
    } catch (error) {
    }
  }

  private captureAccountWebCookies(url: string): void {
    const cookieHeader = collectWebCookies(url);
    if (!hasLoginCookie(cookieHeader)) {
      return;
    }

    ehCookieStore.setCookieHeader(cookieHeader);
    this.signedIn = ehCookieStore.hasCookies();
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehCookieStore.save(context).catch(() => {
    });
  }

  private closeOptionPicker(): void {
    this.optionPickerOpen = false;
    this.optionKey = '';
    this.optionTitle = '';
    this.optionSummary = '';
    this.optionValue = '';
    this.optionOptions = [];
    this.optionDescriptions = [];
    this.optionAllowCustomInput = false;
    this.restoreBackHandler();
  }

  private selectOptionValue(value: string): void {
    if (this.optionKey.length === 0) {
      this.statusText = 'No setting is selected';
      return;
    }
    if (this.optionKey === 'translation_custom_api_selected' && value === 'New...') {
      this.createAndSelectCustomTranslationApi();
    } else {
      this.saveSettingValue(this.optionKey, value);
    }
    this.closeOptionPicker();
  }

  private openTranslationModelPicker(row: SettingsRowItem): void {
    if (row.key === undefined) {
      return;
    }
    const provider = ehSettingsStore.getValue('translation_provider', 'Google Web');
    this.optionKey = row.key;
    this.optionTitle = row.title;
    this.optionSummary = row.summary;
    this.optionValue = row.value;
    this.optionOptions = row.value.trim().length > 0 ? [row.value.trim()] : [];
    this.optionDescriptions = [];
    this.optionAllowCustomInput = true;
    this.optionPickerOpen = true;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    this.showFloatingStatus('Loading available models...');
    ehTranslationService.fetchAvailableModels(provider).then((models: string[]) => {
      const options: string[] = [];
      if (row.value.trim().length > 0) {
        options.push(row.value.trim());
      }
      for (let i = 0; i < models.length; i++) {
        if (options.indexOf(models[i]) < 0) {
          options.push(models[i]);
        }
      }
      this.optionOptions = options;
      this.statusText = models.length > 0 ? 'Available models loaded' : 'No available models were returned';
    }).catch((error: Error) => {
      this.showFloatingStatus('Available models could not be loaded: ' + error.message);
    });
  }

  private customTranslationApis(): SavedTranslationApi[] {
    return parseSavedTranslationApis(ehSettingsStore.getValue('translation_custom_apis', '[]'));
  }

  private ensureCustomTranslationApi(): void {
    const items = this.customTranslationApis();
    const selectedName = ehSettingsStore.getValue('translation_custom_api_selected', '');
    const selected = findSavedTranslationApi(items, selectedName);
    if (selected !== null) {
      if (selectedName !== selected.name) {
        ehSettingsStore.setValue('translation_custom_api_selected', selected.name);
      }
      return;
    }
    const created = createSavedTranslationApi(items);
    items.push(created);
    ehSettingsStore.setValue('translation_custom_apis', serializeSavedTranslationApis(items));
    ehSettingsStore.setValue('translation_custom_api_selected', created.name);
  }

  private createAndSelectCustomTranslationApi(): void {
    const items = this.customTranslationApis();
    const created = createSavedTranslationApi(items);
    items.push(created);
    ehSettingsStore.setValue('translation_custom_apis', serializeSavedTranslationApis(items));
    ehSettingsStore.setValue('translation_custom_api_selected', created.name);
    this.finishCustomTranslationApiSave('Created API: ' + created.name);
  }

  private updateCustomTranslationApiField(key: string, value: string): boolean {
    if (!isCustomTranslationApiField(key)) {
      return false;
    }
    const items = cloneSavedTranslationApis(this.customTranslationApis());
    const selectedName = ehSettingsStore.getValue('translation_custom_api_selected', '');
    const selected = findSavedTranslationApi(items, selectedName);
    if (selected === null) {
      this.statusText = 'No custom translation API is selected';
      return true;
    }
    let nextSelectedName = selected.name;
    if (key === 'translation_custom_api_name') {
      nextSelectedName = uniqueTranslationApiName(items, value, selected.name);
      selected.name = nextSelectedName;
    } else if (key === 'translation_custom_api_base_url') {
      selected.baseUrl = value.trim();
    } else if (key === 'translation_custom_api_key') {
      selected.apiKey = value;
    } else if (key === 'translation_custom_api_model') {
      selected.model = value.trim();
    }
    ehSettingsStore.setValue('translation_custom_apis', serializeSavedTranslationApis(items));
    ehSettingsStore.setValue('translation_custom_api_selected', nextSelectedName);
    this.finishCustomTranslationApiSave('Custom API saved');
    return true;
  }

  private finishCustomTranslationApiSave(status: string): void {
    this.settingEntries = ehSettingsStore.getEntries();
    ehTranslationService.clearCache();
    this.statusText = status;
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSettingsStore.save(context).catch((error: Error) => {
        this.statusText = 'Save failed: ' + error.message;
      });
    }
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
      this.cleanDownloadRedundancy();
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
    if (key === 'clear_app_log') {
      this.clearAppLog();
      return true;
    }
    if (key === 'declaration') {
      this.openExternalUrl(EH_REPOSITORY_URL, 'repository');
      return true;
    }
    if (key === 'author') {
      this.openExternalUrl(EH_AUTHOR_URL, EH_AUTHOR_NAME);
      return true;
    }
    if (key === 'latest_release') {
      this.openExternalUrl(EH_RELEASE_URL, 'version');
      return true;
    }
    if (key === 'issue_help') {
      this.openExternalUrl(EH_ISSUES_URL, 'issue tracker');
      return true;
    }
    if (key === 'license') {
      this.openExternalUrl(EH_LICENSE_URL, 'license');
      return true;
    }
    if (key === 'check_for_updates') {
      this.checkForUpdatesManually();
      return true;
    }
    if (key === 'translation_test') {
      this.testTranslationProvider();
      return true;
    }
    if (key === 'donate') {
      this.statusText = 'Donation is not available in this version.';
      return true;
    }
    if (key === 'dump_logcat') {
      this.exportAppLog();
      return true;
    }
    if (key === 'u_config') {
      if (!this.signedIn) {
        this.statusText = 'UConfig requires a signed-in session';
        return true;
      }
      const isEx = ehSettingsStore.getValue('gallery_site', 'E-Hentai') === 'ExHentai';
      this.openAccountWebPage('UConfig', isEx ? 'https://exhentai.org/uconfig.php' : 'https://e-hentai.org/uconfig.php');
      return true;
    }
    if (key === 'my_tags') {
      if (!this.signedIn) {
        this.statusText = 'My Tags requires a signed-in session';
        return true;
      }
      this.openPanel(SettingsPanel.MyTags);
      return true;
    }
    if (key === 'filter') {
      const context = getAbilityContext();
      if (context !== undefined) {
        ehFilterStore.ensureLoaded(context).then(() => {
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

  private testTranslationProvider(): void {
    this.statusText = uiText('Testing translation...');
    ehTranslationService.clearCache();
    ehTranslationService.translate('Hello, world.', 'text').then((translated: string) => {
      this.statusText = uiText('Translation test succeeded') + ': ' + translated;
      this.showToast(this.statusText);
    }).catch((error: Error) => {
      this.statusText = uiText('Translation test failed') + ': ' + error.message;
      this.showToast(this.statusText);
    });
  }

  private openExternalUrl(url: string, label: string): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Open link failed: Ability context is not ready';
      return;
    }
    context.startAbility({
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url,
      parameters: {
        'ohos.ability.params.showDefaultPicker': true
      }
    }).then(() => {
      this.statusText = 'Opening browser: ' + label;
    }).catch((error: Error) => {
      this.statusText = 'Open link failed: ' + error.message;
    });
  }

  private exportData(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showFloatingStatus('Export needs an ability context');
      return;
    }
    this.showFloatingStatus('Preparing export...');
    const now = new Date();
    const stamp = now.getFullYear().toString() +
      padTwo(now.getMonth() + 1) + padTwo(now.getDate()) + '_' +
      padTwo(now.getHours()) + padTwo(now.getMinutes()) + padTwo(now.getSeconds());
    const fileName = 'ehviewer_backup_' + stamp + '.json';

    Promise.all([
      ehSettingsStore.ensureLoaded(context),
      ehHistoryStore.load(context),
      ehDownloadStore.load(context),
      ehFilterStore.ensureLoaded(context),
      ehLocalFavoritesStore.ensureLoaded(context),
      ehBookmarkStore.ensureLoaded(context)
    ]).then(() => {
      const bundle: EhBackupBundle = {
        version: 1,
        exportedAt: now.toISOString(),
        cookies: ehCookieStore.getCookieHeader(),
        settings: ehSettingsStore.getEntries(),
        history: ehHistoryStore.getItems(),
        downloadItems: ehDownloadStore.getItems(),
        downloadLabels: ehDownloadStore.getLabels(),
        filterRules: ehFilterStore.getRules(),
        localFavorites: ehLocalFavoritesStore.getBackupItems(),
        bookmarks: ehBookmarkStore.getBackupItems()
      };
      const json = JSON.stringify(bundle, null, 2);

      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [fileName];
      const documentPicker = new picker.DocumentViewPicker(context);
      documentPicker.save(saveOptions).then((uris: string[]) => {
        if (uris.length === 0) {
          this.showFloatingStatus('Export cancelled');
          return;
        }
        const uri = uris[0];
        try {
          const file = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
          fs.writeSync(file.fd, json);
          fs.closeSync(file.fd);
          this.showFloatingStatus('Export saved: ' + uri);
        } catch (error) {
          this.showFloatingStatus('Export write failed: ' + String(error));
        }
      }).catch((error: Error) => {
        this.showFloatingStatus('Export picker failed: ' + error.message);
      });
    }).catch((error: Error) => {
      this.showFloatingStatus('Export load failed: ' + error.message);
    });
  }

  private checkForUpdatesManually(): void {
    this.statusText = uiText('Checking for updates...');
    ehUpdateChecker.checkLatestRelease().then((result: UpdateCheckResult) => {
      if (result.hasUpdate && result.latest !== null) {
        this.updateCurrentVersion = result.current.versionName;
        this.updateRelease = result.latest;
        this.updateDialogVisible = true;
        this.statusText = uiText('New version found') + ': ' + result.latest.tagName;
      } else {
        this.statusText = result.message;
        this.showToast(result.message);
      }
    }).catch((error: Error) => {
      this.statusText = 'Check for updates failed: ' + error.message;
    });
  }

  private exportAppLog(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showFloatingStatus('Export log needs an ability context');
      return;
    }
    const now = new Date();
    const stamp = now.getFullYear().toString() +
      padTwo(now.getMonth() + 1) + padTwo(now.getDate()) + '_' +
      padTwo(now.getHours()) + padTwo(now.getMinutes()) + padTwo(now.getSeconds());
    const fileName = 'ehviewer_log_' + stamp + '.txt';
    const content = this.createAppLogExport(context);
    if (content.trim().length === 0) {
      this.showFloatingStatus('No saved log yet');
      return;
    }
    this.writeTextToDownloads(context, fileName, content).then((path: string) => {
      this.statusText = 'Log exported: ' + path;
      this.showToast('Log exported');
    }).catch((error: Error) => {
      this.showFloatingStatus('Log export failed: ' + error.message);
      ehAppLog.error(context, DIAGNOSTIC_LOG_TAG, 'Log export failed: ' + error.message);
    });
  }

  private async writeTextToDownloads(context: common.UIAbilityContext, fileName: string, content: string): Promise<string> {
    const path = await pickDownloadsOutputPath(context, fileName);
    if (path.length === 0) {
      throw new Error('Export cancelled');
    }
    await writeTextFileChunked(path, content);
    return path;
  }

  private showFloatingStatus(message: string): void {
    this.statusText = message;
    this.showToast(message);
  }

  private showBlockingBusy(message: string): void {
    this.blockingBusyMessage = message;
    this.blockingBusyVisible = true;
  }

  private hideBlockingBusy(): void {
    this.blockingBusyVisible = false;
    this.blockingBusyMessage = 'Loading...';
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: uiStatusText(message) });
    } catch (error) {
    }
  }

  private clearAppLog(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Clear log needs an ability context';
      return;
    }
    ehAppLog.clear(context);
    ehParseErrorBodyStore.clear(context);
    this.statusText = 'Saved log cleared';
  }

  private importData(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showFloatingStatus('Import needs an ability context');
      return;
    }
    this.showFloatingStatus('Select backup file to import...');

    const selectOptions = new picker.DocumentSelectOptions();
    const documentPicker = new picker.DocumentViewPicker(context);
    documentPicker.select(selectOptions).then((uris: string[]) => {
      if (uris.length === 0) {
        this.showFloatingStatus('Import cancelled');
        return;
      }
      const uri = uris[0];
      try {
        const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        const stat = fs.statSync(file.fd);
        const buf = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buf);
        fs.closeSync(file.fd);
        const bytes = new Uint8Array(buf);
        if (isAndroidDatabaseBackup(bytes)) {
          this.showFloatingStatus('Importing Android data...');
          this.showBlockingBusy('Importing Android data...');
          importAndroidDatabaseBackup(context, bytes).then((summary: AndroidDataImportSummary) => {
            this.hideBlockingBusy();
            this.filterRules = ehFilterStore.getRules();
            this.showFloatingStatus('Import complete: Android data (history ' + summary.history +
              ', history metadata ' + summary.historyMetadata + ', fetched ' + summary.historyMetadataFetched +
              ', downloads ' + summary.downloads + ', local favorites ' + summary.localFavorites +
              ', labels ' + summary.labels + ', filters ' + summary.filters + ', bookmarks ' + summary.bookmarks + ')');
          }).catch((error: Error) => {
            this.hideBlockingBusy();
            this.showFloatingStatus('Import failed: Android data ' + error.message);
          });
          return;
        }
        const decoder = util.TextDecoder.create('utf-8');
        const json = decoder.decodeToString(bytes);
        const bundle = JSON.parse(json) as EhBackupBundle;

        if (typeof bundle.version !== 'number') {
          this.showFloatingStatus('Import failed: not a valid EhViewer backup file');
          return;
        }

        const saves: Promise<void>[] = [];

        if (typeof bundle.cookies === 'string') {
          ehCookieStore.setCookieHeader(bundle.cookies);
          saves.push(ehCookieStore.save(context));
          this.signedIn = ehCookieStore.hasCookies();
        }

        let languageChanged = false;
        let themeChanged = false;
        let titleChanged = false;
        if (Array.isArray(bundle.settings)) {
          for (let i = 0; i < bundle.settings.length; i++) {
            const e = bundle.settings[i] as SettingEntry;
            if (typeof e.key === 'string' && typeof e.value === 'string') {
              const importedValue = this.normalizedImportedSettingValue(e.key, e.value);
              if (e.key === 'app_language' && ehSettingsStore.getValue('app_language', 'System') !== e.value) {
                languageChanged = true;
              }
              if ((e.key === 'theme' || e.key === 'follow_system_dark_mode') &&
                ehSettingsStore.getValue(e.key, '') !== importedValue) {
                themeChanged = true;
              }
              if (e.key === 'show_jpn_title' && ehSettingsStore.getValue(e.key, '') !== importedValue) {
                titleChanged = true;
              }
              ehSettingsStore.setValue(e.key, importedValue);
            }
          }
          saves.push(ehSettingsStore.save(context));
          this.settingEntries = ehSettingsStore.getEntries();
          this.themeName = currentThemeName();
          if (languageChanged) {
            notifyLanguageChanged();
          }
          if (themeChanged) {
            notifyThemeChanged();
            applyAppChromeImmersiveMode();
          }
          if (titleChanged) {
            notifyGalleryTitleChanged();
          }
          readerImageCache.prune(context);
          this.settingsRenderRevision++;
        }

        let importedHistory: GalleryInfo[] = [];
        let importedHistoryLimit = historyInfoSizeLimitFromValue(ehSettingsStore.getValue(HISTORY_INFO_SIZE_KEY, '100'));
        if (Array.isArray(bundle.history)) {
          for (let i = 0; i < bundle.history.length; i++) {
            const imported = bundle.history[i] as GalleryInfo;
            if (typeof imported.gid === 'number' && imported.gid > 0 && typeof imported.token === 'string' &&
              imported.token.length > 0) {
              importedHistory.push(imported);
            }
          }
        }

        let downloadsChanged = false;
        if (Array.isArray(bundle.downloadLabels)) {
          for (let i = 0; i < bundle.downloadLabels.length; i++) {
            const lbl = bundle.downloadLabels[i] as DownloadLabel;
            if (typeof lbl.label === 'string') {
              ehDownloadStore.addLabel(lbl.label);
              downloadsChanged = true;
            }
          }
        }

        if (Array.isArray(bundle.downloadItems)) {
          for (let i = 0; i < bundle.downloadItems.length; i++) {
            const dl = bundle.downloadItems[i] as DownloadInfo;
            if (typeof dl.gid === 'number' && dl.gid > 0 && typeof dl.token === 'string') {
              ehDownloadStore.importDownload(dl);
              downloadsChanged = true;
            }
          }
        }
        if (downloadsChanged) {
          saves.push(ehDownloadStore.save(context));
        }

        if (importedHistory.length > 0) {
          saves.push(ehHistoryStore.ensureLoaded(context).then(() => {
            for (let i = 0; i < importedHistory.length; i++) {
              ehHistoryStore.addGallery(importedHistory[i], importedHistoryLimit);
            }
            this.showBlockingBusy('Rebuilding imported history metadata...');
            return rebuildImportedHistoryMetadata(context, importedHistory, this.currentGallerySite());
          })
            .then((result: DownloadMetadataRestoreResult) => {
              this.hideBlockingBusy();
              if (result.rebuilt > 0 || result.fetched > 0) {
                this.showFloatingStatus('Imported history metadata rebuilt: ' + result.rebuilt.toString() +
                  ', fetched ' + result.fetched.toString());
              }
            }).catch((error: Error) => {
              this.hideBlockingBusy();
              throw error;
            }));
        }

        if (Array.isArray(bundle.filterRules)) {
          for (let i = 0; i < bundle.filterRules.length; i++) {
            const r = bundle.filterRules[i] as FilterRule;
            if (typeof r.text === 'string' && typeof r.mode === 'number') {
              ehFilterStore.addRule(r.mode, r.text, typeof r.enabled === 'boolean' ? r.enabled : true);
            }
          }
          saves.push(ehFilterStore.save(context));
          this.filterRules = ehFilterStore.getRules();
        }

        if (Array.isArray(bundle.localFavorites)) {
          const localFavorites = bundle.localFavorites;
          saves.push(ehLocalFavoritesStore.ensureLoaded(context).then(() => {
            ehLocalFavoritesStore.importBackupItems(localFavorites);
            return ehLocalFavoritesStore.save(context);
          }));
        }

        if (Array.isArray(bundle.bookmarks)) {
          const bookmarks = bundle.bookmarks;
          saves.push(ehBookmarkStore.ensureLoaded(context).then(() => {
            ehBookmarkStore.importBackupItems(bookmarks);
            return ehBookmarkStore.save(context);
          }));
        }

        Promise.all(saves).then(() => {
          this.showFloatingStatus('Import complete');
        }).catch((error: Error) => {
          this.showFloatingStatus('Import save failed: ' + error.message);
        });

      } catch (error) {
        this.showFloatingStatus('Import failed: ' + String(error));
      }
    }).catch((error: Error) => {
      this.showFloatingStatus('Import picker failed: ' + error.message);
    });
  }

  private normalizedImportedSettingValue(key: string, value: string): string {
    if (key === 'read_cache_size') {
      return normalizeReaderCacheSizeOption(value);
    }
    if (key === HISTORY_INFO_SIZE_KEY) {
      return normalizeHistoryInfoSizeOption(value);
    }
    if (key === 'pattern_protection') {
      return normalizeIdentityAuthenticationOption(value);
    }
    return value;
  }

  private restoreDownloadItems(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Restore download items needs an ability context';
      return;
    }
    const currentLocation = normalizeSettingsDownloadLocation(ehSettingsStore.getValue('download_location',
      DOWNLOAD_LOCATION_APP_FILES));
    this.statusText = currentLocation === DOWNLOAD_LOCATION_APP_FILES ? 'Preparing public Downloads access...' :
      'Scanning downloaded folders...';
    Promise.resolve().then(async () => {
      let downloadsAccess = true;
      if (currentLocation === DOWNLOAD_LOCATION_APP_FILES) {
        downloadsAccess = await this.ensureDownloadLocationAccess(context, DOWNLOAD_LOCATION_DOWNLOADS);
      }
      this.statusText = 'Scanning ZIP archives...';
      this.showBlockingBusy('Scanning ZIP archives...');
      const result: DownloadRestoreResult = await restoreDownloadedItemsAndArchives(context,
        this.currentGallerySite(), downloadsAccess);
      this.hideBlockingBusy();
      let message = 'Restored downloads: ' + result.added.toString() + ' added, ' + result.updated.toString() +
        ' updated, ' + result.migrated.toString() + ' migrated, ' + result.metadataRebuilt.toString() +
        ' metadata rebuilt, ' + downloadSizeText(result.totalBytes) + '.';
      if (result.metadataFetched > 0) {
        message += ' Fetched ' + result.metadataFetched.toString() + ' details.';
      }
      if (result.archives.found > 0) {
        message += result.archives.processed > 0 ?
          ' ZIP archives processed: ' + result.archives.processed.toString() + ', skipped: ' +
            result.archives.skipped.toString() + '.' :
          ' Unprocessed ZIP archives: ' + result.archives.skipped.toString() + '.';
      }
      if (!downloadsAccess) {
        message += ' Downloads access was not granted; scanned app files only.';
      }
      this.showFloatingStatus(message);
      if (result.archives.processed > 0) {
        this.showDeleteProcessedZipDialog(result.archives);
      }
    }).catch((error: Error) => {
      this.hideBlockingBusy();
      this.showFloatingStatus('Restore downloads failed: ' + error.message);
    });
  }

  private showDeleteProcessedZipDialog(result: DownloadZipImportResult): void {
    const message = uiStatusText('ZIP import summary: processed ' + result.processed.toString() + ', skipped ' +
      result.skipped.toString() + '. Delete processed archives?');
    this.getUIContext().getPromptAction().showDialog({
      title: uiText('ZIP archives processed'),
      message: message,
      buttons: [
        {
          text: uiText('Keep'),
          color: themeSecondaryText()
        },
        {
          text: uiText('Delete'),
          color: themePrimaryColor()
        }
      ]
    }).then((data) => {
      if (data.index !== 1) {
        return;
      }
      const removed = ehDownloadFileStore.removeFiles(result.processedPaths);
      this.showFloatingStatus('Deleted processed ZIP archives: ' + removed.toString());
    }).catch(() => {});
  }

  private createAppLogExport(context: common.UIAbilityContext): string {
    const appLog = ehAppLog.read(context);
    const parseBodies = ehParseErrorBodyStore.list(context);
    if (appLog.trim().length === 0 && parseBodies.length === 0) {
      return '';
    }
    const lines: string[] = [];
    lines.push('EhViewer OHOS Diagnostic Log');
    lines.push('ExportedAt: ' + new Date().toISOString());
    lines.push('Version: ' + EH_APP_VERSION_NAME + ' (' + EH_APP_VERSION_CODE.toString() + ')');
    lines.push('Target: ' + EH_TARGET_PLATFORM);
    lines.push('SaveCrashLog: ' + ehSettingsStore.getValue('save_crash_log', 'Off'));
    lines.push('SaveParseErrorBody: ' + ehSettingsStore.getValue('save_parse_error_body', 'Off'));
    lines.push('');
    lines.push('[App Log]');
    lines.push(appLog.trim().length > 0 ? appLog : '(empty)');
    lines.push('');
    lines.push('[Parse Error Bodies]');
    if (parseBodies.length === 0) {
      lines.push('(none)');
    } else {
      for (let i = 0; i < parseBodies.length; i++) {
        const entry: ParseErrorBodyEntry = parseBodies[i];
        lines.push((i + 1).toString() + '. ' + entry.name);
        lines.push('   Path: ' + entry.path);
        lines.push('   Size: ' + downloadSizeText(entry.size));
        lines.push('   Modified: ' + new Date(entry.modifiedTime).toISOString());
      }
    }
    return lines.join('\n');
  }

  private cleanDownloadRedundancy(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showFloatingStatus('Clean redundancy needs an ability context');
      return;
    }
    ehDownloadStore.load(context).then(() => {
      const items = ehDownloadStore.getItems();
      const keepGids: number[] = [];
      for (let i = 0; i < items.length; i++) {
        keepGids.push(items[i].gid);
      }
      const result: DownloadDirectoryScanResult = ehDownloadFileStore.cleanRedundantDirectories(context, keepGids);
      this.settingsRenderRevision++;
      if (result.directories <= 0 && result.files <= 0) {
        this.showFloatingStatus('No redundant downloaded galleries');
        return;
      }
      this.showFloatingStatus('Cleaned redundancy: ' + result.directories.toString() + ' folders, ' +
        result.files.toString() + ' files, ' + downloadSizeText(result.bytes) + '.');
    }).catch((error: Error) => {
      this.showFloatingStatus('Clean redundancy failed: ' + error.message);
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
    this.settingsRenderRevision++;
    this.statusText = 'Cleared cache: ' + pageCount.toString() + ' pages, ' +
      imageResult.files.toString() + ' images, ' + downloadSizeText(imageResult.bytes) + '.';
  }

  private runNetworkDiagnostics(): void {
    this.showFloatingStatus('Running network diagnostics...');
    const context = getAbilityContext();
    this.refreshNetworkRuntime();
    this.client.runNetworkDiagnostics().then((results: NetworkDiagnosticResult[]) => {
      const summary = formatNetworkDiagnostics(results);
      this.statusText = summary;
      if (context === undefined) {
        this.showFloatingStatus('Network diagnostics finished');
        return;
      }
      const content = this.createNetworkDiagnosticLog(results, summary);
      const fileName = 'ehviewer_network_' + diagnosticTimestamp(new Date()) + '.txt';
      this.writeTextToDownloads(context, fileName, content).then((path: string) => {
        this.statusText = 'Network diagnostics exported: ' + path;
        this.showToast('Network diagnostics exported');
      }).catch((error: Error) => {
        this.showFloatingStatus('Network diagnostics export failed: ' + error.message);
        ehAppLog.error(context, DIAGNOSTIC_LOG_TAG, 'Network diagnostics export failed: ' + error.message);
      });
    }).catch((error: Error) => {
      this.showFloatingStatus('Network diagnostics failed: ' + error.message);
      if (context !== undefined) {
        ehAppLog.error(context, DIAGNOSTIC_LOG_TAG, 'Network diagnostics failed: ' + error.message);
      }
    });
  }

  private createNetworkDiagnosticLog(results: NetworkDiagnosticResult[], summary: string): string {
    const lines: string[] = [];
    lines.push('EhViewer OHOS Network Diagnostics');
    lines.push('Time: ' + new Date().toISOString());
    lines.push('Version: ' + EH_APP_VERSION_NAME + ' (' + EH_APP_VERSION_CODE.toString() + ')');
    lines.push('Target: ' + EH_TARGET_PLATFORM);
    lines.push('Gallery site: ' + ehSettingsStore.getValue('gallery_site', 'E-Hentai'));
    lines.push('Proxy: ' + proxyDiagnosticText());
    lines.push('Built-in hosts: ' + ehSettingsStore.getValue('built_in_hosts', 'Off'));
    lines.push('Built EX hosts: ' + ehSettingsStore.getValue('built_ex_hosts', 'Off'));
    lines.push('Domain fronting: ' + ehSettingsStore.getValue('domain_fronting', 'On'));
    lines.push('DNS over HTTPS: ' + currentDnsOverHttpsStatusText());
    lines.push('Direct connection check: ' + ehSettingsStore.getValue('auto_direct_connection', 'On'));
    lines.push('');
    lines.push(summary);
    lines.push('');
    for (let i = 0; i < results.length; i++) {
      const item = results[i];
      lines.push(item.label + ':');
      lines.push('  URL: ' + item.url);
      lines.push('  OK: ' + (item.ok ? 'true' : 'false'));
      lines.push('  Status: ' + (item.statusCode > 0 ? item.statusCode.toString() : 'ERR'));
      lines.push('  Elapsed: ' + item.elapsedMs.toString() + 'ms');
      lines.push('  Message: ' + item.message);
    }
    return lines.join('\n') + '\n';
  }

  private refreshNetworkRuntime(): void {
    const context = getAbilityContext();
    if (!isEhDirectConnectionProbeEnabled()) {
      return;
    }
    startEhDirectConnectionProbe(context).then((directAvailable: boolean) => {
      if (!directAvailable) {
        this.showFloatingStatus('Direct connection unavailable, domain fronting enabled');
        startEhFrontingBenchmark(context);
        return;
      }
      this.showFloatingStatus('Direct connection available, domain fronting disabled');
    }).catch(() => {
      this.showFloatingStatus('Direct connection unavailable, domain fronting enabled');
      startEhFrontingBenchmark(context);
    });
  }

  private addFilterRule(mode: number, draftText: string): boolean {
    const text = draftText.trim();
    if (text.length === 0) {
      this.statusText = 'Enter a filter text first';
      this.showToast(this.statusText);
      return false;
    }
    const added = ehFilterStore.addRule(mode, text);
    if (!added) {
      this.statusText = 'Rule already exists: ' + text;
      this.showToast(this.statusText);
      return false;
    }
    this.filterRules = ehFilterStore.getRules();
    this.filterNewText = '';
    this.filterNewMode = mode;
    this.statusText = 'Filter rule added: ' + text;
    this.showToast(this.statusText);
    this.saveFilterRules();
    return true;
  }

  private removeFilterRule(id: number): void {
    ehFilterStore.removeRule(id);
    this.filterRules = ehFilterStore.getRules();
    this.statusText = 'Filter rule removed';
    this.showToast(this.statusText);
    this.saveFilterRules();
  }

  private toggleFilterRule(id: number): void {
    ehFilterStore.toggleRule(id);
    this.filterRules = ehFilterStore.getRules();
    this.saveFilterRules();
  }

  private setRatingFilterRule(level: number): void {
    const rules = ehFilterStore.getRules();
    for (let i = 0; i < rules.length; i++) {
      if (rules[i].mode === FILTER_MODE_RATING) {
        ehFilterStore.removeRule(rules[i].id);
      }
    }
    if (level > 1) {
      ehFilterStore.addRule(FILTER_MODE_RATING, level.toString());
      this.statusText = 'Filter rule added: ' + level.toString();
    } else {
      this.statusText = 'Filter rule removed';
    }
    this.filterRules = ehFilterStore.getRules();
    this.showToast(this.statusText);
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
    Stack({ alignContent: Alignment.TopStart }) {
      // Main panel always rendered at the bottom so sub-panels can slide over it
      // and returning to Main requires no enter animation — it's already there.
      SettingsHomePanel({
        onMenu: this.onMenu,
        onOpen: (panel: SettingsPanel) => {
          this.openPrimaryPanel(panel);
        }
      })
        .width(this.useSplitLayout() ? this.splitListPaneWidth() : '100%')
        .height('100%')
        .onTouch((event: TouchEvent) => {
          if (shouldUpdateSplitPaneFocus(event)) {
            this.activeSplitPane = SPLIT_PANE_FOCUS_LEFT;
          }
        })
        .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })

      if (this.useSplitLayout()) {
        SplitPaneDivider({
          x: this.splitListPaneWidth(),
          dragging: this.splitDragging,
          fadeTransition: this.restorePanelWithFade,
          onSplitDragStart: () => {
            this.splitDragging = true;
            this.splitDragStartWidth = this.splitListPaneWidth();
          },
          onSplitDragUpdate: (offsetX: number) => {
            this.updateSplitPaneByOffset(offsetX);
          },
          onSplitDragEnd: () => {
            this.finishSplitPaneDrag();
          }
        })
      }

      // Ordinary settings panels stay underneath deeper panels. This keeps EH/Advanced
      // visually fixed while account session, web config, filters, or migration slide over it.
      if (this.settingsDetailLayerPanel() !== SettingsPanel.Main) {
        SettingsDetailPanel({
          panel: this.settingsDetailLayerPanel(),
          signedIn: this.signedIn,
          themeName: this.themeName,
          renderRevision: this.settingsRenderRevision,
          settingEntries: this.settingEntries,
          onBack: () => {
            this.closePanel();
          },
          onOpenSession: () => {
            this.openPanel(SettingsPanel.Session);
          },
          onSignOut: () => {
            this.signOut();
          },
          onCycleSetting: (row: SettingsRowItem) => {
            this.cycleSetting(row);
          },
          onSetSetting: (key: string, value: string) => {
            this.saveSettingValue(key, value);
          }
        })
          .width(this.useSplitLayout() ? this.splitSidePaneWidth() : '100%')
          .height('100%')
          .position({ x: this.useSplitLayout() ? this.splitListPaneWidth() + 1 : 0, y: 0 })
          .onTouch((event: TouchEvent) => {
            if (shouldUpdateSplitPaneFocus(event)) {
              this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
            }
          })
          .zIndex(5)
          .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
          .transition(this.restorePanelWithFade ?
            TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }) :
            TransitionEffect.asymmetric(
              TransitionEffect.move(TransitionEdge.END).animation({ duration: 300, curve: Curve.EaseOut }),
              TransitionEffect.move(TransitionEdge.END).animation({ duration: 240, curve: Curve.EaseIn })))
      }

      // Deeper panels slide over the ordinary settings panel instead of replacing it.
      if (this.panel === SettingsPanel.Filter) {
        FilterPanel({
          rules: this.filterRules,
          newText: this.filterNewText,
          newMode: this.filterNewMode,
          onBack: () => {
            this.closePanel();
          },
          onNewModeChange: (mode: number) => {
            this.filterNewMode = mode;
          },
          onAddText: (mode: number, text: string): boolean => {
            return this.addFilterRule(mode, text);
          },
          onRatingSelect: (level: number) => {
            this.setRatingFilterRule(level);
          },
          onRemove: (id: number) => {
            this.removeFilterRule(id);
          },
          onToggle: (id: number) => {
            this.toggleFilterRule(id);
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .onTouch((event: TouchEvent) => {
            if (shouldUpdateSplitPaneFocus(event)) {
              this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
            }
          })
          .zIndex(10)
          .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
          .transition(TransitionEffect.move(TransitionEdge.END)
            .animation({ duration: 300, curve: Curve.EaseOut }))
      } else if (this.panel === SettingsPanel.WebView) {
        SettingsAccountWebPanel({
          title: this.webViewTitle,
          url: this.webViewUrl,
          onBack: () => {
            this.closePanel();
          },
          onPageEnd: (url: string) => {
            this.captureAccountWebCookies(url);
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .onTouch((event: TouchEvent) => {
            if (shouldUpdateSplitPaneFocus(event)) {
              this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
            }
          })
          .zIndex(10)
          .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
          .transition(TransitionEffect.move(TransitionEdge.END)
            .animation({ duration: 300, curve: Curve.EaseOut }))
      } else if (this.panel === SettingsPanel.MyTags) {
        Column() {
          SettingsSubToolbar({
            title: uiText('My Tags'),
            showAction: true,
            actionIcon: $r('sys.symbol.share'),
            onBack: () => {
              this.closePanel();
            },
            onAction: () => {
              const site = this.currentGallerySite();
              this.openAccountWebPage('My Tags', EhUrl.getHost(site) + 'mytags');
            }
          })
          MyTagsPanel({ site: this.currentGallerySite() })
            .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(themePageBackground())
        .width(this.settingsLayerWidth())
        .position({ x: this.settingsLayerTranslateX(), y: 0 })
        .onTouch((event: TouchEvent) => {
          if (shouldUpdateSplitPaneFocus(event)) {
            this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
          }
        })
        .zIndex(10)
        .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
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
        .width(this.settingsLayerWidth())
        .height('100%')
        .position({ x: this.settingsLayerTranslateX(), y: 0 })
        .onTouch((event: TouchEvent) => {
          if (shouldUpdateSplitPaneFocus(event)) {
            this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
          }
        })
        .zIndex(10)
        .animation({ duration: this.splitDragging ? 0 : 220, curve: Curve.EaseOut })
        .transition(TransitionEffect.move(TransitionEdge.END)
          .animation({ duration: 300, curve: Curve.EaseOut }))
      }

      // Option picker floats on top of everything.
      if (this.optionPickerOpen) {
        SettingsOptionPanel({
          title: this.optionTitle,
          summary: this.optionSummary,
          value: this.optionValue,
          options: this.optionOptions,
          optionDescriptions: this.optionDescriptions,
          allowCustomInput: this.optionAllowCustomInput,
          onBack: () => {
            this.closeOptionPicker();
          },
          onSelect: (value: string) => {
            this.selectOptionValue(value);
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .zIndex(25)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
      }

      if (this.downloadMigrationDialogOpen) {
        DownloadMigrationConfirmOverlay({
          current: this.downloadMigrationCurrent,
          target: this.downloadMigrationTarget,
          onCancel: () => {
            this.closeDownloadMigrationDialog();
            this.statusText = 'Download location change cancelled';
          },
          onSwitchOnly: () => {
            this.chooseDownloadLocationMigration(false);
          },
          onMigrate: () => {
            this.chooseDownloadLocationMigration(true);
          }
        })
          .zIndex(20)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }

      if (this.updateDialogVisible && this.updateRelease !== null) {
        UpdatePromptOverlay({
          release: this.updateRelease,
          currentVersion: this.updateCurrentVersion,
          onCancel: () => {
            this.updateDialogVisible = false;
          },
          onUpdate: () => {
            const release = this.updateRelease;
            this.updateDialogVisible = false;
            if (release !== null) {
              this.openExternalUrl(release.hapDownloadUrl, 'latest HAP');
            }
          }
        })
          .zIndex(30)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }

      if (this.blockingBusyVisible) {
        BlockingBusyOverlay({ message: this.blockingBusyMessage })
          .zIndex(60)
          .transition(TransitionEffect.OPACITY.animation({ duration: 140, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateSceneContentWidth(areaDimensionToVp(newArea.width, (value: number) => this.getUIContext().px2vp(value)));
    })
  }
}

@Component
struct DownloadMigrationConfirmOverlay {
  current: string = DOWNLOAD_LOCATION_APP_FILES;
  target: string = DOWNLOAD_LOCATION_APP_FILES;
  onCancel: () => void = () => {};
  onSwitchOnly: () => void = () => {};
  onMigrate: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(themeScrimColor())
        .onClick(this.onCancel)

      Column() {
        Text(uiText('Download location'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .width('100%')
        Text(uiText('Migrate downloaded files to the new location?'))
          .fontSize(14)
          .fontColor(themeSecondaryText())
          .lineHeight(20)
          .width('100%')
          .margin({ top: 10 })
        Text(uiText('Current') + ': ' + uiValue(this.current) + '  ->  ' + uiText('Target') + ': ' +
          uiValue(this.target))
          .fontSize(12)
          .fontColor(themeTertiaryText())
          .lineHeight(18)
          .width('100%')
          .margin({ top: 8 })

        Row({ space: 8 }) {
          Button(uiText('Cancel'), { type: ButtonType.Normal, stateEffect: true })
            .fontSize(14)
            .fontColor(themePrimaryText())
            .backgroundColor(themeSurfaceVariant())
            .borderRadius(6)
            .layoutWeight(1)
            .onClick(this.onCancel)
          Button(uiText('Switch only'), { type: ButtonType.Normal, stateEffect: true })
            .fontSize(14)
            .fontColor(themePrimaryText())
            .backgroundColor(themeSurfaceVariant())
            .borderRadius(6)
            .layoutWeight(1)
            .onClick(this.onSwitchOnly)
          Button(uiText('Migrate'), { type: ButtonType.Normal, stateEffect: true })
            .fontSize(14)
            .fontColor(themeOnPrimaryText())
            .backgroundColor(themePrimaryColor())
            .borderRadius(6)
            .layoutWeight(1)
            .onClick(this.onMigrate)
        }
        .width('100%')
        .margin({ top: 18 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 420 })
      .padding(18)
      .backgroundColor(themeSurface())
      .borderRadius(8)
      .shadow({
        radius: 18,
        color: '#33000000',
        offsetX: 0,
        offsetY: 8
      })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct SettingsHomePanel {
  onMenu: () => void = () => {};
  onOpen: (panel: SettingsPanel) => void = () => {};

  build() {
    Column() {
      AppToolbar({
        title: 'Settings',
        subtitle: '',
        onMenu: this.onMenu
      })

      List({ space: 8 }) {
        ListItem() {
          Row()
            .height(0)
        }
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
        ListItem() {
          Row()
            .height(0)
        }
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .cachedCount(3)
      .padding({ left: 12, right: 12, top: 0, bottom: 0 })
      .edgeEffect(EdgeEffect.None)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}

@Component
export struct SettingsAccountWebPanel {
  title: string = '';
  url: string = '';
  onBack: () => void = () => {};
  onPageEnd: (url: string) => void = (_url: string) => {};
  private webViewController: webview.WebviewController = new webview.WebviewController();

  build() {
    Column() {
      SettingsSubToolbar({
        title: uiText(this.title),
        onBack: this.onBack
      })
      Web({ src: this.url, controller: this.webViewController })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .backgroundColor(Color.Transparent)
        .onPageEnd((event: OnPageEndEvent) => {
          this.onPageEnd(event.url);
        })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}

@Component
export struct SettingsSubToolbar {
  title: string = '';
  showAction: boolean = false;
  actionIcon: Resource = $r('sys.symbol.share');
  onBack: () => void = () => {};
  onAction: () => void = () => {};

  build() {
    AppSubToolbar({
      title: this.title,
      showAction: this.showAction,
      actionIcon: this.actionIcon,
      onBack: this.onBack,
      onAction: this.onAction
    })
  }
}

@Component
export struct SettingsHeaderRow {
  item: SettingsHeaderItem = { panel: SettingsPanel.Eh, title: '', icon: '', summary: '' };
  onTap: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row() {
        SettingsTextBlock({ title: uiText(this.item.title), summary: uiText(this.item.summary) })
        .layoutWeight(1)
        Text('>')
          .fontSize(16)
          .fontColor(themeTertiaryText())
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(themeSurface())
    .borderRadius(6)
    .onClick(() => {
      this.onTap();
    })
  }
}

@Component
export struct SettingsTextBlock {
  title: string = '';
  summary: string = '';
  isEnabled: boolean = true;

  build() {
    Column() {
      Text(this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isEnabled ? themePrimaryText() : themeTertiaryText())
      Text(this.summary)
        .fontSize(12)
        .fontColor(themeSecondaryText())
        .lineHeight(18)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct SettingsDetailPanel {
  @Prop panel: SettingsPanel = SettingsPanel.Eh;
  @Prop signedIn: boolean = false;
  @Prop themeName: string = 'Light';
  @Prop renderRevision: number = 0;
  @Prop settingEntries: SettingEntry[] = [];
  onBack: () => void = () => {};
  onOpenSession: () => void = () => {};
  onSignOut: () => void = () => {};
  onCycleSetting: (row: SettingsRowItem) => void = () => {};
  onSetSetting: (key: string, value: string) => void = () => {};

  build() {
    Column() {
      AppSubToolbar({
        title: uiText(settingsPanelTitle(this.panel)),
        onBack: this.onBack
      })

      List({ space: 8 }) {
        ListItem() {
          Row()
            .height(0)
        }
        if (this.panel === SettingsPanel.Eh) {
          ListItem() {
            SettingsActionRow({
              title: this.signedIn ? uiText('Account session') : uiText('Sign in'),
              summary: this.signedIn ? uiText('Cookie session is available. Open to replace or inspect cookies.') :
                uiText('Open password, WebView or Cookie sign-in and manage the current session.'),
              value: this.signedIn ? uiText('Signed in') : uiText('Tourist'),
              onTap: this.onOpenSession
            })
          }
          .reuseId('settings-session-action')
          ListItem() {
            SettingsActionRow({
              title: uiText('Sign out'),
              summary: uiText('Clear the persisted identity cookies'),
              value: this.signedIn ? uiText('Available') : uiText('No session'),
              isEnabled: this.signedIn,
              onTap: this.onSignOut
            })
          }
          .reuseId('settings-signout-action')
          ForEach(settingsRowsForPanel(this.panel, this.themeName, this.settingEntries), (row: SettingsRowItem) => {
            ListItem() {
              SettingsStaticRow({
                row: row,
                renderRevision: this.renderRevision,
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
            .reuseId('settings-static-row')
          }, (row: SettingsRowItem) => settingsRowRenderKey(row))
        } else {
          ForEach(settingsRowsForPanel(this.panel, this.themeName, this.settingEntries), (row: SettingsRowItem) => {
            ListItem() {
              SettingsStaticRow({
                row: row,
                renderRevision: this.renderRevision,
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
            .reuseId('settings-static-row')
          }, (row: SettingsRowItem) => settingsRowRenderKey(row))
        }
        ListItem() {
          Row()
            .height(0)
        }
      }
      .edgeEffect(EdgeEffect.None)
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .cachedCount(4)
      .padding({ left: 12, right: 12, top: 0, bottom: 0 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}

@Component
export struct SettingsOptionPanel {
  title: string = '';
  summary: string = '';
  value: string = '';
  options: string[] = [];
  optionDescriptions: string[] = [];
  allowCustomInput: boolean = false;
  @State customValue: string = '';
  onBack: () => void = () => {};
  onSelect: (value: string) => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(themeScrimColor())
        .onClick(this.onBack)

      Column() {
        Row() {
          Text(uiText(this.title))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([themePrimaryText()])
          }
          .width(40)
          .height(40)
          .backgroundColor(themeSurfaceVariant())
          .onClick(this.onBack)
        }
        .width('100%')

        if (this.summary.length > 0) {
          Text(uiText(this.summary))
            .fontSize(13)
            .fontColor(themeSecondaryText())
            .lineHeight(19)
            .width('100%')
            .margin({ top: 6, bottom: 12 })
        }

        List({ space: 8 }) {
          ForEach(this.options, (option: string, index: number) => {
            ListItem() {
              Button({ type: ButtonType.Normal, stateEffect: true }) {
                Row() {
                  Text(uiValue(option))
                    .fontSize(15)
                    .fontWeight(option === this.value ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(option === this.value ? themePrimaryColor() : themePrimaryText())
                    .constraintSize({ minWidth: 78, maxWidth: 118 })
                  if (index < this.optionDescriptions.length && this.optionDescriptions[index].length > 0) {
                    Text(uiText(this.optionDescriptions[index]))
                      .fontSize(12)
                      .fontColor(themeSecondaryText())
                      .maxLines(2)
                      .textAlign(TextAlign.End)
                      .layoutWeight(1)
                      .margin({ left: 8 })
                  } else {
                    Row()
                      .layoutWeight(1)
                  }
                  if (option === this.value) {
                    Text(uiText('Selected'))
                      .fontSize(12)
                      .fontColor(themeOnPrimaryText())
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .backgroundColor(themePrimaryColor())
                      .borderRadius(14)
                      .margin({ left: 8 })
                  }
                }
                .width('100%')
              }
              .width('100%')
              .padding(14)
              .backgroundColor(option === this.value ? themeSelectedBackground() : themeFieldBackground())
              .borderRadius(6)
              .onClick(() => {
                this.onSelect(option);
              })
            }
            .reuseId('settings-option-row')
          }, (option: string) => option)
        }
        .width('100%')
        .constraintSize({ maxHeight: 420 })
        .cachedCount(4)

        if (this.allowCustomInput) {
          Row({ space: 8 }) {
            TextInput({ text: this.customValue, placeholder: uiText('Enter a model name') })
              .height(40)
              .layoutWeight(1)
              .fontSize(14)
              .fontColor(themePrimaryText())
              .backgroundColor(themeFieldBackground())
              .onChange((value: string) => {
                this.customValue = value;
              })
              .onSubmit(() => {
                const value = this.customValue.trim();
                if (value.length > 0) {
                  this.onSelect(value);
                }
              })
            Button(uiText('Use custom value'))
              .height(40)
              .fontSize(13)
              .fontColor(themeOnPrimaryText())
              .backgroundColor(themePrimaryColor())
              .onClick(() => {
                const value = this.customValue.trim();
                if (value.length > 0) {
                  this.onSelect(value);
                }
              })
          }
          .width('100%')
          .margin({ top: 12 })
        }
      }
      .width('86%')
      .constraintSize({ maxWidth: 420, maxHeight: '82%' })
      .padding(18)
      .backgroundColor(themeSurface())
      .borderRadius(8)
      .shadow({
        radius: 18,
        color: '#33000000',
        offsetX: 0,
        offsetY: 8
      })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
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
    Button({ type: ButtonType.Normal, stateEffect: this.isEnabled }) {
      Row() {
        SettingsTextBlock({
          title: this.title,
          summary: this.summary,
          isEnabled: this.isEnabled
        })
        .layoutWeight(1)
        Text(this.value)
          .fontSize(12)
          .fontColor(this.isEnabled ? themeOnPrimaryText() : themeTertiaryText())
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(this.isEnabled ? themePrimaryColor() : themeSurfaceVariant())
          .borderRadius(14)
          .margin({ left: 12 })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(themeSurface())
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
  @Prop renderRevision: number = 0;
  @State inputValue: string = '';
  onTap: () => void = () => {};
  onTextChange: (key: string, value: string) => void = () => {};
  onSwitchChange: (key: string, isOn: boolean) => void = () => {};
  onOptionSelect: (key: string, value: string) => void = () => {};
  private committedInputValue: string = '';

  aboutToAppear(): void {
    this.inputValue = this.row.value;
    this.committedInputValue = this.row.value;
  }

  private commitInputValue(): void {
    if (this.row.key === undefined) {
      return;
    }
    const value = isSecretSettingKey(this.row.key) ? this.inputValue : this.inputValue.trim();
    if (value === this.committedInputValue) {
      return;
    }
    this.committedInputValue = value;
    this.onTextChange(this.row.key, value);
  }

  build() {
    Column() {
      Row() {
        SettingsTextBlock({
          title: uiText(this.row.title),
          summary: uiText(this.row.summary)
        })
        .layoutWeight(1)
        if (this.row.type === 'input') {
          TextInput({ text: this.inputValue, placeholder: uiText(this.row.summary) })
            .width(150)
            .height(38)
            .type(isSecretSettingKey(this.row.key) ? InputType.Password : InputType.Normal)
            .fontSize(13)
            .fontColor(themePrimaryText())
            .placeholderColor(themeSecondaryText())
            .backgroundColor(themeFieldBackground())
            .margin({ left: 12 })
            .onChange((value: string) => {
              this.inputValue = value;
            })
            .onSubmit(() => {
              this.commitInputValue();
            })
            .onBlur(() => {
              this.commitInputValue();
            })
        } else if (this.row.type === 'switch') {
          Row() {
            Text(this.row.value === 'On' ? uiText('On') : uiText('Off'))
              .fontSize(12)
              .fontColor(this.row.value === 'On' ? themePrimaryColor() : themeTertiaryText())
              .margin({ right: 8 })
            Toggle({ type: ToggleType.Switch, isOn: this.row.value === 'On' })
              .selectedColor(themePrimaryColor())
              .switchPointColor(Color.White)
              .onChange((isOn: boolean) => {
                if (this.row.key !== undefined) {
                  this.onSwitchChange(this.row.key, isOn);
                }
              })
          }
          .alignItems(VerticalAlign.Center)
          .margin({ left: 12 })
        } else if (this.row.type === 'slider') {
          SettingsInlineSlider({
            row: this.row,
            onOptionSelect: this.onOptionSelect
          })
            .margin({ left: 12 })
        } else if ((this.row.type === 'list' && this.row.options !== undefined && this.row.options.length > 0) ||
          this.row.type === 'model') {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 6 }) {
              Text(uiValue(this.row.value))
                .fontSize(13)
                .fontColor(themeSecondaryText())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(14)
                .fontColor([themeSecondaryText()])
            }
          }
            .height(34)
            .constraintSize({ maxWidth: 190 })
            .padding({ left: 12, right: 10 })
            .backgroundColor(themeSurfaceVariant())
            .borderRadius(17)
            .margin({ left: 8 })
            .onClick(() => {
              this.onTap();
            })
        } else if (this.row.type === 'info') {
          Text(uiValue(this.row.value))
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .maxLines(2)
            .textAlign(TextAlign.End)
            .margin({ left: 12 })
        } else {
          Button(settingsRowActionText(this.row), { type: ButtonType.Normal, stateEffect: true })
            .height(34)
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .backgroundColor(themeSurfaceVariant())
            .borderRadius(17)
            .margin({ left: 12 })
            .onClick(() => {
              this.onTap();
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(themeSurface())
    .borderRadius(6)
    .onClick(() => {
      if (this.row.type !== 'input' && this.row.type !== 'switch' && this.row.type !== 'info' &&
        this.row.type !== 'slider' && this.row.key !== 'theme') {
        this.onTap();
      }
    })
  }
}

@Component
struct SettingsInlineSlider {
  row: SettingsRowItem = { title: '', summary: '', value: '', type: '' };
  onOptionSelect: (key: string, value: string) => void = () => {};
  @State liveValue: number = 0;

  aboutToAppear(): void {
    this.liveValue = settingsSliderNumberValue(this.row);
  }

  build() {
    Row() {
      Slider({
        value: this.liveValue,
        min: settingsSliderMin(this.row),
        max: settingsSliderMax(this.row),
        step: 1
      })
        .width(150)
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.liveValue = Math.round(value);
          if (this.row.key !== undefined) {
            this.onOptionSelect(this.row.key, settingsSliderTextValue(this.row, this.liveValue));
          }
        })
      Text(settingsSliderDisplayText(this.row, this.liveValue))
        .fontSize(12)
        .fontColor(themePrimaryColor())
        .width(42)
        .textAlign(TextAlign.End)
    }
    .alignItems(VerticalAlign.Center)
  }
}

function settingsRowActionText(row: SettingsRowItem): string {
  if (row.value.length > 0) {
    return uiValue(row.value);
  }
  return uiText('Open');
}

function isSecretSettingKey(key: string | undefined): boolean {
  return key === 'proxy_password' || key === 'translation_deepseek_api_key' ||
    key === 'translation_openai_api_key' || key === 'translation_official_openai_api_key' ||
    key === 'translation_custom_api_key' || key === 'translation_gemini_api_key';
}

function isCustomTranslationApiField(key: string): boolean {
  return key === 'translation_custom_api_name' || key === 'translation_custom_api_base_url' ||
    key === 'translation_custom_api_key' || key === 'translation_custom_api_model';
}

function isTranslationSettingKey(key: string): boolean {
  return key.indexOf('translation_') === 0;
}

function settingsSliderNumberValue(row: SettingsRowItem): number {
  if (row.key === 'start_transfer_time') {
    return Number.parseInt(normalizeAutoTransferTimeOption(row.value));
  }
  if (row.key === 'screen_lightness') {
    return Number.parseInt(normalizeBrightnessLevelOption(row.value));
  }
  return 0;
}

function settingsSliderMin(row: SettingsRowItem): number {
  return row.key === 'start_transfer_time' ? 1 : 0;
}

function settingsSliderMax(row: SettingsRowItem): number {
  return row.key === 'start_transfer_time' ? 20 : 100;
}

function settingsSliderTextValue(row: SettingsRowItem, value: number): string {
  if (row.key === 'start_transfer_time') {
    return normalizeAutoTransferTimeOption(Math.max(1, Math.min(20, Math.round(value))).toString() + 's');
  }
  return normalizeBrightnessLevelOption(Math.max(0, Math.min(100, Math.round(value))).toString() + '%');
}

function settingsSliderDisplayText(row: SettingsRowItem, value: number): string {
  return uiValue(settingsSliderTextValue(row, value));
}

function normalizeSettingsDownloadLocation(value: string): string {
  return value === DOWNLOAD_LOCATION_DOWNLOADS ? DOWNLOAD_LOCATION_DOWNLOADS : DOWNLOAD_LOCATION_APP_FILES;
}

function diagnosticTimestamp(now: Date): string {
  return now.getFullYear().toString() + padTwo(now.getMonth() + 1) + padTwo(now.getDate()) + '_' +
    padTwo(now.getHours()) + padTwo(now.getMinutes()) + padTwo(now.getSeconds());
}

async function pickDownloadsOutputPath(context: common.UIAbilityContext, fileName: string): Promise<string> {
  const saveOptions = new picker.DocumentSaveOptions();
  saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
  const documentPicker = new picker.DocumentViewPicker(context);
  const result = await documentPicker.save(saveOptions);
  if (result.length === 0 || result[0].length === 0) {
    return '';
  }
  return new fileUri.FileUri(result[0] + '/' + sanitizeExportFileName(fileName)).path;
}

function sanitizeExportFileName(fileName: string): string {
  return fileName.replace(/[\\/:*?"<>|]/g, '_');
}

async function writeTextFileChunked(path: string, content: string): Promise<void> {
  let fd = -1;
  try {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    fd = file.fd;
    for (let start = 0; start < content.length; start += LOG_EXPORT_CHUNK_BYTES) {
      fs.writeSync(fd, content.substring(start, Math.min(content.length, start + LOG_EXPORT_CHUNK_BYTES)));
      await yieldToUi();
    }
  } catch (error) {
    removeFileQuietly(path);
    throw new Error(String(error));
  } finally {
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (error) {
      }
    }
  }
}

function removeFileQuietly(path: string): void {
  try {
    fs.unlinkSync(path);
  } catch (error) {
  }
}

function yieldToUi(): Promise<void> {
  return new Promise<void>((resolve: (value: void | PromiseLike<void>) => void) => {
    setTimeout(() => {
      resolve();
    }, 0);
  });
}

function settingsRowRenderKey(row: SettingsRowItem): string {
  if (row.type === 'slider') {
    return row.title + ':' + row.type;
  }
  return row.title + ':' + row.value + ':' + row.type;
}

function isNetworkSettingKey(key: string): boolean {
  return key === 'proxy' || key === 'proxy_host' || key === 'proxy_port' || key === 'proxy_username' ||
    key === 'proxy_password' || key === 'proxy_exclusion_list' || key === 'built_in_hosts' ||
    key === 'built_ex_hosts' || key === 'dns_over_https' || key === 'domain_fronting' ||
    key === 'auto_direct_connection' || key === 'gallery_site';
}

function normalizeProxyExclusionListText(value: string): string {
  const parts = value.split(',');
  const result: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const item = parts[i].trim();
    if (item.length > 0 && result.indexOf(item) < 0) {
      result.push(item);
    }
  }
  return result.join(',');
}

function proxyDiagnosticText(): string {
  const proxy = normalizeProxyOption(ehSettingsStore.getValue('proxy', 'System'));
  if (proxy !== 'HTTP') {
    return proxy;
  }
  const host = ehSettingsStore.getValue('proxy_host', '').trim();
  const port = ehSettingsStore.getValue('proxy_port', '').trim();
  const username = ehSettingsStore.getValue('proxy_username', '').trim();
  const exclusions = ehSettingsStore.getValue('proxy_exclusion_list', '').trim();
  let text = 'HTTP ' + (host.length > 0 ? host : '(missing host)') + ':' + (port.length > 0 ? port : '(missing port)');
  if (username.length > 0) {
    text += ' user=' + username + ' password=***';
  }
  if (exclusions.length > 0) {
    text += ' exclusions=' + exclusions;
  }
  return text;
}

function settingDisplayValueForStatus(key: string, value: string): string {
  if (isSecretSettingKey(key) && value.length > 0) {
    return '***';
  }
  return value;
}

