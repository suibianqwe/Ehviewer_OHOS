import { GalleryRoute } from '../model/GalleryModels';
import { ehCookieStore } from '../services/EhCookieStore';
import { ehDownloadStore } from '../services/EhDownloadStore';
import { LANGUAGE_REVISION_KEY, STATUS_BAR_HEIGHT_KEY, downloadQueueSummary, getAbilityContext, uiText, uiStatusText, DrawerItem, DRAWER_ITEMS } from '../shared/EhShared';
import {
  themeDividerColor,
  themeFieldBackground,
  themeOnPrimaryActionBackground,
  themeOnPrimaryActionDisabledBackground,
  themeOnPrimaryActionStrongBackground,
  themeOnPrimaryDangerBackground,
  themeOnPrimarySecondaryText,
  themeOnPrimaryText,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSelectedBackground,
  themeSelectedBackgroundLight,
  themeSelectedIndicatorColor,
  themeSelectedText,
  themeSurface,
  themeSurfaceVariant,
  themeTransparentColor
} from '../shared/EhTheme';

// ===================================================================
// EhDrawer  -- slide-in navigation drawer (HarmonyOS style)
// ===================================================================
@Component
export struct EhDrawer {
  @Prop activeRoute: GalleryRoute = GalleryRoute.Home;
  @Prop statusBarHeight: number = 0;
  onSelect: (route: GalleryRoute) => void = () => {};

  @State signedIn: boolean = false;
  @State downloadSummary: string = '';
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  private downloadRefreshTimer: number = -1;

  aboutToAppear(): void {
    this.signedIn = ehCookieStore.hasCookies();
    this.refreshDownloadSummary();
    const ctx = getAbilityContext();
    if (ctx !== undefined) {
      ehDownloadStore.load(ctx).then(() => {
        this.refreshDownloadSummary();
      }).catch(() => {});
    }
    this.downloadRefreshTimer = setInterval(() => {
      this.refreshDownloadSummary();
    }, 1500);
  }

  aboutToDisappear(): void {
    if (this.downloadRefreshTimer >= 0) {
      clearInterval(this.downloadRefreshTimer);
      this.downloadRefreshTimer = -1;
    }
  }

  private refreshDownloadSummary(): void {
    this.downloadSummary = downloadQueueSummary(ehDownloadStore.getItems());
  }

