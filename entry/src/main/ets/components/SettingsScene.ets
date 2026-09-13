import { common } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { GalleryInfo, GallerySite } from '../model/GalleryModels';
import { ehBookmarkStore } from '../services/EhBookmarkStore';
import { BrowsePositionsBackupInfo, ehBrowsePositionStore } from '../services/EhBrowsePositionStore';
import { ehCookieStore } from '../services/EhCookieStore';
import {
  DOWNLOAD_LOCATION_APP_FILES,
  DOWNLOAD_LOCATION_DOWNLOADS,
  DownloadDirectoryScanResult,
  DownloadMigrationProgress,
  ehDownloadFileStore,
} from '../services/EhDownloadFileStore';
import { DownloadInfo, DownloadLabel, ehDownloadStore } from '../services/EhDownloadStore';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehSearchHistoryStore } from '../services/EhSearchHistoryStore';
import { ehLocalFavoritesStore } from '../services/EhLocalFavoritesStore';
import {
  DownloadMetadataRestoreResult,
  rebuildImportedHistoryMetadata,
} from '../services/DownloadMetadataRestore';
import {
  DownloadRestoreResult,
  DownloadZipImportResult,
  restoreDownloadedItemsAndArchives,
} from '../services/DownloadZipImportService';
import {
  FLOATING_ACTION_HOLDING_HAND_REVISION_KEY,
  FLOATING_ACTION_HOLDING_HAND_SETTING_KEY,
  MULTI_DEVICE_CONTINUATION_SETTING_KEY,
  HISTORY_INFO_SIZE_KEY,
  ehSettingsStore,
  historyInfoSizeLimitFromValue,
  normalizeHistoryInfoSizeOption,
  SettingImportResult,
  SettingEntry,
  defaultSettingEntries,
} from '../services/EhSettingsStore';
import {
  SavedTranslationApi,
  cloneSavedTranslationApis,
  createSavedTranslationApi,
  findSavedTranslationApi,
  parseSavedTranslationApis,
  serializeSavedTranslationApis,
  uniqueTranslationApiName,
} from '../services/TranslationSupport';
import {
  allReaderPresetProfiles,
  applyReaderPresetValues,
  findReaderPresetProfile,
  READER_CUSTOM_PRESETS_SETTING_KEY,
} from '../services/ReaderPresetSupport';
import { EhHttpClient, NetworkDiagnosticResult } from '../services/EhHttpClient';
import {
  currentDnsOverHttpsStatusText,
  ensureEhHostRules,
  isEhDirectConnectionProbeEnabled,
  socks5ProxySupported,
  startEhDirectConnectionProbe,
  startEhFrontingBenchmark,
} from '../services/EhNetworkConfig';
import { EhUrl } from '../services/EhUrl';
import { ehUpdateChecker, ReleaseInfo, UpdateCheckResult } from '../services/EhUpdateChecker';
import {
  ehTagTranslationStore,
  EhTagTranslationUpdatePhase,
  EhTagTranslationUpdateResult,
} from '../services/EhTagTranslationStore';
import {
  effectiveAiTranslationProvider,
  ehTranslationService,
} from '../services/EhTranslationService';
import {
  AI_TRANSLATION_CONVERSATION_LOG_SETTING_KEY,
  aiTranslationConversationLog,
} from '../services/AiTranslationConversationLog';
import {
  READER_OCR_DEBUG_LOG_SETTING_KEY,
  readerOcrDebugLog,
} from '../services/ReaderOcrDebugLog';
import { galleryPageCache } from '../services/GalleryPageCache';
import { CacheClearResult, CachePruneResult, readerImageCache } from '../services/ReaderImageCache';
import { FilterRule, FILTER_MODE_RATING, FILTER_MODE_TITLE, FILTER_RULE_REVISION_KEY, ehFilterStore } from '../services/EhFilterStore';
import { ehCommentBlacklistStore } from '../services/EhCommentBlacklistStore';
import {
  applyAppChromeImmersiveMode,
  applyAppColorMode,
  mainContentWidthFallbackVp,
  rememberMainContentWidthVp,
} from '../services/EhWindowImmersive';
import { applyWindowPrivacyMode } from '../services/EhWindowPrivacy';
import { ehAppLog } from '../services/EhAppLog';
import { applyMissionContinuationSetting } from '../services/DistributedContinuationService';
import { ehParseErrorBodyStore, ParseErrorBodyEntry } from '../services/EhParseErrorBodyStore';
import {
  AndroidDataImportSummary,
  importAndroidDatabaseBackup,
  isAndroidDatabaseBackup,
} from '../services/AndroidDataImporter';
import {
  EH_APP_VERSION_CODE,
  EH_APP_VERSION_NAME,
  EH_AUTHOR_NAME,
  EH_AUTHOR_URL,
  EH_ISSUES_URL,
  EH_RELEASE_URL,
  EH_REPOSITORY_URL,
  EH_TARGET_PLATFORM,
} from '../services/EhBuildInfo';
import {
  IDENTITY_AUTH_LOCKED_KEY,
  LANGUAGE_REVISION_KEY,
  notifyGalleryTitleChanged,
  notifyLanguageChanged,
  notifyThemeChanged,
} from '../shared/EhShared';
import {
  currentThemeName,
  themePageBackground,
  themeAccentTextColor,
  themeSecondaryText,
} from '../shared/EhTheme';
import { EhBackupBundle, SessionMode, SettingsRowItem, SettingsPanel, SETTINGS_HEADERS, uiText, uiStatusText, setActiveBackHandler, padTwo, getAbilityContext, downloadSizeText, settingEntryValue, cloneStringOptions, isValidProxyHostText, isValidProxyPortText, normalizeProxyOption, formatNetworkDiagnostics, normalizeIdentityAuthenticationOption, normalizeReaderCacheSizeOption } from '../shared/EhShared';
import { FilterPanel } from './FilterPanel';
import { BlockingBusyOverlay } from './BlockingBusyOverlay';
import { ConfirmActionOverlay } from './ConfirmActionOverlay';
import { MyTagsPanel } from './MyTagsPanel';
import { ReaderPresetPanel } from './ReaderPresetPanel';
import {
  captureEhAccountWebCookies,
  clearWebSessionCookies,
  prepareEhAccountWebViewCookies,
  SessionScene,
} from './SessionScene';
import { UpdatePromptOverlay } from './UpdatePromptOverlay';
import { WifiMigrationPanel } from './WifiMigrationPanel';
import { RemoteStoragePanel } from './RemoteStoragePanel';
import { CommentBlacklistPanel } from './CommentBlacklistPanel';
import {
  areaDimensionToVp,
  markCurrentRouteRightPane,
  normalizeSplitPaneFocus,
  saveSplitPaneRatio,
  SPLIT_PANE_BREAKPOINT,
  SPLIT_PANE_FOCUS_LEFT,
  SPLIT_PANE_FOCUS_RIGHT,
  SPLIT_PANE_MODAL_Z_INDEX,
  SPLIT_PANE_RATIO_REVISION_KEY,
  shouldFadeRestoredRightPane,
  splitPaneCurrentRatio,
  SplitPaneDivider,
  splitPaneListWidth,
  splitPaneModeEnabled,
  splitPaneRatioForWidth,
  splitPaneSideWidth,
  splitPaneWidthFromDrag,
  shouldUpdateSplitPaneFocus,
} from './SplitPaneSupport';
import {
  DIAGNOSTIC_LOG_TAG,
  EH_LICENSE_URL,
  isDirectTranslationApiKey,
  cleanErrorMessage,
  isCustomTranslationApiField,
  isTranslationSettingKey,
  normalizeSettingsDownloadLocation,
  diagnosticTimestamp,
  pickDownloadsOutputPath,
  writeTextFileChunked,
  isNetworkSettingKey,
  normalizeProxyExclusionListText,
  proxyDiagnosticText,
  settingDisplayValueForStatus,
} from './SettingsSupport';
import {
  ProxySettingsOverlay,
  DownloadMigrationConfirmOverlay,
  TranslationPromptPanel,
} from './SettingsOverlays';
import {
  SettingsHomePanel,
  SettingsAccountWebPanel,
  SettingsSubToolbar,
  SettingsDetailPanel,
  SettingsOptionPanel,
} from './SettingsPanels';

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
  sessionInitialMode: SessionMode;
  homeScrollOffset: number;
  detailScrollOffsets: Map<string, number>;
}

