import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { GalleryRoute, GallerySite } from '../model/GalleryModels';
import { ehCookieStore } from '../services/EhCookieStore';
import { ehDownloadStore } from '../services/EhDownloadStore';
import { ehSearchHistoryStore } from '../services/EhSearchHistoryStore';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { ehSpiderInfoStore } from '../services/EhSpiderInfoStore';
import { ehUpdateChecker, ReleaseInfo, UpdateCheckResult } from '../services/EhUpdateChecker';
import { EhDrawer } from '../components/NavigationComponents';
import { UpdatePromptOverlay } from '../components/UpdatePromptOverlay';
import { applyAppChromeImmersiveMode, isEmbeddedReaderActive } from '../services/EhWindowImmersive';
import { FavoriteGalleryScene, HomeGalleryScene, HotGalleryScene, SubscriptionGalleryScene } from '../components/GalleryScenes';
import { HistoryScene, TopListScene } from '../components/HistoryTopScenes';
import { DownloadScene, MigrationScene } from '../components/DownloadMigrationScenes';
import { SessionScene, SettingsScene } from '../components/SessionSettingsScenes';
import {
  LANGUAGE_REVISION_KEY,
  STATUS_BAR_HEIGHT_KEY,
  getAbilityContext,
  launchRouteFromSetting,
  runActiveBackHandler,
  uiText
} from '../shared/EhShared';
import {
  themeOnPrimaryText,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeScrimColor,
  themeSecondaryText,
  themeShadowColor,
  themeSurface
} from '../shared/EhTheme';

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
  @State updateDialogVisible: boolean = false;
  @State updateCurrentVersion: string = '';
  @State updateRelease: ReleaseInfo | null = null;
  @State clipboardPasteVisible: boolean = false;
  @State clipboardPromptVisible: boolean = false;
  @State clipboardPromptUrl: string = '';
  @State clipboardPromptGid: number = 0;
  @State clipboardPromptToken: string = '';
  @State clipboardPromptSite: GallerySite = GallerySite.E;
  @State homeInitialDetailGid: number = 0;
  @State homeInitialDetailToken: string = '';
  @State homeInitialDetailSite: GallerySite = GallerySite.E;
  @State homeInitialDetailNonce: number = 0;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeight: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

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
    if (this.routeStack.length > 0) {
      this.popRoute();
      return true;
    }
    if (this.activeRoute !== GalleryRoute.Home) {
      this.setRootRoute(GalleryRoute.Home);
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
    ehSearchHistoryStore.load(context).catch(() => {});
    ehSettingsStore.load(context).then(() => {
      this.settingsReady = true;
      this.loadSessionRoute(context);
      this.checkForUpdatesOnStartup();
      this.checkClipboardGalleryUrl(context);
    }).catch(() => {
      this.settingsReady = true;
      this.loadSessionRoute(context);
      this.checkForUpdatesOnStartup();
      this.checkClipboardGalleryUrl(context);
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
    ehCookieStore.load(ctx).then(() => {
      this.setRootRoute(this.routeAfterSignIn());
    }).catch(() => {
      this.setRootRoute(this.routeAfterSignIn());
    });
  }

  private checkClipboardGalleryUrl(_context: common.UIAbilityContext): void {
    if (ehSettingsStore.getValue('clipboard_gallery_url_scan', 'Off') !== 'On') {
      return;
    }
    this.clipboardPasteVisible = true;
  }

  private pasteClipboardGalleryUrl(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.showToast('Clipboard scan failed');
      return;
    }
    pasteboard.getSystemPasteboard().getData().then((data: pasteboard.PasteData) => {
      this.handleClipboardText(context, data.getPrimaryText());
    }).catch(() => {
      this.showToast('Clipboard scan failed');
    });
  }

  private handleClipboardText(context: common.UIAbilityContext, text: string): void {
    if (text === undefined || text.length === 0) {
      this.rememberClipboardTextHash(context, 0);
      this.clipboardPasteVisible = false;
      this.showToast('No gallery URL in clipboard');
      return;
    }
    const hash = textHashCode(text);
    if (hash === Number.parseInt(ehSettingsStore.getValue('clipboard_text_hash', '0'))) {
      this.clipboardPasteVisible = false;
      this.showToast('Clipboard content already checked');
      return;
    }
    this.rememberClipboardTextHash(context, hash);
    const parsed = parseClipboardGalleryUrl(text);
    if (parsed === null) {
      this.clipboardPasteVisible = false;
      this.showToast('No gallery URL in clipboard');
      return;
    }
    this.clipboardPromptUrl = parsed.url;
    this.clipboardPromptGid = parsed.gid;
    this.clipboardPromptToken = parsed.token;
    this.clipboardPromptSite = parsed.site;
    this.clipboardPasteVisible = false;
    this.clipboardPromptVisible = true;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: uiText(message) });
    } catch (error) {
    }
  }

  private rememberClipboardTextHash(context: common.UIAbilityContext, hash: number): void {
    ehSettingsStore.setValue('clipboard_text_hash', hash.toString());
    ehSettingsStore.save(context).catch(() => {});
  }

  private openClipboardGallery(): void {
    if (this.clipboardPromptGid <= 0 || this.clipboardPromptToken.length === 0) {
      this.clipboardPromptVisible = false;
      return;
    }
    this.homeInitialDetailGid = this.clipboardPromptGid;
    this.homeInitialDetailToken = this.clipboardPromptToken;
    this.homeInitialDetailSite = this.clipboardPromptSite;
    this.homeInitialDetailNonce++;
    this.clipboardPromptVisible = false;
    this.setRootRoute(GalleryRoute.Home);
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
          Stack({ alignContent: Alignment.TopStart }) {
            // Persistent nav bar background — behind the transitioning scenes so the
            // primary-color strip stays solid while scene content fades in/out.
            Column()
              .width('100%')
              .height(this.statusBarVp() + 56)
              .backgroundColor(themePrimaryColor())

            this.RouteContent()
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
          .zIndex(30)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }

      if (this.clipboardPasteVisible && !this.clipboardPromptVisible) {
        Column() {
          Text(uiText('Paste clipboard to scan gallery URL'))
            .fontSize(15)
            .fontColor(themePrimaryText())
            .fontWeight(FontWeight.Medium)
            .width('100%')
          Text(uiText('Tap the system Paste button to grant one-time clipboard access'))
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .width('100%')
            .margin({ top: 4, bottom: 12 })
          Row() {
            Button(uiText('Ignore'), { type: ButtonType.Normal, stateEffect: true })
              .height(40)
              .fontSize(13)
              .fontColor(themeSecondaryText())
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.clipboardPasteVisible = false;
              })
            PasteButton()
              .height(40)
              .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
                if (result === PasteButtonOnClickResult.SUCCESS) {
                  this.pasteClipboardGalleryUrl();
                }
              })
          }
          .justifyContent(FlexAlign.End)
          .width('100%')
        }
        .width('92%')
        .padding(14)
        .backgroundColor(themeSurface())
        .borderRadius(8)
        .align(Alignment.Bottom)
        .margin({ bottom: 32 })
        .zIndex(31)
        .shadow({ radius: 18, color: themeShadowColor(), offsetX: 0, offsetY: 6 })
      }

      if (this.clipboardPromptVisible) {
        Column() {
          Text(uiText('There is a gallery url in the clipboard'))
            .fontSize(15)
            .fontColor(themePrimaryText())
            .fontWeight(FontWeight.Medium)
            .width('100%')
          Text(this.clipboardPromptUrl)
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 4, bottom: 12 })
          Row() {
            Button(uiText('Ignore'), { type: ButtonType.Normal, stateEffect: true })
              .height(36)
              .fontSize(13)
              .fontColor(themeSecondaryText())
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.clipboardPromptVisible = false;
              })
            Button(uiText('View'), { type: ButtonType.Normal, stateEffect: true })
              .height(36)
              .fontSize(13)
              .fontColor(themeOnPrimaryText())
              .backgroundColor(themePrimaryColor())
              .onClick(() => {
                this.openClipboardGallery();
              })
          }
          .justifyContent(FlexAlign.End)
          .width('100%')
        }
        .width('92%')
        .padding(14)
        .backgroundColor(themeSurface())
        .borderRadius(8)
        .align(Alignment.Bottom)
        .margin({ bottom: 32 })
        .zIndex(31)
        .shadow({ radius: 18, color: themeShadowColor(), offsetX: 0, offsetY: 6 })
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
        onMenu: () => { this.openDrawer(); },
        initialDetailGid: this.homeInitialDetailGid,
        initialDetailToken: this.homeInitialDetailToken,
        initialDetailSite: this.homeInitialDetailSite,
        initialDetailNonce: this.homeInitialDetailNonce
      })
        .id('home-gallery-' + this.homeInitialDetailNonce.toString())
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

interface ClipboardGalleryUrl {
  gid: number;
  token: string;
  site: GallerySite;
  url: string;
}

function parseClipboardGalleryUrl(text: string): ClipboardGalleryUrl | null {
  const match = /(https?:\/\/)?(e-hentai\.org|exhentai\.org)\/g\/(\d+)\/([A-Za-z0-9]+)\/?/i.exec(text);
  if (match === null) {
    return null;
  }
  const gid = Number.parseInt(match[3]);
  if (Number.isNaN(gid) || gid <= 0) {
    return null;
  }
  const host = match[2].toLowerCase();
  const token = match[4];
  return {
    gid: gid,
    token: token,
    site: host === 'exhentai.org' ? GallerySite.Ex : GallerySite.E,
    url: 'https://' + host + '/g/' + gid.toString() + '/' + token + '/'
  };
}

function textHashCode(text: string): number {
  let hash = 0;
  for (let i = 0; i < text.length; i++) {
    hash = ((hash << 5) - hash + text.charCodeAt(i)) | 0;
  }
  return hash;
}