  build() {
    Column() {
      // ---- Header ----
      Column() {
        // status bar spacer
        Column()
          .height(this.statusBarHeight)
          .width('100%')

        Row() {
          // Avatar
          Text(this.signedIn ? 'EH' : '?')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(themePrimaryColor())
            .textAlign(TextAlign.Center)
            .width(52)
            .height(52)
            .backgroundColor(themeSurface())
            .borderRadius(26)

          Column() {
            Text('EhViewer')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(themeOnPrimaryText())

            Text(this.signedIn ? uiText('Signed in') : uiText('Guest mode'))
              .fontSize(13)
              .fontColor(themeOnPrimarySecondaryText())
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 14 })
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 20 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .backgroundColor(themePrimaryColor())

      // ---- Nav items ----
      List() {
        ForEach(DRAWER_ITEMS, (item: DrawerItem) => {
          ListItem() {
            DrawerNavItem({
              item: item,
              selected: item.route === this.activeRoute,
              onTap: () => { this.onSelect(item.route); }
            })
          }
          .reuseId('drawer-nav-item')
        }, (item: DrawerItem) => item.route + ':' + this.activeRoute.toString())
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .cachedCount(4)
      .divider({ strokeWidth: 0.5, color: themeDividerColor(), startMargin: 56, endMargin: 0 })

      // ---- Footer: download summary ----
      if (this.downloadSummary.length > 0) {
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_down_circle'))
            .fontSize(16)
            .fontColor([themeSecondaryText()])
          Text(uiStatusText('Downloads: ' + this.downloadSummary))
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: 6 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .backgroundColor(themeSurfaceVariant())
      }
    }
    .width(264)
    .height('100%')
    .backgroundColor(themeSurface())
  }
}

// ===================================================================
// DrawerNavItem  -- a single row in the drawer list
// ===================================================================
@Component
struct DrawerNavItem {
  item: DrawerItem = { route: GalleryRoute.Home, title: '', icon: '', subtitle: '' };
  selected: boolean = false;
  onTap: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  // Map old letter icons to sys.symbol
  private symbolForRoute(route: GalleryRoute): Resource {
    switch (route) {
      case GalleryRoute.Home:         return $r('sys.symbol.house');
      case GalleryRoute.Subscription: return $r('sys.symbol.star');
      case GalleryRoute.WhatsHot:     return $r('sys.symbol.flame');
      case GalleryRoute.TopLists:     return $r('sys.symbol.list_number');
      case GalleryRoute.Favorites:    return $r('sys.symbol.heart');
      case GalleryRoute.History:      return $r('sys.symbol.clock');
      case GalleryRoute.Downloads:    return $r('sys.symbol.arrow_down_circle');
      case GalleryRoute.Settings:     return $r('sys.symbol.gearshape');
      default:                        return $r('sys.symbol.circle');
    }
  }

  build() {
    Row() {
      // Selection indicator
      Column()
        .width(3)
        .height(28)
        .borderRadius(2)
        .backgroundColor(this.selected ? themeSelectedIndicatorColor() : themeTransparentColor())
        .margin({ right: 10 })

      // Icon badge
      Column() {
        SymbolGlyph(this.symbolForRoute(this.item.route))
          .fontSize(20)
          .fontColor([this.selected ? themeSelectedText() : themeSecondaryText()])
      }
      .width(38)
      .height(38)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.selected ? themeSelectedBackgroundLight() : themeTransparentColor())
      .borderRadius(10)

      Column() {
        Text(uiText(this.item.title))
          .fontSize(15)
          .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.selected ? themeSelectedText() : themePrimaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(uiText(this.item.subtitle))
          .fontSize(11)
          .fontColor(themeSecondaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 1 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .height(60)
    .padding({ left: 8, right: 16 })
    .backgroundColor(this.selected ? themeSelectedBackground() : themeTransparentColor())
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.onTap(); })
  }
}

// ===================================================================
// EhNavBar  -- top app bar used by list pages
//   Supports: immersive (extends under status bar), scroll-hide,
//             search mode and action mode
// ===================================================================
@Component
export struct EhNavBar {
  @Prop statusBarHeight: number = 0;  // in vp
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop searchMode: boolean = false;
  @Prop keyword: string = '';
  @Prop searchPlaceholder: string = '';
  @Prop filterActive: boolean = false;
  @Prop showClear: boolean = false;
  @Prop canClear: boolean = false;
  @Prop showSearchButton: boolean = false;
  @Prop showRefreshButton: boolean = true;
  @Prop showBackButton: boolean = false;
  @Prop searchShowsAdvancedButton: boolean = false;
  // translate offset injected by parent for scroll-hide; 0 = visible, negative = hidden
  @Prop translateY: number = 0;
  onMenu: () => void = () => {};
  onBack: () => void = () => {};
  onSearch: () => void = () => {};
  onSearchFocus: () => void = () => {};
  onAdvanced: () => void = () => {};
  onKeywordChange: (value: string) => void = () => {};
  onRefresh: () => void = () => {};
  onClear: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  private barBodyHeight(): number {
    return 56;
  }

  private totalBarHeight(): number {
    return this.statusBarHeight + this.barBodyHeight();
  }

  private barVisible(): boolean {
    return this.translateY > -this.totalBarHeight();
  }

  build() {
    Column() {
      // Status bar spacer (colour-matched)
      Column()
        .height(this.statusBarHeight)
        .width('100%')
        .backgroundColor(themePrimaryColor())

      // Main bar row
      Row() {
        // Hamburger / back button
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph(this.showBackButton ? $r('sys.symbol.chevron_left') : $r('sys.symbol.open_sidebar'))
            .fontSize(22)
            .fontColor([themeOnPrimaryText()])
        }
        .width(40)
        .height(40)
        .backgroundColor(themeOnPrimaryActionBackground())
        .flexShrink(0)
        .onClick(() => {
          if (this.showBackButton) {
            this.onBack();
          } else {
            this.onMenu();
          }
        })

        if (this.searchMode) {
          // Search input
          Stack({ alignContent: Alignment.BottomStart }) {
            TextInput({
              text: this.keyword,
              placeholder: this.searchPlaceholder.length > 0 ? uiText(this.searchPlaceholder) :
                (this.title.length === 0 ? uiText('Search galleries') : uiText(this.title))
            })
              .height(38)
              .width('100%')
              .backgroundColor(themeFieldBackground())
              .borderRadius(19)
              .placeholderColor(themeSecondaryText())
              .fontColor(themePrimaryText())
              .caretColor(themePrimaryColor())
              .padding({ left: 16, right: 42 })
              .onFocus(() => { this.onSearchFocus(); })
              .onChange((v: string) => { this.onKeywordChange(v); })
              .onSubmit(() => { this.onSearch(); })

            if (this.filterActive) {
              Text(uiText('Filter'))
                .fontSize(9)
                .fontColor(themeOnPrimaryText())
                .backgroundColor(themeOnPrimaryActionStrongBackground())
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .borderRadius(3)
                .margin({ left: 10, bottom: 5 })
            }
          }
          .height(38)
          .layoutWeight(1)
          .margin({ left: 10 })

          // Search confirm
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph(this.searchShowsAdvancedButton ? $r('sys.symbol.plus') : $r('sys.symbol.magnifyingglass'))
              .fontSize(this.searchShowsAdvancedButton ? 22 : 20)
              .fontColor([themeOnPrimaryText()])
          }
          .width(40)
          .height(40)
          .backgroundColor(this.searchShowsAdvancedButton && this.filterActive ? themeOnPrimaryActionStrongBackground() :
            themeOnPrimaryActionBackground())
          .flexShrink(0)
          .margin({ left: 8 })
          .onClick(() => {
            if (this.searchShowsAdvancedButton) {
              this.onAdvanced();
            } else {
              this.onSearch();
            }
          })

        } else {
          // Title text
          Column() {
            Text(uiText(this.title))
              .fontSize(19)
              .fontWeight(FontWeight.Medium)
              .fontColor(themeOnPrimaryText())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if (this.subtitle.length > 0) {
              Text(uiText(this.subtitle))
                .fontSize(12)
                .fontColor(themeOnPrimarySecondaryText())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 1 })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 12 })

          if (this.showRefreshButton) {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.play_arrow_triangle_2_circlepath'))
                .fontSize(20)
                .fontColor([themeOnPrimaryText()])
            }
            .width(40)
            .height(40)
            .backgroundColor(themeOnPrimaryActionBackground())
            .flexShrink(0)
            .margin({ left: 6 })
            .onClick(() => { this.onRefresh(); })
          }

          if (this.showSearchButton) {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(20)
                .fontColor([themeOnPrimaryText()])
            }
            .width(40)
            .height(40)
            .backgroundColor(themeOnPrimaryActionBackground())
            .flexShrink(0)
            .margin({ left: 6 })
            .onClick(() => { this.onSearch(); })
          }

