import { common } from '@kit.AbilityKit';
import { GalleryRoute } from '../model/GalleryModels';
import { ehCookieStore } from '../services/EhCookieStore';
import {
  DAILY_CHECK_IN_FOREGROUND_REVISION_KEY,
  ehDailyCheckInService,
  EhDailyCheckInResult
} from '../services/EhDailyCheckInService';
import { ehDownloadStore } from '../services/EhDownloadStore';
import { ehAppLog } from '../services/EhAppLog';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehSearchHistoryStore } from '../services/EhSearchHistoryStore';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { ehSpiderInfoStore } from '../services/EhSpiderInfoStore';
import { ehUpdateChecker, ReleaseInfo, UpdateCheckResult } from '../services/EhUpdateChecker';
import { TRANSLATION_ERROR_MESSAGE_KEY, TRANSLATION_ERROR_REVISION_KEY } from '../services/EhTranslationService';
import { EhDrawer } from '../components/NavigationComponents';
import { ConfirmActionOverlay } from '../components/ConfirmActionOverlay';
import { UpdatePromptOverlay } from '../components/UpdatePromptOverlay';
import { PopupScrim } from '../components/PopupScrim';
import { applyAppChromeImmersiveMode, isEmbeddedReaderActive } from '../services/EhWindowImmersive';
import { prepareSplitPaneRouteTransition, SPLIT_PANE_MODAL_Z_INDEX } from '../components/SplitPaneSupport';
import { FavoriteGalleryScene, HomeGalleryScene, HotGalleryScene, SubscriptionGalleryScene } from '../components/GalleryScenes';
import { HistoryScene, TopListScene } from '../components/HistoryTopScenes';
import { DownloadScene, MigrationScene } from '../components/DownloadMigrationScenes';
import { SessionScene, SettingsScene } from '../components/SessionSettingsScenes';
import {
  LANGUAGE_REVISION_KEY,
  IDENTITY_AUTH_LOCKED_KEY,
  STATUS_BAR_HEIGHT_KEY,
  THEME_REVISION_KEY,
  getAbilityContext,
  launchRouteFromSetting,
  runActiveBackHandler,
  uiStatusText,
  uiText
} from '../shared/EhShared';
import {
  themePageBackground,
  themePrimaryText,
  themeSecondaryText,
  themeShadowColor
} from '../shared/EhTheme';

// ----------------------------------------------------------------
// Root page: full-screen immersive shell with slide-in side drawer
// ----------------------------------------------------------------
interface RootNavigationCache {
  initialized: boolean;
  activeRoute: GalleryRoute;
  routeResetVersion: number;
}

let rootNavigationCache: RootNavigationCache = {
  initialized: false,
  activeRoute: GalleryRoute.Home,
  routeResetVersion: 0
};

const DAILY_CHECK_IN_RETRY_INTERVAL_MS: number = 5 * 60 * 1000;

@Entry
@Component
struct Index {
  @State activeRoute: GalleryRoute = GalleryRoute.Home;
  @State drawerVisible: boolean = false;
  @State drawerOffsetX: number = -264;
  @State drawerOverlayOpacity: number = 0;
  @State settingsReady: boolean = false;
  @State routeResetVersion: number = 0;
  @State updateDialogVisible: boolean = false;
  @State updateCurrentVersion: string = '';
  @State updateRelease: ReleaseInfo | null = null;
  @State dailyCheckInDialogVisible: boolean = false;
  @State dailyCheckInMessage: string = '';
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeight: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @StorageProp(THEME_REVISION_KEY) themeRevision: number = 0;
  @StorageProp(IDENTITY_AUTH_LOCKED_KEY) identityAuthLocked: boolean = false;
  @StorageProp(TRANSLATION_ERROR_REVISION_KEY) @Watch('onTranslationErrorRevision') translationErrorRevision: number = 0;
  @StorageProp(DAILY_CHECK_IN_FOREGROUND_REVISION_KEY) @Watch('onDailyCheckInForeground')
  dailyCheckInForegroundRevision: number = 0;
  private dailyCheckInPending: boolean = false;
  private dailyCheckInLastAttemptAt: number = 0;

