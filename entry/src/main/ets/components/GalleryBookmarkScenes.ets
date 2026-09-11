import { GalleryCategory, GalleryRoute } from '../model/GalleryModels';
import { SearchBookmarkInfo } from '../services/EhBookmarkStore';
import { BrowsePosition, ehBrowsePositionStore } from '../services/EhBrowsePositionStore';
import { FavListUrlBuilder, ListMode } from '../services/EhUrl';
import { FavoriteCategoryInfo } from '../services/GalleryListParser';
import { LANGUAGE_REVISION_KEY } from '../shared/EhShared';
import {
  themeDividerColor,
  themeFieldBackground,
  themePageBackground,
  themePrimaryText,
  themeSecondaryText,
  themeSelectedBackground,
  themeSelectedBackgroundLight,
  themeSelectedText,
  themeSurface,
  themeSurfaceVariant,
  themeTertiaryText,
  themeTransparentColor,
} from '../shared/EhTheme';
import {
  uiButtonMaterial,
  uiTransparentButtonBackgroundEffect,
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiDialogMaterial,
  uiDialogSurfaceBackground,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiRadius,
} from '../shared/EhUiStyle';
import { PopupScrim } from './PopupScrim';
import {
  SidePanelHeader,
  SidePanelEditableManagerRow,
  SidePanelManagerHeader,
  SidePanelRow,
} from './SidePanelComponents';
import {
  uiText,
  getAbilityContext,
} from '../shared/EhShared';
import {
  FavoriteCategoryOption,
  DefaultFavoriteSlotOption,
  favoriteCategoryOptions,
  defaultFavoriteSlotOptions,
  favoriteCategoryCountText,
} from './GalleryListSupport';

@Component
export struct FavoriteCategoryDrawer {
  @Prop statusBarHeight: number = 0;
  @Prop selectedFavCat: number = FavListUrlBuilder.FAV_CAT_ALL;
  @Prop categories: FavoriteCategoryInfo[] = [];
  @Prop localFavoriteCount: number = -1;
  onSelect: (favCat: number) => void = (_favCat: number) => {};
  onSettings: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  private options(): FavoriteCategoryOption[] {
    return favoriteCategoryOptions(this.categories, this.localFavoriteCount);
  }

  build() {
    Column() {
      SidePanelHeader({
        statusBarHeight: this.statusBarHeight,
        title: 'Favorite folders',
        showFirstAction: true,
        firstActionIcon: $r('sys.symbol.gearshape'),
        onFirstAction: () => {
          this.onSettings();
        }
      })

      List() {
        ForEach(this.options(), (item: FavoriteCategoryOption) => {
          ListItem() {
            FavoriteCategoryDrawerRow({
              item: item,
              selected: item.favCat === this.selectedFavCat,
              onTap: () => {
                this.onSelect(item.favCat);
              }
            })
          }
          .reuseId('favorite-category-drawer-row')
        }, (item: FavoriteCategoryOption) => item.favCat.toString() + ':' + item.name + ':' + item.count.toString())
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .cachedCount(4)
    }
    .width(288)
    .height('100%')
    .backgroundColor(uiMaterialBackground(themeSurface()))
  }
}

@Component
export struct DefaultFavoriteSlotDialog {
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;
  @Prop selectedSlot: number | null = null;
  @Prop categories: FavoriteCategoryInfo[] = [];
  @Prop panelMaxHeight: number = 680;
  onSelect: (slot: number | null) => void = (_slot: number | null) => {};
  onClose: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  private options(): DefaultFavoriteSlotOption[] {
    return defaultFavoriteSlotOptions(this.categories);
  }

  private listHeight(): number {
    const contentHeight = this.options().length * 52;
    return Math.min(contentHeight, Math.max(156, this.panelMaxHeight - 57));
  }

  private panelHeight(): number {
    return this.listHeight() + 57;
  }

