import { common } from '@kit.AbilityKit';
import { GalleryRoute } from '../model/GalleryModels';
import { ehCookieStore } from '../services/EhCookieStore';
import { ehDownloadStore } from '../services/EhDownloadStore';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { ehSpiderInfoStore } from '../services/EhSpiderInfoStore';
import { EhDrawer } from '../components/NavigationComponents';
import { applyAppChromeImmersiveMode } from '../services/EhWindowImmersive';
import { FavoriteGalleryScene, HomeGalleryScene, HotGalleryScene, SubscriptionGalleryScene } from '../components/GalleryScenes';
import { HistoryScene, TopListScene } from '../components/HistoryTopScenes';
import { DownloadScene, MigrationScene } from '../components/DownloadMigrationScenes';
import { SessionScene, SettingsScene } from '../components/SessionSettingsScenes';
import {
  LANGUAGE_REVISION_KEY,
  STATUS_BAR_HEIGHT_KEY,
  getAbilityContext,
  launchRouteFromSetting,
  runActiveBackHandler
} from '../shared/EhShared';
import { themePageBackground, themeScrimColor, themeShadowColor } from '../shared/EhTheme';

// ----------------------------------------------------------------
// Root page: full-screen immersive shell with slide-in side drawer
// ----------------------------------------------------------------
@Entry
@Component
struct Index {
  @State activeRoute: GalleryRoute = GalleryRoute.Home;
  @State drawerVisible: boolean = false;
  @State drawerOffsetX: number = -264;
  @State drawerOverlayOpacity: number = 0;
  @State settingsReady: boolean = false;
  @State routeStack: GalleryRoute[] = [];
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeight: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeight);
  }

  onBackPress(): boolean {
    if (runActiveBackHandler()) {
      return true;
    }
    if (this.drawerVisible) {
      this.closeDrawer();
      return true;
    }
    if (this.routeStack.length > 0) {
      this.popRoute();
      return true;
    }
    if (this.activeRoute === GalleryRoute.Settings || this.activeRoute === GalleryRoute.Downloads) {
      this.setRootRoute(this.routeAfterSignIn());
      return true;
    }
    return false;
  }

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    const context = getAbilityContext();
    if (context === undefined) {
      this.setRootRoute(GalleryRoute.Home);
      return;
    }
    ehSpiderInfoStore.load(context).catch(() => {});
    ehDownloadStore.load(context).catch(() => {});
    ehSettingsStore.load(context).then(() => {
      this.settingsReady = true;
      this.loadSessionRoute(context);
    }).catch(() => {
      this.settingsReady = true;
      this.loadSessionRoute(context);
    });
  }

  private loadSessionRoute(ctx: common.UIAbilityContext): void {
    ehCookieStore.load(ctx).then(() => {
      this.setRootRoute(this.routeAfterSignIn());
    }).catch(() => {
      this.setRootRoute(this.routeAfterSignIn());
    });
  }

  private routeAfterSignIn(): GalleryRoute {
    return launchRouteFromSetting(ehSettingsStore.getValue('launch_page', 'Homepage'));
  }

  selectRoute(route: GalleryRoute): void {
    applyAppChromeImmersiveMode();
    if (this.activeRoute !== route) {
      const nextStack = this.routeStack.slice();
      nextStack.push(this.activeRoute);
      this.routeStack = nextStack;
      this.activeRoute = route;
    }
    this.closeDrawer();
  }

  private setRootRoute(route: GalleryRoute): void {
    this.routeStack = [];
    this.activeRoute = route;
  }

  private popRoute(): void {
    const nextStack = this.routeStack.slice();
    const previousRoute = nextStack.pop();
    this.routeStack = nextStack;
    if (previousRoute !== undefined) {
      applyAppChromeImmersiveMode();
      this.activeRoute = previousRoute;
    }
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
          this.RouteContent()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(themePageBackground())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // ---- Scrim + drawer ----
      if (this.drawerVisible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(themeScrimColor())
          .opacity(this.drawerOverlayOpacity)
          .onClick(() => { this.closeDrawer(); })
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
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private RouteContent() {
    if (this.activeRoute === GalleryRoute.Home) {
      HomeGalleryScene({ onMenu: () => { this.openDrawer(); } })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else if (this.activeRoute === GalleryRoute.Subscription) {
      SubscriptionGalleryScene({ onMenu: () => { this.openDrawer(); } })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else if (this.activeRoute === GalleryRoute.WhatsHot) {
      HotGalleryScene({ onMenu: () => { this.openDrawer(); } })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else if (this.activeRoute === GalleryRoute.TopLists) {
      TopListScene({ onMenu: () => { this.openDrawer(); } })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else if (this.activeRoute === GalleryRoute.Favorites) {
      FavoriteGalleryScene({ onMenu: () => { this.openDrawer(); } })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else if (this.activeRoute === GalleryRoute.History) {
      HistoryScene({ onMenu: () => { this.openDrawer(); } })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else if (this.activeRoute === GalleryRoute.Downloads) {
      DownloadScene({ onMenu: () => { this.openDrawer(); } })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else if (this.activeRoute === GalleryRoute.Session) {
      SessionScene({
        onSignedIn: () => { this.setRootRoute(this.routeAfterSignIn()); }
      })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else if (this.activeRoute === GalleryRoute.Migration) {
      MigrationScene()
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    } else {
      SettingsScene({
        onMenu: () => { this.openDrawer(); },
        onSignedIn: () => { this.setRootRoute(this.routeAfterSignIn()); }
      })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    }
  }
}