          // Optional clear button
          if (this.showClear) {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(19)
                .fontColor([themeOnPrimaryText()])
            }
            .width(40)
            .height(40)
            .enabled(this.canClear)
            .backgroundColor(this.canClear ? themeOnPrimaryDangerBackground() : themeOnPrimaryActionDisabledBackground())
            .flexShrink(0)
            .margin({ left: 6 })
            .onClick(() => { this.onClear(); })
          }
        }
      }
      .width('100%')
      .height(this.barBodyHeight())
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(themePrimaryColor())
    }
    .width('100%')
    .translate({ y: this.translateY })
    .opacity(1)
    .visibility(this.barVisible() ? Visibility.Visible : Visibility.Hidden)
    .animation({ duration: 200, curve: Curve.EaseOut })
    .zIndex(10)
  }
}

// ===================================================================
// EhSubNavBar  -- back-arrow top bar for sub-pages (detail, settings)
// ===================================================================
@Component
export struct EhSubNavBar {
  @Prop statusBarHeight: number = 0;
  @Prop title: string = '';
  onBack: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    Column() {
      Column()
        .height(this.statusBarHeight)
        .width('100%')
        .backgroundColor(themePrimaryColor())

      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([themeOnPrimaryText()])
        }
        .width(40)
        .height(40)
        .backgroundColor(themeOnPrimaryActionBackground())
        .flexShrink(0)
        .onClick(() => { this.onBack(); })