  private optionKey(slot: number | null): string {
    return slot === null ? 'ask' : slot.toString();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      PopupScrim({
        showCutout: this.popupWidth > 0 && this.popupHeight > 0,
        cutoutWidth: this.popupWidth,
        cutoutHeight: this.popupHeight,
        cutoutRadius: uiDialogSurfaceRadius(),
        onDismiss: () => {
          this.onClose();
        }
      })

      Column() {
        Row() {
          Text(uiText('Default favorites collection'))
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(20)
              .fontColor([uiMaterialForegroundColor(themePrimaryText())])
          }
          .width(40)
          .height(40)
          .backgroundColor(uiMaterialBackground(themeFieldBackground()))
          .backgroundEffect(uiTransparentButtonBackgroundEffect())
          .systemMaterial(uiButtonMaterial())
          .onClick(() => {
            this.onClose();
          })
        }
        .width('100%')
        .height(56)
        .padding({ left: 18, right: 12 })
        .alignItems(VerticalAlign.Center)

        Divider().color(themeDividerColor()).strokeWidth(0.5)

        List() {
          ForEach(this.options(), (item: DefaultFavoriteSlotOption) => {
            ListItem() {
              Row() {
                Column() {
                  SymbolGlyph(item.slot === null ? $r('sys.symbol.list_number') :
                    (item.slot === -1 ? $r('sys.symbol.heart') : $r('sys.symbol.folder')))
                    .fontSize(21)
                    .fontColor([item.slot === this.selectedSlot ? themeSelectedText() : themeSecondaryText()])
                }
                .width(38)
                .height(38)
                .borderRadius(uiRadius(9))
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .backgroundColor(item.slot === this.selectedSlot ?
                  themeSelectedBackgroundLight() : themeSurfaceVariant())

                Text(uiText(item.name))
                  .fontSize(15)
                  .fontWeight(item.slot === this.selectedSlot ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(item.slot === this.selectedSlot ? themeSelectedText() : themePrimaryText())
                  .layoutWeight(1)
                  .margin({ left: 12 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                if (item.slot === this.selectedSlot) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(20)
                    .fontColor([themeSelectedText()])
                }
              }
              .width('100%')
              .height(52)
              .padding({ left: 18, right: 18 })
              .backgroundColor(item.slot === this.selectedSlot ?
                themeSelectedBackground() : themeTransparentColor())
              .onClick(() => {
                this.onSelect(item.slot);
              })
            }
          }, (item: DefaultFavoriteSlotOption) => this.optionKey(item.slot))
        }
        .width('100%')
        .height(this.listHeight())
        .cachedCount(4)
      }
      .width('78%')
      .height(this.panelHeight())
      .constraintSize({ maxWidth: 360, minWidth: 280, maxHeight: this.panelMaxHeight })
      .backgroundColor(uiMaterialBackground(uiDialogSurfaceBackground()))
      .shadow(uiDialogSurfaceShadow())
      .borderRadius(uiDialogSurfaceRadius())
      .backgroundBlurStyle(uiDialogBlurStyle(), uiDialogBlurOptions())
      .systemMaterial(uiDialogMaterial())
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.popupWidth = Number.parseFloat(newArea.width.toString());
        this.popupHeight = Number.parseFloat(newArea.height.toString());
      })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct FavoriteCategoryDrawerRow {
  item: FavoriteCategoryOption = { favCat: FavListUrlBuilder.FAV_CAT_ALL, name: 'All favorites', count: -1 };
  selected: boolean = false;
  onTap: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    SidePanelRow({
      title: this.item.name,
      subtitle: this.item.count >= 0 ? favoriteCategoryCountText(this.item.count) : '',
      selected: this.selected,
      icon: this.item.favCat === FavListUrlBuilder.FAV_CAT_ALL ?
        $r('sys.symbol.heart') : $r('sys.symbol.folder'),
      onTap: () => {
        this.onTap();
      }
    })
  }
}

function bookmarkModeLabel(mode: ListMode): string {
  if (mode === ListMode.Uploader) {
    return 'Specify uploader';
  }
  if (mode === ListMode.Tag) {
    return 'Specify tag';
  }
  if (mode === ListMode.Subscription) {
    return 'Subscription';
  }
  if (mode === ListMode.WhatsHot) {
    return 'Whats Hot';
  }
  if (mode === ListMode.Filter) {
    return 'Filter';
  }
  if (mode === ListMode.TopList) {
    return 'Toplists';
  }
  return 'General';
}

function bookmarkLocationLabel(route: GalleryRoute): string {
  if (route === GalleryRoute.Subscription) {
    return 'Subscription';
  }
  if (route === GalleryRoute.WhatsHot) {
    return 'Whats Hot';
  }
  return 'All site';
}

function bookmarkSummary(item: SearchBookmarkInfo): string {
  const parts: string[] = [uiText(bookmarkLocationLabel(item.location)), uiText(bookmarkModeLabel(item.mode))];
  if (item.keyword.length > 0) {
    parts.push(item.keyword);
  }
  if (item.category !== GalleryCategory.None) {
    parts.push('cat=' + item.category.toString());
  }
  if (item.advanceSearch !== -1 || item.minRating !== -1 || item.pageFrom !== -1 || item.pageTo !== -1) {
    parts.push(uiText('Advanced'));
  }
  if (!item.filterEnabled) {
    parts.push(uiText('Filter Off'));
  }
  return parts.join(' · ');
}

@Component
export struct SearchBookmarkDrawer {
  @Prop statusBarHeight: number = 0;
  @Prop bookmarks: SearchBookmarkInfo[] = [];
  onSelect: (bookmark: SearchBookmarkInfo) => void = (_bookmark: SearchBookmarkInfo) => {};
  onAdd: () => void = () => {};
  onDelete: (bookmark: SearchBookmarkInfo) => void = (_bookmark: SearchBookmarkInfo) => {};
  onSettings: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  private bookmarkScroller: Scroller = new Scroller();
  private restoringScrollPosition: boolean = false;
  private positionLoaded: boolean = false;
  private firstVisibleIndex: number = 0;
  private lastScrollOffset: number = 0;
  private componentActive: boolean = false;