  onTranslationErrorRevision(): void {
    const message = AppStorage.get<string>(TRANSLATION_ERROR_MESSAGE_KEY);
    if (message === undefined || message.length === 0) {
      return;
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: uiStatusText(message) });
    } catch (_error) {
    }
  }

  onDailyCheckInForeground(): void {
    if (!this.settingsReady) {
      return;
    }
    this.requestDailyCheckIn('foreground');
  }

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeight);
  }

  private openExternalUrl(url: string): void {
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    context.startAbility({
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url,
      parameters: {
        'ohos.ability.params.showDefaultPicker': true
      }
    }).catch(() => {});
  }

  private canOpenDrawerBySwipe(): boolean {
    return !this.drawerVisible && !isEmbeddedReaderActive();
  }

  private handleOpenDrawerPan(event: GestureEvent | undefined): void {
    if (!this.canOpenDrawerBySwipe() || event === undefined) {
      return;
    }
    const distanceX = event.offsetX;
    const distanceY = Math.abs(event.offsetY);
    const velocityX = event.velocityX;
    if (distanceX > 72 && distanceY < Math.max(48, Math.abs(distanceX) * 0.7) && velocityX >= -80) {
      this.openDrawer();
    }
  }

  onBackPress(): boolean {
    if (this.drawerVisible) {
      this.closeDrawer();
      return true;
    }
    if (runActiveBackHandler()) {
      return true;
    }
    const launchRoute = this.routeAfterSignIn();
    if (this.activeRoute !== launchRoute) {
      this.setRootRoute(launchRoute);
      return true;
    }
    return false;
  }

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    this.restoreRootRoute();
    const context = getAbilityContext();
    if (context === undefined) {
      this.setRootRoute(GalleryRoute.Home);
      return;
    }
    ehSpiderInfoStore.load(context).catch(() => {});
    ehDownloadStore.load(context).catch(() => {});
    ehHistoryStore.load(context).catch(() => {});
    ehSearchHistoryStore.load(context).catch(() => {});
    ehSettingsStore.ensureLoaded(context).then(() => {
      this.settingsReady = true;
      this.loadSessionRoute(context);
      this.checkForUpdatesOnStartup();
    }).catch(() => {
      this.settingsReady = true;
      this.loadSessionRoute(context);
      this.checkForUpdatesOnStartup();
    });
  }

  private checkForUpdatesOnStartup(): void {
    if (ehSettingsStore.getValue('close_auto_updates', 'Off') === 'On') {
      return;
    }
    ehUpdateChecker.checkLatestRelease().then((result: UpdateCheckResult) => {
      if (result.hasUpdate && result.latest !== null) {
        this.updateCurrentVersion = result.current.versionName;
        this.updateRelease = result.latest;
        this.updateDialogVisible = true;
      }
    }).catch(() => {});
  }

  private loadSessionRoute(ctx: common.UIAbilityContext): void {
    ehCookieStore.ensureLoaded(ctx).then(() => {
      this.applyInitialRoute();
      this.requestDailyCheckIn('startup');
    }).catch(() => {
      this.applyInitialRoute();
      this.requestDailyCheckIn('startup');
    });
  }

  private requestDailyCheckIn(reason: string, force: boolean = false): void {
    if (this.dailyCheckInPending) {
      return;
    }
    if (!ehCookieStore.hasCookies()) {
      this.logDailyCheckInInfo('Skipped: no login session');
      return;
    }
    if (ehSettingsStore.getValue('show_eh_events', 'On') !== 'On') {
      this.logDailyCheckInInfo('Skipped: automatic check-in is disabled');
      return;
    }
    const now = Date.now();
    if (!force && now - this.dailyCheckInLastAttemptAt < DAILY_CHECK_IN_RETRY_INTERVAL_MS) {
      return;
    }
    this.dailyCheckInPending = true;
    this.dailyCheckInLastAttemptAt = now;
    const startedAt = Date.now();
    this.logDailyCheckInInfo('Request started, reason=' + reason);
    ehDailyCheckInService.check().then((result: EhDailyCheckInResult) => {
      const elapsedMs = Date.now() - startedAt;
      if (!result.ok) {
        this.logDailyCheckInWarn('Request failed, status=' + result.statusCode.toString() +
          ', elapsedMs=' + elapsedMs.toString() + ', kind=' + result.responseKind +
          ', message=' + result.message);
        return;
      }
      if (result.event !== null) {
        this.logDailyCheckInInfo('Request succeeded, status=' + result.statusCode.toString() +
          ', elapsedMs=' + elapsedMs.toString() + ', dailyEvent=present, bodyLength=' +
          result.bodyLength.toString() + ', paragraphs=' + result.eventParagraphCount.toString());
        this.dailyCheckInMessage = result.event.message;
        this.dailyCheckInDialogVisible = true;
      } else {
        this.logDailyCheckInInfo('Request succeeded, status=' + result.statusCode.toString() +
          ', elapsedMs=' + elapsedMs.toString() + ', dailyEvent=absent, kind=' + result.responseKind +
          ', bodyLength=' + result.bodyLength.toString() + ', paragraphs=' +
          result.eventParagraphCount.toString());
      }
    }).catch((error: Error) => {
      this.logDailyCheckInWarn('Request rejected, elapsedMs=' + (Date.now() - startedAt).toString() +
        ', message=' + error.message);
    }).finally(() => {
      this.dailyCheckInPending = false;
    });
  }

  private logDailyCheckInInfo(message: string): void {
    console.info('DailyCheckIn: ' + message);
    ehAppLog.info(getAbilityContext(), 'DailyCheckIn', message);
  }

  private logDailyCheckInWarn(message: string): void {
    console.warn('DailyCheckIn: ' + message);
    ehAppLog.warn(getAbilityContext(), 'DailyCheckIn', message);
  }

  private handleSignedIn(): void {
    this.setRootRoute(this.routeAfterSignIn());
    this.requestDailyCheckIn('signed-in', true);
  }

  private restoreRootRoute(): void {
    if (!rootNavigationCache.initialized) {
      return;
    }
    this.activeRoute = rootNavigationCache.activeRoute;
    this.routeResetVersion = rootNavigationCache.routeResetVersion;
  }

  private applyInitialRoute(): void {
    if (rootNavigationCache.initialized) {
      this.restoreRootRoute();
      return;
    }
    this.setRootRoute(this.routeAfterSignIn());
  }

  private routeAfterSignIn(): GalleryRoute {
    return launchRouteFromSetting(ehSettingsStore.getValue('launch_page', 'Homepage'));
  }

  selectRoute(route: GalleryRoute): void {
    applyAppChromeImmersiveMode();
    this.setRootRoute(route);
    this.closeDrawer();
  }

  private setRootRoute(route: GalleryRoute): void {
    prepareSplitPaneRouteTransition();
    this.activeRoute = route;
    this.routeResetVersion++;
    rootNavigationCache = {
      initialized: true,
      activeRoute: this.activeRoute,
      routeResetVersion: this.routeResetVersion
    };
  }

  openDrawer(): void {
    this.drawerVisible = true;
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
      this.drawerOffsetX = 0;
      this.drawerOverlayOpacity = 0.45;
    });
  }

  closeDrawer(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
      this.drawerOffsetX = -264;
      this.drawerOverlayOpacity = 0;
    });
    setTimeout(() => {
      if (this.drawerOffsetX < -200) {
        this.drawerVisible = false;
      }
    }, 220);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ---- Main content ----
      Column() {
        if (this.settingsReady) {
          Stack({ alignContent: Alignment.TopStart }) {
            // Keep the transition underlay neutral. Material app bars are rendered by
            // each scene; a primary-color underlay can flash through between frames.
            Column()
              .width('100%')
              .height(this.statusBarVp() + 56)
              .backgroundColor(themePageBackground())

            if (this.themeRevision % 2 === 0) {
              this.RouteContent()
            } else {
              this.RouteContent()
            }
          }
          .width('100%')
          .height('100%')
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(themePageBackground())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // ---- Scrim + drawer ----
      if (this.drawerVisible) {
        PopupScrim({
          showCutout: true,
          positionedCutout: true,
          cutoutX: this.drawerOffsetX,
          cutoutY: 0,
          cutoutWidth: 264,
          cutoutHeight: '100%',
          cutoutRadius: 0,
          scrimOpacity: this.drawerOverlayOpacity,
          onDismiss: () => { this.closeDrawer(); }
        })
          .zIndex(8)

        EhDrawer({
          activeRoute: this.activeRoute,
          statusBarHeight: this.statusBarVp(),
          onSelect: (route: GalleryRoute) => { this.selectRoute(route); }
        })
          .translate({ x: this.drawerOffsetX })
          .zIndex(9)
          .shadow({ radius: 32, color: themeShadowColor(), offsetX: 8, offsetY: 0 })
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
              this.openExternalUrl(release.hapDownloadUrl);
            }
          }
        })
          .zIndex(SPLIT_PANE_MODAL_Z_INDEX)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }

      if (this.dailyCheckInDialogVisible) {
        ConfirmActionOverlay({
          title: 'Daily check-in',
          message: this.dailyCheckInMessage,
          confirmLabel: 'OK',
          danger: false,
          showCancel: false,
          onCancel: () => { this.dailyCheckInDialogVisible = false; },
          onConfirm: () => { this.dailyCheckInDialogVisible = false; }
        })
          .zIndex(SPLIT_PANE_MODAL_Z_INDEX + 1)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }

      if (this.identityAuthLocked) {
        Column() {
          Text(uiText('Identity authentication required'))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(themePrimaryText())
          Text(uiText('Unlock to continue using EhViewer'))
            .fontSize(14)
            .fontColor(themeSecondaryText())
            .margin({ top: 10 })
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        .height('100%')
        .backgroundColor(themePageBackground())
        .zIndex(100)
      }
    }
    .width('100%')
    .height('100%')
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Right, distance: 28 })
        .onActionEnd((event: GestureEvent | undefined) => {
          this.handleOpenDrawerPan(event);
        })
    )
  }

  @Builder
  private RouteContent() {
    if (this.activeRoute === GalleryRoute.Home) {
      HomeGalleryScene({
        resetVersion: this.routeResetVersion,
        onMenu: () => { this.openDrawer(); }
      })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else if (this.activeRoute === GalleryRoute.Subscription) {
      SubscriptionGalleryScene({ resetVersion: this.routeResetVersion, onMenu: () => { this.openDrawer(); } })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else if (this.activeRoute === GalleryRoute.WhatsHot) {
      HotGalleryScene({ resetVersion: this.routeResetVersion, onMenu: () => { this.openDrawer(); } })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else if (this.activeRoute === GalleryRoute.TopLists) {
      TopListScene({ resetVersion: this.routeResetVersion, onMenu: () => { this.openDrawer(); } })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else if (this.activeRoute === GalleryRoute.Favorites) {
      FavoriteGalleryScene({ resetVersion: this.routeResetVersion, onMenu: () => { this.openDrawer(); } })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else if (this.activeRoute === GalleryRoute.History) {
      HistoryScene({ resetVersion: this.routeResetVersion, onMenu: () => { this.openDrawer(); } })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else if (this.activeRoute === GalleryRoute.Downloads) {
      DownloadScene({ resetVersion: this.routeResetVersion, onMenu: () => { this.openDrawer(); } })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else if (this.activeRoute === GalleryRoute.Session) {
      SessionScene({
        onSignedIn: () => { this.handleSignedIn(); }
      })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else if (this.activeRoute === GalleryRoute.Migration) {
      MigrationScene()
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else {
      SettingsScene({
        resetVersion: this.routeResetVersion,
        onMenu: () => { this.openDrawer(); },
        onSignedIn: () => { this.handleSignedIn(); }
      })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    }
  }
}