        Text(uiText(this.title))
          .fontSize(19)
          .fontWeight(FontWeight.Medium)
          .fontColor(themeOnPrimaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(themePrimaryColor())
    }
    .width('100%')
    .zIndex(10)
  }
}

// ===================================================================
// Legacy shims -- kept so older code that still imports these still
// compiles until we migrate each caller
// ===================================================================
@Component
export struct AppToolbar {
  title: string = '';
  subtitle: string = '';
  onMenu: () => void = () => {};
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeight: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeight);
  }

  build() {
    EhNavBar({
      statusBarHeight: this.statusBarVp(),
      title: this.title,
      subtitle: this.subtitle,
      onMenu: this.onMenu,
      onRefresh: () => {}
    })
  }
}

@Component
export struct AppSubToolbar {
  title: string = '';
  onBack: () => void = () => {};
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeight: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeight);
  }

  build() {
    EhSubNavBar({
      statusBarHeight: this.statusBarVp(),
      title: this.title,
      onBack: this.onBack
    })
  }
}

@Component
export struct DrawerPanel {
  @Prop activeRoute: GalleryRoute = GalleryRoute.Home;
  onSelect: (route: GalleryRoute) => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    EhDrawer({
      activeRoute: this.activeRoute,
      statusBarHeight: 0,
      onSelect: this.onSelect
    })
  }
}

// ===================================================================
// FloatingToolbar / FloatingToolbarHost -- used by History & TopList scenes
// These provide scroll-hiding toolbar overlay behavior
// ===================================================================
@Component
export struct FloatingToolbar {
  @Prop visible: boolean = true;
  @Prop barHeight: number = 62;
  @Prop offsetY: number = 0;
  @BuilderParam content: () => void = this.EmptyContent;

  @Builder
  private EmptyContent() {}

  private toolbarOffset(): number {
    if (this.offsetY !== 0) {
      return this.offsetY;
    }
    return this.visible ? 0 : -this.barHeight;
  }

  private toolbarVisible(): boolean {
    return this.toolbarOffset() > -this.barHeight;
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .translate({ y: this.toolbarOffset() })
    .opacity(1)
    .visibility(this.toolbarVisible() ? Visibility.Visible : Visibility.Hidden)
    .animation({ duration: 200, curve: Curve.EaseOut })
    .zIndex(10)
  }
}

@Component
export struct FloatingToolbarHost {
  @Prop kind: string = 'title';
  @Prop title: string = '';
  @Prop keyword: string = '';
  @Prop searchPlaceholder: string = '';
  @Prop filterActive: boolean = false;
  @Prop requestUrl: string = '';
  @Prop showClear: boolean = false;
  @Prop canClear: boolean = false;
  @Prop showSearchButton: boolean = false;
  @Prop showRefreshButton: boolean = true;
  @Prop showBackButton: boolean = false;
  @Prop searchShowsAdvancedButton: boolean = false;
  @Prop toolbarOffsetY: number = 0;
  @Prop toolbarHeight: number = 62;
  @BuilderParam content: () => void = this.EmptyContent;
  onKeywordChange: (value: string) => void = () => {};
  onMenu: () => void = () => {};
  onBack: () => void = () => {};
  onSearch: () => void = () => {};
  onSearchFocus: () => void = () => {};
  onAdvanced: () => void = () => {};
  onRefresh: () => void = () => {};
  onClear: () => void = () => {};
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  private totalToolbarHeight(): number {
    return this.statusBarVp() + 56;
  }