  aboutToAppear(): void {
    this.componentActive = true;
    const context = getAbilityContext();
    if (context === undefined) {
      return;
    }
    ehBrowsePositionStore.ensureLoaded(context).then(() => {
      this.positionLoaded = true;
      this.restoreScrollPosition();
    }).catch(() => {});
  }

  aboutToDisappear(): void {
    this.componentActive = false;
    this.rememberCachedScrollPosition();
    ehBrowsePositionStore.flush();
  }

  private bookmarkIndexById(id: string): number {
    if (id.length === 0) {
      return -1;
    }
    for (let i = 0; i < this.bookmarks.length; i++) {
      if (this.bookmarks[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  private restoreScrollPosition(): void {
    if (!this.positionLoaded || this.bookmarks.length === 0) {
      return;
    }
    const position: BrowsePosition = ehBrowsePositionStore.getBookmarkDrawerPosition();
    this.lastScrollOffset = Math.max(0, position.offset);
    let targetIndex = this.bookmarkIndexById(position.anchorId);
    if (targetIndex < 0) {
      targetIndex = Math.min(position.anchorIndex, this.bookmarks.length - 1);
    }
    this.firstVisibleIndex = targetIndex;
    this.restoringScrollPosition = true;
    setTimeout(() => {
      if (!this.componentActive) {
        return;
      }
      if (targetIndex === position.anchorIndex && position.offset > 0) {
        this.bookmarkScroller.scrollTo({ xOffset: 0, yOffset: position.offset });
      } else if (targetIndex > 0) {
        this.bookmarkScroller.scrollToIndex(targetIndex);
      }
      setTimeout(() => {
        if (this.componentActive) {
          this.restoringScrollPosition = false;
        }
      }, 80);
    }, 0);
  }

  private rememberCachedScrollPosition(): void {
    if (this.restoringScrollPosition || this.bookmarks.length === 0) {
      return;
    }
    const index = Math.max(0, Math.min(this.firstVisibleIndex, this.bookmarks.length - 1));
    const anchorId = this.bookmarks[index].id;
    ehBrowsePositionStore.updateBookmarkDrawerPosition(anchorId, index, this.lastScrollOffset);
  }

  private captureScrollPosition(): void {
    if (this.restoringScrollPosition || !this.componentActive) {
      return;
    }
    const currentOffset = this.bookmarkScroller.currentOffset();
    if (currentOffset === undefined || Number.isNaN(currentOffset.yOffset)) {
      return;
    }
    this.lastScrollOffset = Math.max(0, currentOffset.yOffset);
    this.rememberCachedScrollPosition();
  }

  build() {
    Column() {
      SidePanelHeader({
        statusBarHeight: this.statusBarHeight,
        title: 'Bookmarks',
        showFirstAction: true,
        firstActionIcon: $r('sys.symbol.plus'),
        showSecondAction: true,
        secondActionIcon: $r('sys.symbol.gearshape'),
        onFirstAction: () => {
          this.onAdd();
        },
        onSecondAction: () => {
          this.onSettings();
        }
      })

      if (this.bookmarks.length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.bookmark'))
            .fontSize(34)
            .fontColor([themeTertiaryText()])
          Text(uiText('No bookmarks'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
          Text(uiText('Tap plus to bookmark the current gallery list'))
            .fontSize(13)
            .fontColor(themeSecondaryText())
            .textAlign(TextAlign.Center)
            .padding({ left: 22, right: 22 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ scroller: this.bookmarkScroller }) {
          ForEach(this.bookmarks, (item: SearchBookmarkInfo, index: number) => {
            ListItem() {
              SearchBookmarkDrawerRow({
                item: this.bookmarks[index],
                onTap: () => {
                  this.onSelect(this.bookmarks[index]);
                },
                onDelete: () => {
                  this.onDelete(this.bookmarks[index]);
                }
              })
            }
            .reuseId('search-bookmark-drawer-row')
          }, (item: SearchBookmarkInfo, index: number) => item.id + ':' + index.toString())
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .cachedCount(6)
        .onAppear(() => {
          this.restoreScrollPosition();
        })
        .onDidScroll((_scrollOffset: number, _scrollState: ScrollState) => {
          this.captureScrollPosition();
        })
        .onScrollIndex((first: number, _last: number) => {
          this.firstVisibleIndex = Math.max(0, first);
        })
        .onScrollStop(() => {
          this.captureScrollPosition();
        })
      }
    }
    .width(288)
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}

@Component
export struct SearchBookmarkDrawerRow {
  @Prop item: SearchBookmarkInfo = {
    id: '',
    name: '',
    mode: ListMode.Normal,
    category: GalleryCategory.None,
    keyword: '',
    advanceSearch: -1,
    minRating: -1,
    pageFrom: -1,
    pageTo: -1,
    filterEnabled: true,
    location: GalleryRoute.Home,
    time: 0
  };
  onTap: () => void = () => {};
  onDelete: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    SidePanelRow({
      title: this.item.name,
      subtitle: bookmarkSummary(this.item),
      icon: $r('sys.symbol.bookmark'),
      showDelete: true,
      onTap: () => {
        this.onTap();
      },
      onDelete: () => {
        this.onDelete();
      }
    })
  }
}

@Component
export struct SearchBookmarkManagerScene {
  @Prop bookmarks: SearchBookmarkInfo[] = [];
  @Prop statusBarHeight: number = 0;
  onBack: () => void = () => {};
  onRename: (bookmark: SearchBookmarkInfo, name: string) => void = (_bookmark: SearchBookmarkInfo, _name: string) => {};
  onEdit: (bookmark: SearchBookmarkInfo) => void = (_bookmark: SearchBookmarkInfo) => {};
  onMoveIndex: (from: number, to: number) => void = (_from: number, _to: number) => {};
  onDelete: (bookmark: SearchBookmarkInfo) => void = (_bookmark: SearchBookmarkInfo) => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @State editingBookmarkId: string = '';

  build() {
    Column() {
      SidePanelManagerHeader({
        statusBarHeight: this.statusBarHeight,
        title: 'Bookmark settings',
        onBack: () => {
          this.onBack();
        }
      })

      if (this.bookmarks.length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.bookmark'))
            .fontSize(34)
            .fontColor([themeTertiaryText()])
          Text(uiText('No bookmarks'))
            .fontSize(16)
            .fontColor(themeSecondaryText())
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 8 }) {
          ListItem() {
            Row()
              .height(0)
          }

          // Observe the current array entry, not the object captured when ForEach first created the row.
          ForEach(this.bookmarks, (item: SearchBookmarkInfo, index: number) => {
            ListItem() {
              SidePanelEditableManagerRow({
                rowId: this.bookmarks[index].id,
                value: this.bookmarks[index].name,
                placeholder: 'Bookmark name',
                subtitle: bookmarkSummary(this.bookmarks[index]),
                editing: this.editingBookmarkId === this.bookmarks[index].id,
                onStartEdit: () => {
                  this.editingBookmarkId = this.bookmarks[index].id;
                },
                onFinishEdit: () => {
                  if (this.editingBookmarkId === this.bookmarks[index].id) {
                    this.editingBookmarkId = '';
                  }
                },
                onValueChange: (name: string) => {
                  this.onRename(this.bookmarks[index], name);
                },
                onCommit: (name: string) => {
                  this.onRename(this.bookmarks[index], name);
                },
                onDelete: () => {
                  this.onDelete(this.bookmarks[index]);
                },
                showEdit: true,
                onEdit: () => {
                  this.onEdit(this.bookmarks[index]);
                }
              })
            }
            .reuseId('search-bookmark-manager-row')
          }, (item: SearchBookmarkInfo, index: number) => item.id + ':' + index.toString())
            .onMove((from: number, to: number) => {
              this.onMoveIndex(from, to);
            })

          ListItem() {
            Row()
              .height(0)
          }
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .padding({ left: 10, right: 10 })
        .clip(false)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}