let settingsNavigationCache: SettingsNavigationCache | null = null;
let settingsHomeScrollOffset: number = 0;
const settingsDetailScrollOffsets: Map<string, number> = new Map<string, number>();


@Component
export struct SettingsScene {
  @State panel: SettingsPanel = SettingsPanel.Main;
  @State panelStack: SettingsPanel[] = [SettingsPanel.Main];
  @State signedIn: boolean = ehCookieStore.hasCookies();
  @State statusText: string = '';
  @State blockingBusyVisible: boolean = false;
  @State blockingBusyMessage: string = 'Loading...';
  @State blockingBusyProgressText: string = '';
  @State blockingBusyProgressCurrent: number = -1;
  @State blockingBusyProgressTotal: number = -1;
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
  @State proxySettingsOpen: boolean = false;
  @State downloadMigrationDialogOpen: boolean = false;
  @State downloadMigrationCurrent: string = DOWNLOAD_LOCATION_APP_FILES;
  @State downloadMigrationTarget: string = DOWNLOAD_LOCATION_APP_FILES;
  @State signOutConfirmationVisible: boolean = false;
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
  @State sessionInitialMode: SessionMode = SessionMode.Password;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp(SPLIT_PANE_RATIO_REVISION_KEY) @Watch('onSplitPaneRatioRevisionChange') splitPaneRatioRevision: number = 0;
  private client: EhHttpClient = new EhHttpClient();
  private splitDragStartWidth: number = 0;
  private modelPickerRequestVersion: number = 0;
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
    if (this.blockingBusyVisible) {
      return true;
    }
    if (this.signOutConfirmationVisible) {
      this.signOutConfirmationVisible = false;
      return true;
    }
    if (this.proxySettingsOpen) {
      this.closeProxySettings();
      return true;
    }
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
    this.proxySettingsOpen = false;
    this.downloadMigrationDialogOpen = false;
    this.signOutConfirmationVisible = false;
    this.updateDialogVisible = false;
    this.webViewUrl = '';
    this.webViewTitle = '';
    this.sessionInitialMode = SessionMode.Password;
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
    this.proxySettingsOpen = false;
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
    this.proxySettingsOpen = false;
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
    this.sessionInitialMode = settingsNavigationCache.sessionInitialMode;
    settingsHomeScrollOffset = Math.max(0, settingsNavigationCache.homeScrollOffset);
    settingsDetailScrollOffsets.clear();
    settingsNavigationCache.detailScrollOffsets.forEach((offset: number, key: string) => {
      settingsDetailScrollOffsets.set(key, Math.max(0, offset));
    });
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
      filterNewMode: this.filterNewMode,
      sessionInitialMode: this.sessionInitialMode,
      homeScrollOffset: settingsHomeScrollOffset,
      detailScrollOffsets: new Map<string, number>(settingsDetailScrollOffsets)
    };
  }

  private updateHomeScrollOffset(offset: number): void {
    settingsHomeScrollOffset = Math.max(0, offset);
    this.saveNavigationCache();
  }

  private updateDetailScrollOffset(panel: SettingsPanel, offset: number): void {
    settingsDetailScrollOffsets.set(panel, Math.max(0, offset));
    this.saveNavigationCache();
  }

  private clearNavigationCache(): void {
    settingsNavigationCache = null;
    settingsHomeScrollOffset = 0;
    settingsDetailScrollOffsets.clear();
  }

  private restoreBackHandler(): void {
    setTimeout(() => {
      setActiveBackHandler(() => this.handleSystemBack());
    }, 0);
  }

  private settingsDetailLayerPanel(): SettingsPanel {
    for (let i = this.panelStack.length - 1; i >= 0; i--) {
      // Keep the ordinary settings list mounted while a deeper page covers it.
      for (let j = 0; j < SETTINGS_HEADERS.length; j++) {
        if (this.panelStack[i] === SETTINGS_HEADERS[j].panel) {
          return this.panelStack[i];
        }
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
    this.signOutConfirmationVisible = false;
    clearWebSessionCookies(false);
    clearWebSessionCookies(true);
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
      if (value === 'Remote server') {
        this.commitSettingValue(key, value);
        return;
      }
      this.requestDownloadLocationChange(value);
      return;
    }
    this.commitSettingValue(key, value);
  }

  private updateSettingDraft(key: string, value: string): void {
    if (isDirectTranslationApiKey(key)) {
      ehSettingsStore.setValue(key, value);
    }
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
    const previousValue = ehSettingsStore.getValue(key, '');
    ehSettingsStore.setValue(key, normalizedValue);
    if (key === MULTI_DEVICE_CONTINUATION_SETTING_KEY) {
      applyMissionContinuationSetting(getAbilityContext());
    }
    if (key === FLOATING_ACTION_HOLDING_HAND_SETTING_KEY && normalizedValue !== previousValue) {
      const revision = AppStorage.get<number>(FLOATING_ACTION_HOLDING_HAND_REVISION_KEY) ?? 0;
      AppStorage.setOrCreate<number>(FLOATING_ACTION_HOLDING_HAND_REVISION_KEY, revision + 1);
    }
    if (key === AI_TRANSLATION_CONVERSATION_LOG_SETTING_KEY && normalizedValue !== 'On') {
      aiTranslationConversationLog.clear(getAbilityContext());
    }
    if (key === READER_OCR_DEBUG_LOG_SETTING_KEY && normalizedValue !== 'On') {
      readerOcrDebugLog.clear(getAbilityContext());
    }
    if (key === 'translation_ai_provider' && normalizedValue === 'Custom API') {
      this.ensureCustomTranslationApi();
    }
    if (key === 'translation_buttons_enabled' && normalizedValue !== 'On') {
      ehTranslationService.setEnabled(false);
    }
    if (key === 'translation_buttons_enabled' && normalizedValue === 'On' && previousValue !== 'On') {
      this.showToast('The translation toggle is in the lower-right toolbar');
    }
    if (isTranslationSettingKey(key)) {
      ehTranslationService.clearCache();
    }
    if (key === 'follow_system_dark_mode' && normalizedValue === 'On' &&
      ehSettingsStore.getValue('theme', 'Light') === 'Light') {
      ehSettingsStore.setValue('theme', 'Dark');
    }
    if (key === 'reading_direction' && normalizedValue === 'Top to bottom' &&
      ehSettingsStore.getValue('adaptive_dual_page', 'Off') !== 'On') {
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
    if (key === 'theme' || key === 'theme_color' || key === 'follow_system_dark_mode' || key === 'ui_style') {
      notifyThemeChanged();
      this.settingsRenderRevision++;
      applyAppChromeImmersiveMode();
      applyAppColorMode(getAbilityContext());
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
      if (key === 'theme' || key === 'theme_color' || key === 'follow_system_dark_mode' || key === 'ui_style') {
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
    const adaptiveDualPage = key === 'adaptive_dual_page' ? value === 'On' :
      settingEntryValue(this.settingEntries, 'adaptive_dual_page', 'Off') === 'On';
    if (adaptiveDualPage && key === 'screen_rotation' && value === 'Match image') {
      return 'Default';
    }
    if (adaptiveDualPage && key === 'reading_direction' && value === 'Top to bottom') {
      return 'Right to left';
    }
    if (adaptiveDualPage && key === 'page_scaling') {
      return 'Fit screen';
    }
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
        const result = await ehDownloadFileStore.migrateDownloadLocation(context, current, target,
          (progress: DownloadMigrationProgress) => {
            this.updateDownloadMigrationProgress(progress);
          });
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
    prepareEhAccountWebViewCookies(url);
  }

  private captureAccountWebCookies(url: string): void {
    if (!captureEhAccountWebCookies(url)) {
      return;
    }

    this.signedIn = ehCookieStore.hasCookies();
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehCookieStore.save(context).catch(() => {
    });
  }

  private closeOptionPicker(): void {
    this.modelPickerRequestVersion++;
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
    const provider = effectiveAiTranslationProvider();
    const requestVersion = ++this.modelPickerRequestVersion;
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
      if (requestVersion !== this.modelPickerRequestVersion || !this.optionPickerOpen ||
        this.optionKey !== row.key) {
        return;
      }
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
      this.showFloatingStatus(models.length > 0 ? 'Available models loaded: ' + models.length.toString() :
        'No available models were returned');
    }).catch((error: Error) => {
      if (requestVersion !== this.modelPickerRequestVersion || !this.optionPickerOpen ||
        this.optionKey !== row.key) {
        return;
      }
      const message = cleanErrorMessage(error);
      if (message === 'Translation API key is missing' || message === 'No custom translation API is selected') {
        this.showFloatingStatus(message);
      } else {
        this.showFloatingStatus('Model list request failed: ' + message);
      }
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
      this.sessionInitialMode = SessionMode.Cookie;
      this.openPanel(SettingsPanel.Session);
      return true;
    }
    if (key === 'network_diagnostics') {
      this.runNetworkDiagnostics();
      return true;
    }
    if (key === 'proxy_settings') {
      this.openProxySettings();
      return true;
    }
    if (key === 'remote_storage') {
      this.openPanel(SettingsPanel.RemoteStorage);
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
    if (key === 'update_tag_translation_database') {
      this.updateTagTranslationDatabase();
      return true;
    }
    if (key === 'translation_test') {
      this.testTranslationProvider();
      return true;
    }
    if (key === 'translation_ai_log_export') {
      this.exportAiTranslationRecords();
      return true;
    }
    if (key === 'reader_ocr_debug_export') {
      this.exportReaderOcrDebugRecords();
      return true;
    }
    if (key === 'translation_prompt_settings') {
      this.openPanel(SettingsPanel.TranslationPrompt);
      return true;
    }
    if (key === 'reader_presets') {
      this.openPanel(SettingsPanel.ReaderPresets);
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
    if (key === 'comment_blacklist') {
      const context = getAbilityContext();
      if (context === undefined) {
        this.openPanel(SettingsPanel.CommentBlacklist);
        return true;
      }
      ehCommentBlacklistStore.ensureLoaded(context).then(() => {
        this.openPanel(SettingsPanel.CommentBlacklist);
      }).catch((error: Error) => {
        this.openPanel(SettingsPanel.CommentBlacklist);
        this.statusText = 'Comment blacklist load warning: ' + error.message;
      });
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
      this.openPanel(SettingsPanel.WifiTransfer);
      return true;
    }
    return false;
  }

  private testTranslationProvider(): void {
    this.statusText = uiText('Testing translation...');
    ehTranslationService.clearCache();
    ehTranslationService.testTranslation('Hello, world.').then((translated: string) => {
      this.statusText = uiText('Translation test succeeded') + ': ' + translated;
      this.showToast(this.statusText);
    }).catch((error: Error) => {
      this.statusText = uiText('Translation test failed') + ': ' + error.message;
      this.showToast(this.statusText);
    });
  }

  private saveTranslationPrompt(selectedId: string, customProfiles: string, status: string): void {
    ehSettingsStore.setValue('translation_prompt_selected', selectedId);
    ehSettingsStore.setValue('translation_prompt_custom_profiles', customProfiles);
    this.settingEntries = ehSettingsStore.getEntries();
    ehTranslationService.clearCache();
    this.showFloatingStatus(status);
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSettingsStore.save(context).catch((error: Error) => {
        this.showFloatingStatus('Save failed: ' + error.message);
      });
    }
  }

  private saveReaderPresets(customProfiles: string, status: string): void {
    ehSettingsStore.setValue(READER_CUSTOM_PRESETS_SETTING_KEY, customProfiles);
    this.settingEntries = ehSettingsStore.getEntries();
    this.showFloatingStatus(status);
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSettingsStore.save(context).catch((error: Error) => {
        this.showFloatingStatus('Save failed: ' + error.message);
      });
    }
  }

  private applyReaderPreset(profileId: string): void {
    const customProfiles = ehSettingsStore.getValue(READER_CUSTOM_PRESETS_SETTING_KEY, '[]');
    const profile = findReaderPresetProfile(allReaderPresetProfiles(customProfiles), profileId);
    if (profile === null) {
      return;
    }
    applyReaderPresetValues(profile.values);
    this.settingEntries = ehSettingsStore.getEntries();
    this.settingsRenderRevision++;
    this.showFloatingStatus('Reading preset applied');
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSettingsStore.save(context).catch((error: Error) => {
        this.showFloatingStatus('Save failed: ' + error.message);
      });
    }
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
      ehCookieStore.ensureLoaded(context),
      ehSettingsStore.ensureLoaded(context),
      ehHistoryStore.ensureLoaded(context),
      ehSearchHistoryStore.load(context),
      ehDownloadStore.load(context),
      ehFilterStore.ensureLoaded(context),
      ehLocalFavoritesStore.ensureLoaded(context),
      ehBookmarkStore.ensureLoaded(context),
      ehCommentBlacklistStore.ensureLoaded(context),
      ehBrowsePositionStore.ensureLoaded(context)
    ]).then(() => {
      const bundle: EhBackupBundle = {
        version: 2,
        exportedAt: now.toISOString(),
        cookies: ehCookieStore.getTransferCookieHeader(),
        settings: ehSettingsStore.getTransferEntries(),
        history: ehHistoryStore.getItems(),
        readingProgress: ehHistoryStore.getReadingProgressBackupItems(),
        searchHistory: ehSearchHistoryStore.getKeywords(),
        browsePositions: ehBrowsePositionStore.getBackupInfo(),
        downloadItems: ehDownloadStore.getItems(),
        downloadLabels: ehDownloadStore.getLabels(),
        filterRules: ehFilterStore.getRules(),
        localFavorites: ehLocalFavoritesStore.getBackupItems(),
        bookmarks: ehBookmarkStore.getBackupItems(),
        commentBlacklist: ehCommentBlacklistStore.getBackupItems()
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
    this.blockingBusyProgressText = '';
    this.blockingBusyProgressCurrent = -1;
    this.blockingBusyProgressTotal = -1;
    this.blockingBusyVisible = true;
  }

  private hideBlockingBusy(): void {
    this.blockingBusyVisible = false;
    this.blockingBusyMessage = 'Loading...';
    this.blockingBusyProgressText = '';
    this.blockingBusyProgressCurrent = -1;
    this.blockingBusyProgressTotal = -1;
  }

  private updateDownloadMigrationProgress(progress: DownloadMigrationProgress): void {
    if (progress.phase === 'scanning') {
      this.blockingBusyMessage = 'Scanning downloaded files...';
      this.blockingBusyProgressText = '';
      this.blockingBusyProgressCurrent = -1;
      this.blockingBusyProgressTotal = -1;
      return;
    }
    const countText = progress.files.toString() + ' / ' + progress.totalFiles.toString();
    const sizeText = downloadSizeText(progress.bytes) + ' / ' + downloadSizeText(progress.totalBytes);
    this.blockingBusyProgressText = countText + ' · ' + sizeText;
    if (progress.phase === 'cleaning') {
      this.blockingBusyMessage = 'Cleaning migrated source files...';
      this.blockingBusyProgressCurrent = progress.totalBytes > 0 ? progress.totalBytes : progress.totalFiles;
      this.blockingBusyProgressTotal = progress.totalBytes > 0 ? progress.totalBytes : progress.totalFiles;
      return;
    }
    this.blockingBusyMessage = 'Migrating downloaded files...';
    this.blockingBusyProgressCurrent = progress.totalBytes > 0 ? progress.bytes : progress.files;
    this.blockingBusyProgressTotal = progress.totalBytes > 0 ? progress.totalBytes : progress.totalFiles;
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
              ', labels ' + summary.labels + ', filters ' + summary.filters + ', bookmarks ' + summary.bookmarks +
              ', comment blacklist ' + summary.blacklist + ')');
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
          const importedCookies = bundle.cookies;
          saves.push(ehCookieStore.ensureLoaded(context).then(() => {
            ehCookieStore.setTransferCookieHeader(importedCookies);
            this.signedIn = ehCookieStore.hasCookies();
            return ehCookieStore.save(context);
          }));
        }

        if (Array.isArray(bundle.settings)) {
          const settingResult: SettingImportResult = ehSettingsStore.importEntries(bundle.settings);
          saves.push(ehSettingsStore.save(context));
          this.settingEntries = ehSettingsStore.getEntries();
          this.themeName = currentThemeName();
          if (settingResult.languageChanged) {
            notifyLanguageChanged();
          }
          if (settingResult.themeChanged) {
            notifyThemeChanged();
            applyAppChromeImmersiveMode();
          }
          if (settingResult.titleChanged) {
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
        const importedReadingProgress = Array.isArray(bundle.readingProgress) ? bundle.readingProgress : [];

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

        if (importedHistory.length > 0 || importedReadingProgress.length > 0) {
          saves.push(ehHistoryStore.ensureLoaded(context).then(async () => {
            ehHistoryStore.importHistoryBackupItems(importedHistory, importedHistoryLimit);
            ehHistoryStore.importReadingProgressBackupItems(importedReadingProgress);
            if (importedHistory.length === 0) {
              await ehHistoryStore.save(context);
              return;
            }
            this.showBlockingBusy('Rebuilding imported history metadata...');
            const result: DownloadMetadataRestoreResult = await rebuildImportedHistoryMetadata(context,
              importedHistory, this.currentGallerySite());
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

        if (Array.isArray(bundle.searchHistory)) {
          const searchHistory = bundle.searchHistory;
          saves.push(ehSearchHistoryStore.load(context).then(() => {
            ehSearchHistoryStore.importKeywords(searchHistory);
            return ehSearchHistoryStore.save(context);
          }));
        }

        if (bundle.browsePositions !== undefined && bundle.browsePositions !== null &&
          typeof bundle.browsePositions === 'object') {
          const browsePositions = bundle.browsePositions as BrowsePositionsBackupInfo;
          saves.push(ehBrowsePositionStore.ensureLoaded(context).then(() => {
            ehBrowsePositionStore.importBackupInfo(browsePositions);
            return ehBrowsePositionStore.save(context);
          }));
        }

        if (Array.isArray(bundle.commentBlacklist)) {
          const commentBlacklist = bundle.commentBlacklist;
          saves.push(ehCommentBlacklistStore.ensureLoaded(context).then(() => {
            ehCommentBlacklistStore.importBackupItems(commentBlacklist);
            return ehCommentBlacklistStore.save(context);
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

  private exportAiTranslationRecords(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showFloatingStatus('AI translation record export needs an ability context');
      return;
    }
    const content = aiTranslationConversationLog.read(context);
    if (content.trim().length === 0) {
      this.showFloatingStatus('No AI translation records yet');
      return;
    }
    const fileName = 'ehviewer_ai_translation_' + diagnosticTimestamp(new Date()) + '.txt';
    this.writeTextToDownloads(context, fileName, content).then((path: string) => {
      this.statusText = uiText('AI translation records exported') + ': ' + path;
      this.showToast('AI translation records exported');
    }).catch((error: Error) => {
      this.showFloatingStatus(uiText('AI translation record export failed') + ': ' + error.message);
    });
  }

  private exportReaderOcrDebugRecords(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showFloatingStatus('Comic OCR debug export needs an ability context');
      return;
    }
    const content = readerOcrDebugLog.read(context);
    if (content.trim().length === 0) {
      this.showFloatingStatus('No comic OCR debug records yet');
      return;
    }
    const fileName = 'ehviewer_reader_ocr_debug_' + diagnosticTimestamp(new Date()) + '.txt';
    this.writeTextToDownloads(context, fileName, content).then((path: string) => {
      this.statusText = uiText('Comic OCR debug data exported') + ': ' + path;
      this.showToast('Comic OCR debug data exported');
    }).catch((error: Error) => {
      this.showFloatingStatus(uiText('Comic OCR debug export failed') + ': ' + error.message);
    });
  }

  private updateTagTranslationDatabase(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showFloatingStatus('Tag translation database update needs an ability context');
      return;
    }
    this.showBlockingBusy('Checking tag translation database...');
    ehTagTranslationStore.update(context, (phase: EhTagTranslationUpdatePhase) => {
      this.blockingBusyMessage = phase === 'downloading' ? 'Downloading tag translation database...' :
        'Checking tag translation database...';
    }).then((result: EhTagTranslationUpdateResult) => {
      this.hideBlockingBusy();
      if (result.updated) {
        notifyLanguageChanged();
        this.settingsRenderRevision++;
        this.showFloatingStatus('Tag translation database updated: ' + result.count.toString() + ' tags');
      } else {
        this.showFloatingStatus('Tag translation database is up to date');
      }
    }).catch((error: Error) => {
      this.hideBlockingBusy();
      this.showFloatingStatus('Tag translation database update failed: ' + error.message);
    });
  }

  private openProxySettings(): void {
    this.optionPickerOpen = false;
    this.proxySettingsOpen = true;
    this.activeSplitPane = SPLIT_PANE_FOCUS_RIGHT;
    this.statusText = '';
  }

  private closeProxySettings(): void {
    this.proxySettingsOpen = false;
    this.restoreBackHandler();
  }

  private saveProxySettings(type: string, host: string, port: string, username: string, password: string,
    exclusions: string, socksDns: string): void {
    const normalizedType = normalizeProxyOption(type);
    if (normalizedType === 'SOCKS' && !socks5ProxySupported()) {
      this.showFloatingStatus('SOCKS5 requires HarmonyOS API 26 or later');
      return;
    }
    const normalizedHost = host.trim();
    const normalizedPort = port.trim();
    if (normalizedType === 'HTTP' || normalizedType === 'SOCKS') {
      if (normalizedHost.length === 0 || !isValidProxyHostText(normalizedHost)) {
        this.showFloatingStatus(normalizedHost.length === 0 ? 'Proxy host is required' :
          'Invalid proxy host: ' + normalizedHost);
        return;
      }
      if (!isValidProxyPortText(normalizedPort)) {
        this.showFloatingStatus('Proxy port is invalid');
        return;
      }
    }
    ehSettingsStore.setValue('proxy', normalizedType);
    ehSettingsStore.setValue('proxy_host', normalizedHost);
    ehSettingsStore.setValue('proxy_port', normalizedPort);
    ehSettingsStore.setValue('proxy_username', username.trim());
    ehSettingsStore.setValue('proxy_password', password);
    ehSettingsStore.setValue('proxy_exclusion_list', normalizeProxyExclusionListText(exclusions));
    ehSettingsStore.setValue('proxy_socks_dns', socksDns === 'System' ? 'System' : 'Proxy');
    this.settingEntries = ehSettingsStore.getEntries();
    this.settingsRenderRevision++;
    this.closeProxySettings();
    this.refreshNetworkRuntime();
    const context = getAbilityContext();
    if (context !== undefined) {
      ehSettingsStore.save(context).catch((error: Error) => {
        this.showFloatingStatus('Save failed: ' + error.message);
      });
    }
    this.showFloatingStatus('Proxy settings saved');
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
          color: themeAccentTextColor()
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
    lines.push('Domain fronting: ' + ehSettingsStore.getValue('domain_fronting', 'Off'));
    lines.push('DNS over HTTPS: ' + currentDnsOverHttpsStatusText());
    lines.push('Direct connection check: ' + ehSettingsStore.getValue('auto_direct_connection', 'Off'));
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
      ensureEhHostRules().then(() => {
        startEhFrontingBenchmark(context);
      }).catch(() => {});
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
    const revision = AppStorage.get<number>(FILTER_RULE_REVISION_KEY) ?? 0;
    AppStorage.setOrCreate<number>(FILTER_RULE_REVISION_KEY, revision + 1);
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
        initialScrollOffset: settingsHomeScrollOffset,
        onScrollPositionChange: (offset: number) => {
          this.updateHomeScrollOffset(offset);
        },
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

      if (this.settingsDetailLayerPanel() !== SettingsPanel.Main) {
        SplitPaneDivider({
          x: this.useSplitLayout() ? this.splitListPaneWidth() : 0,
          dividerVisible: this.useSplitLayout(),
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
          initialScrollOffset: settingsDetailScrollOffsets.get(this.settingsDetailLayerPanel()) ?? 0,
          onScrollPositionChange: (offset: number) => {
            this.updateDetailScrollOffset(this.settingsDetailLayerPanel(), offset);
          },
          onBack: () => {
            this.closePanel();
          },
          onOpenSession: () => {
            this.sessionInitialMode = SessionMode.Password;
            this.openPanel(SettingsPanel.Session);
          },
          onSignOut: () => {
            this.signOutConfirmationVisible = true;
          },
          onCycleSetting: (row: SettingsRowItem) => {
            this.cycleSetting(row);
          },
          onSetSetting: (key: string, value: string) => {
            this.saveSettingValue(key, value);
          },
          onTextDraftChange: (key: string, value: string) => {
            this.updateSettingDraft(key, value);
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
      if (this.panel === SettingsPanel.CommentBlacklist) {
        CommentBlacklistPanel({
          onBack: () => {
            this.closePanel();
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
      } else if (this.panel === SettingsPanel.Filter) {
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
      } else if (this.panel === SettingsPanel.WifiTransfer) {
        WifiMigrationPanel({
          onBack: () => {
            this.closePanel();
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
      } else if (this.panel === SettingsPanel.RemoteStorage) {
        RemoteStoragePanel({
          onBack: () => {
            this.closePanel();
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
      } else if (this.panel === SettingsPanel.TranslationPrompt) {
        TranslationPromptPanel({
          selectedId: settingEntryValue(this.settingEntries, 'translation_prompt_selected', 'preset_faithful'),
          customProfiles: settingEntryValue(this.settingEntries, 'translation_prompt_custom_profiles', '[]'),
          onBack: () => {
            this.closePanel();
          },
          onSave: (selectedId: string, customProfiles: string, status: string) => {
            this.saveTranslationPrompt(selectedId, customProfiles, status);
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
      } else if (this.panel === SettingsPanel.ReaderPresets) {
        ReaderPresetPanel({
          customProfiles: settingEntryValue(this.settingEntries, READER_CUSTOM_PRESETS_SETTING_KEY, '[]'),
          onBack: () => {
            this.closePanel();
          },
          onApply: (profileId: string) => {
            this.applyReaderPreset(profileId);
          },
          onSave: (customProfiles: string, status: string) => {
            this.saveReaderPresets(customProfiles, status);
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
      } else if (this.panel === SettingsPanel.Session) {
        SessionScene({
          initialMode: this.sessionInitialMode,
          onBack: () => {
            this.closePanel();
          },
          onSignedIn: () => {
            this.signedIn = ehCookieStore.hasCookies();
            this.statusText = this.signedIn ? 'Signed in' : 'Guest mode';
            this.closePanel();
            this.onSignedIn();
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
      }

      // Option picker floats on top of everything.
      if (this.proxySettingsOpen) {
        ProxySettingsOverlay({
          initialType: normalizeProxyOption(ehSettingsStore.getValue('proxy', 'System')),
          initialHost: ehSettingsStore.getValue('proxy_host', ''),
          initialPort: ehSettingsStore.getValue('proxy_port', ''),
          initialUsername: ehSettingsStore.getValue('proxy_username', ''),
          initialPassword: ehSettingsStore.getValue('proxy_password', ''),
          initialExclusions: ehSettingsStore.getValue('proxy_exclusion_list', ''),
          initialSocksDns: ehSettingsStore.getValue('proxy_socks_dns', 'Proxy'),
          socksSupported: socks5ProxySupported(),
          onCancel: () => {
            this.closeProxySettings();
          },
          onSave: (type: string, host: string, port: string, username: string, password: string,
            exclusions: string, socksDns: string) => {
            this.saveProxySettings(type, host, port, username, password, exclusions, socksDns);
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .zIndex(26)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
      }

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
          .zIndex(SPLIT_PANE_MODAL_Z_INDEX)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }

      if (this.signOutConfirmationVisible) {
        ConfirmActionOverlay({
          title: 'Sign out',
          message: 'The saved login session will be removed.',
          confirmLabel: 'Sign out',
          onCancel: () => {
            this.signOutConfirmationVisible = false;
          },
          onConfirm: () => {
            this.signOut();
          }
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .zIndex(28)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
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
          .zIndex(SPLIT_PANE_MODAL_Z_INDEX)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }

      if (this.blockingBusyVisible) {
        BlockingBusyOverlay({
          message: this.blockingBusyMessage,
          progressText: this.blockingBusyProgressText,
          progressCurrent: this.blockingBusyProgressCurrent,
          progressTotal: this.blockingBusyProgressTotal
        })
          .width(this.settingsLayerWidth())
          .height('100%')
          .position({ x: this.settingsLayerTranslateX(), y: 0 })
          .zIndex(SPLIT_PANE_MODAL_Z_INDEX)
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

export {
  SettingsHomePanel,
  SettingsAccountWebPanel,
  SettingsSubToolbar,
  SettingsHeaderRow,
  SettingsTextBlock,
  SettingsDetailPanel,
  SettingsOptionPanel,
  SettingsActionRow,
  SettingsStaticRow,
} from './SettingsPanels';