  @Builder
  private EmptyContent() {}

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()
      FloatingToolbar({ offsetY: this.toolbarOffsetY, barHeight: this.totalToolbarHeight() }) {
        EhNavBar({
          statusBarHeight: this.statusBarVp(),
          title: this.title,
          searchMode: this.kind === 'search',
          keyword: this.keyword,
          searchPlaceholder: this.searchPlaceholder,
          filterActive: this.filterActive,
          showClear: this.showClear,
          canClear: this.canClear,
          showSearchButton: this.showSearchButton,
          showRefreshButton: this.showRefreshButton,
          showBackButton: this.showBackButton,
          searchShowsAdvancedButton: this.searchShowsAdvancedButton,
          onKeywordChange: this.onKeywordChange,
          onSearchFocus: this.onSearchFocus,
          onAdvanced: this.onAdvanced,
          onMenu: this.onMenu,
          onBack: this.onBack,
          onSearch: this.onSearch,
          onRefresh: this.onRefresh,
          onClear: this.onClear
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}

// Legacy search bar used by FloatingToolbarHost
@Component
struct LegacySearchBar {
  @Prop keyword: string = '';
  @Prop title: string = '';
  @Prop filterActive: boolean = false;
  onKeywordChange: (value: string) => void = () => {};
  onMenu: () => void = () => {};
  onSearch: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.open_sidebar'))
          .fontSize(22).fontColor([themeOnPrimaryText()])
      }
      .width(40).height(40)
      .backgroundColor(themeOnPrimaryActionBackground())
      .flexShrink(0)
      .onClick(() => { this.onMenu(); })

      TextInput({ text: this.keyword, placeholder: uiText(this.title.length > 0 ? this.title : 'Search') })
        .height(38)
        .layoutWeight(1)
        .backgroundColor(themeFieldBackground())
        .borderRadius(19)
        .fontColor(themePrimaryText())
        .caretColor(themePrimaryColor())
        .placeholderColor(themeSecondaryText())
        .padding({ left: 14, right: 14 })
        .margin({ left: 10 })
        .onChange((v: string) => { this.onKeywordChange(v); })

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(20).fontColor([themeOnPrimaryText()])
      }
      .width(40).height(40)
      .backgroundColor(themeOnPrimaryActionBackground())
      .flexShrink(0)
      .margin({ left: 8 })
      .onClick(() => { this.onSearch(); })
    }
    .width('100%')
    .height(62)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(themePrimaryColor())
  }
}

// Legacy action bar used by FloatingToolbarHost
@Component
struct LegacyActionBar {
  @Prop title: string = '';
  @Prop showClear: boolean = false;
  @Prop canClear: boolean = false;
  onMenu: () => void = () => {};
  onRefresh: () => void = () => {};
  onClear: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.open_sidebar'))
          .fontSize(22).fontColor([themeOnPrimaryText()])
      }
      .width(40).height(40)
      .backgroundColor(themeOnPrimaryActionBackground())
      .flexShrink(0)
      .onClick(() => { this.onMenu(); })

      Text(uiText(this.title))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(themeOnPrimaryText())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 12 })

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.play_arrow_triangle_2_circlepath'))
          .fontSize(20).fontColor([themeOnPrimaryText()])
      }
      .width(40).height(40)
      .backgroundColor(themeOnPrimaryActionBackground())
      .flexShrink(0)
      .margin({ left: 6 })
      .onClick(() => { this.onRefresh(); })

      if (this.showClear) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(19).fontColor([themeOnPrimaryText()])
        }
        .width(40).height(40)
        .enabled(this.canClear)
        .backgroundColor(this.canClear ? themeOnPrimaryDangerBackground() : themeOnPrimaryActionDisabledBackground())
        .flexShrink(0)
        .margin({ left: 6 })
        .onClick(() => { this.onClear(); })
      }
    }
    .width('100%')
    .height(62)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(themePrimaryColor())
  }
}

// Legacy aliases kept for source compatibility
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
    LegacySearchBar({
      keyword: this.keyword,
      title: this.title,
      filterActive: this.filterActive,
      onKeywordChange: this.onKeywordChange,
      onMenu: this.onMenu,
      onSearch: this.onSearch
    })
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
    LegacyActionBar({
      title: this.title,
      showClear: this.showClear,
      canClear: this.canClear,
      onMenu: this.onMenu,
      onRefresh: this.onRefresh,
      onClear: this.onClear
    })
  }
}

@Component
export struct AppTopBar {
  title: string = '';
  subtitle: string = '';
  symbol: Resource = $r('sys.symbol.open_sidebar');
  onAction: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph(this.symbol)
          .fontSize(22)
          .fontColor([themeOnPrimaryText()])
      }
      .width(40).height(40)
      .backgroundColor(themeOnPrimaryActionBackground())
      .onClick(() => { this.onAction(); })

      Column() {
        Text(uiText(this.title))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(themeOnPrimaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle.length > 0) {
          Text(uiText(this.subtitle))
            .fontSize(12)
            .fontColor(themeOnPrimarySecondaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 1 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('100%')
    .height(62)
    .padding({ left: 12, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(themePrimaryColor())
  }
}
