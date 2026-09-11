import { EhNavBar, EhTitleBarBackdrop } from './NavigationComponents';
import { immersiveChromeHeightFromOffset } from '../shared/EhShared';
import { uiTitleBarFadeHeight } from '../shared/EhUiStyle';

// The floating navigation bars observe this offset directly so a per-frame scroll update only
// refreshes the chrome instead of re-executing the whole gallery list component.
@Observed
export class GalleryToolbarOffset {
  offsetY: number = 0;
}

@Component
export struct GalleryHomeNavBarHost {
  @ObjectLink toolbarState: GalleryToolbarOffset;
  @Prop statusBarHeight: number = 0;
  @Prop title: string = '';
  @Prop keyword: string = '';
  @Prop filterActive: boolean = false;
  @Prop showSearchButton: boolean = false;
  @Prop showFavoriteButton: boolean = false;
  @Prop showBookmarkButton: boolean = false;
  @Prop showBackButton: boolean = false;
  onMenu: () => void = () => {
  };
  onBack: () => void = () => {
  };
  onSearch: () => void = () => {
  };
  onFavoriteButton: () => void = () => {
  };
  onBookmarkButton: () => void = () => {
  };
  onKeywordChange: (value: string) => void = (_value: string) => {
  };
  onRefresh: () => void = () => {
  };

  build() {
    EhNavBar({
      statusBarHeight: this.statusBarHeight,
      title: this.title,
      searchMode: false,
      keyword: this.keyword,
      filterActive: this.filterActive,
      showSearchButton: this.showSearchButton,
      showFavoriteButton: this.showFavoriteButton,
      showBookmarkButton: this.showBookmarkButton,
      showRefreshButton: false,
      showBackButton: this.showBackButton,
      translateY: this.toolbarState.offsetY,
      onMenu: () => {
        this.onMenu();
      },
      onBack: () => {
        this.onBack();
      },
      onSearch: () => {
        this.onSearch();
      },
      onFavoriteButton: () => {
        this.onFavoriteButton();
      },
      onBookmarkButton: () => {
        this.onBookmarkButton();
      },
      onKeywordChange: (value: string) => {
        this.onKeywordChange(value);
      },
      onRefresh: () => {
        this.onRefresh();
      }
    })
  }
}

@Component
export struct GallerySearchNavBarHost {
  @ObjectLink toolbarState: GalleryToolbarOffset;
  @Prop searchSubmitted: boolean = false;
  @Prop statusBarHeight: number = 0;
  @Prop totalBarHeight: number = 0;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  private visibleBarHeight(): number {
    return immersiveChromeHeightFromOffset(this.toolbarState.offsetY, this.totalBarHeight);
  }

  private backdropHeight(): number {
    const fadeHeight = uiTitleBarFadeHeight();
    const minimumHeight = this.statusBarHeight + fadeHeight;
    return Math.max(minimumHeight,
      Math.min(this.totalBarHeight + fadeHeight, this.totalBarHeight + this.toolbarState.offsetY + fadeHeight));
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      EhTitleBarBackdrop({
        barBackdropHeight: this.searchSubmitted ? this.backdropHeight() :
          this.totalBarHeight + uiTitleBarFadeHeight()
      })

      Column() {
        this.content()
      }
      .width('100%')
      .translate({ y: this.searchSubmitted ? this.toolbarState.offsetY : 0 })
      .visibility(!this.searchSubmitted || this.visibleBarHeight() > 0 ? Visibility.Visible : Visibility.Hidden)
    }
    .width('100%')
    .height(this.searchSubmitted ? this.backdropHeight() : this.totalBarHeight + uiTitleBarFadeHeight())
    .backgroundColor(Color.Transparent)
    .zIndex(10)
  }
}
