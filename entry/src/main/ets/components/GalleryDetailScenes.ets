import { GalleryDetail, GalleryPreview } from '../model/GalleryModels';
import { GalleryComment } from '../model/GalleryModels';
import { GalleryTagInfo } from '../model/GalleryModels';
import { ArchiveOption, ArchiverInfo, ArchiverOption, HathArchiveList } from '../model/GalleryModels';
import { ehTagTranslationStore } from '../services/EhTagTranslationStore';
import { STATUS_BAR_HEIGHT_KEY, createEmptyDetail, galleryDisplayTitle, shouldUseChineseUi, uiText } from '../shared/EhShared';
import { themePageBackground, themeScrimColor } from '../shared/EhTheme';
import {
  themeDividerColor,
  themeInactiveActionText,
  themePrimaryText,
  themeSecondaryText,
  themeShadowColor,
  themeSurface,
  themeSurfaceVariant
} from '../shared/EhTheme';
import { EhSubNavBar } from './NavigationComponents';
import { CommentsScene } from './ReaderScenes';
import { DetailHeader } from './detail/DetailHeader';
import { DetailInfoBlock, GalleryInfoScene } from './detail/DetailInfo';
import { DetailActions, RatingPanel } from './detail/DetailActions';
import { DetailTags } from './detail/DetailTags';
import { DetailPreviews, DetailPreviewJumpOverlay } from './detail/DetailPreviews';
import { DetailComments } from './detail/DetailComments';

@Component
export struct GalleryDetailOverlayScene {
  @Prop renderVersion: number = 0;
  @Prop showInfo: boolean = false;
  @Prop showComments: boolean = false;
  @Prop detail: GalleryDetail = createEmptyDetail();
  @Prop isDetailLoaded: boolean = false;
  @Prop isFavorited: boolean = false;
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  @Prop downloadText: string = 'Download';
  @Prop archivePanelVisible: boolean = false;
  @Prop archivePanelMode: string = '';
  @Prop archivePanelStatus: string = '';
  @Prop archiveBusy: boolean = false;
  @Prop archiverInfo: ArchiverInfo = { funds: '', options: [] };
  @Prop hathArchiveList: HathArchiveList = { formParamOr: '', options: [] };
  initialDetailScrollOffset: number = 0;
  onBack: () => void = () => {};
  onShowInfo: () => void = () => {};
  onCloseInfo: () => void = () => {};
  onCloseComments: () => void = () => {};
  onDownload: () => void = () => {};
  onRead: () => void = () => {};
  onSelectPreview: (preview: GalleryPreview) => void = () => {};
  onJumpPreviewPage: (pageIndex: number) => void = (_pageIndex: number) => {};
  onComments: () => void = () => {};
  onVoteComment: (comment: GalleryComment, vote: number) => void = (_comment: GalleryComment, _vote: number) => {};
  onOpenCommentGalleryLink: (url: string) => void = (_url: string) => {};
  onFavorite: () => void = () => {};
  onShare: () => void = () => {};
  onRate: (rating: number) => void = (_rating: number) => {};
  onTorrent: () => void = () => {};
  onArchive: () => void = () => {};
  onHath: () => void = () => {};
  onSimilar: () => void = () => {};
  onSearchCover: () => void = () => {};
  onCloseArchivePanel: () => void = () => {};
  onSelectArchiverOption: (option: ArchiverOption) => void = (_option: ArchiverOption) => {};
  onSelectHathOption: (option: ArchiveOption) => void = (_option: ArchiveOption) => {};
  onLoadMorePreviews: () => void = () => {};
  onRefreshDetail: (done: () => void) => void = (_done: () => void) => {};
  onDetailScrollUpdate: (offset: number) => void = () => {};
  onTagSearch: (namespace: string, tag: string) => void = (_namespace: string, _tag: string) => {};
  onVoteTag: (fullTag: string, vote: number) => void = (_fullTag: string, _vote: number) => {};
  onAddTag: (fullTag: string) => void = (_fullTag: string) => {};
  onShowTagDefinition: (fullTag: string) => void = (_fullTag: string) => {};
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  build() {
    if (this.showInfo) {
      GalleryInfoScene({
        detail: this.detail,
        requestUrl: this.requestUrl,
        statusBarHeight: this.statusBarVp(),
        onBack: this.onCloseInfo
      })
    } else if (this.showComments) {
      CommentsScene({
        renderVersion: this.renderVersion,
        comments: this.detail.comments,
        galleryTitle: galleryDisplayTitle(this.detail),
        onBack: this.onCloseComments,
        onVoteComment: this.onVoteComment,
        onOpenGalleryLink: this.onOpenCommentGalleryLink
      })
    } else {
      GalleryDetailScene({
        renderVersion: this.renderVersion,
        detail: this.detail,
        isDetailLoaded: this.isDetailLoaded,
        isFavorited: this.isFavorited,
        statusText: this.statusText,
        requestUrl: this.requestUrl,
        downloadText: this.downloadText,
        archivePanelVisible: this.archivePanelVisible,
        archivePanelMode: this.archivePanelMode,
        archivePanelStatus: this.archivePanelStatus,
        archiveBusy: this.archiveBusy,
        archiverInfo: this.archiverInfo,
        hathArchiveList: this.hathArchiveList,
        onBack: this.onBack,
        onShowInfo: this.onShowInfo,
        onCloseInfo: this.onCloseInfo,
        onDownload: this.onDownload,
        onRead: this.onRead,
        onSelectPreview: this.onSelectPreview,
        onJumpPreviewPage: this.onJumpPreviewPage,
        onComments: this.onComments,
        onVoteComment: this.onVoteComment,
        onOpenCommentGalleryLink: this.onOpenCommentGalleryLink,
        onFavorite: this.onFavorite,
        onShare: this.onShare,
        onRate: this.onRate,
        onTorrent: this.onTorrent,
        onArchive: this.onArchive,
        onHath: this.onHath,
        onSimilar: this.onSimilar,
        onSearchCover: this.onSearchCover,
        onCloseArchivePanel: this.onCloseArchivePanel,
        onSelectArchiverOption: this.onSelectArchiverOption,
        onSelectHathOption: this.onSelectHathOption,
        onLoadMorePreviews: this.onLoadMorePreviews,
        onRefreshDetail: this.onRefreshDetail,
        initialDetailScrollOffset: this.initialDetailScrollOffset,
        onDetailScrollUpdate: this.onDetailScrollUpdate,
        onTagSearch: this.onTagSearch,
        onVoteTag: this.onVoteTag,
        onAddTag: this.onAddTag,
        onShowTagDefinition: this.onShowTagDefinition
      })
    }
  }
}

@Component
export struct GalleryDetailScene {
  @Prop renderVersion: number = 0;
  @Prop detail: GalleryDetail = createEmptyDetail();
  @Prop isDetailLoaded: boolean = false;
  @Prop isFavorited: boolean = false;
  @Prop statusText: string = '';
  @Prop requestUrl: string = '';
  @Prop downloadText: string = 'Download';
  @Prop archivePanelVisible: boolean = false;
  @Prop archivePanelMode: string = '';
  @Prop archivePanelStatus: string = '';
  @Prop archiveBusy: boolean = false;
  @Prop archiverInfo: ArchiverInfo = { funds: '', options: [] };
  @Prop hathArchiveList: HathArchiveList = { formParamOr: '', options: [] };
  onBack: () => void = () => {};
  onShowInfo: () => void = () => {};
  onCloseInfo: () => void = () => {};
  onDownload: () => void = () => {};
  onRead: () => void = () => {};
  onSelectPreview: (preview: GalleryPreview) => void = () => {};
  onJumpPreviewPage: (pageIndex: number) => void = (_pageIndex: number) => {};
  onComments: () => void = () => {};
  onVoteComment: (comment: GalleryComment, vote: number) => void = (_comment: GalleryComment, _vote: number) => {};
  onOpenCommentGalleryLink: (url: string) => void = (_url: string) => {};
  onFavorite: () => void = () => {};
  onShare: () => void = () => {};
  onRate: (rating: number) => void = (_rating: number) => {};
  onTorrent: () => void = () => {};
  onArchive: () => void = () => {};
  onHath: () => void = () => {};
  onSimilar: () => void = () => {};
  onSearchCover: () => void = () => {};
  onCloseArchivePanel: () => void = () => {};
  onSelectArchiverOption: (option: ArchiverOption) => void = (_option: ArchiverOption) => {};
  onSelectHathOption: (option: ArchiveOption) => void = (_option: ArchiveOption) => {};
  onLoadMorePreviews: () => void = () => {};
  onRefreshDetail: (done: () => void) => void = (_done: () => void) => {};
  initialDetailScrollOffset: number = 0;
  onDetailScrollUpdate: (offset: number) => void = () => {};
  onTagSearch: (namespace: string, tag: string) => void = (_namespace: string, _tag: string) => {};
  onVoteTag: (fullTag: string, vote: number) => void = (_fullTag: string, _vote: number) => {};
  onAddTag: (fullTag: string) => void = (_fullTag: string) => {};
  onShowTagDefinition: (fullTag: string) => void = (_fullTag: string) => {};
  private detailScroller: Scroller = new Scroller();
  @State showRatingDialog: boolean = false;
  @State pendingRating: number = 0;
  @State previewJumpPanelVisible: boolean = false;
  @State previewJumpPageIndex: number = 0;
  @State detailRefreshing: boolean = false;
  @State tagVotePanelVisible: boolean = false;
  @State tagVoteTarget: GalleryTagInfo = createEmptyTagInfo();
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeightPx: number = 0;

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  private startRating(): void {
    if (!this.isDetailLoaded || this.detail.apiUid < 0 || this.detail.apiKey.length === 0) {
      return;
    }
    const current = this.detail.rated && this.detail.rating > 0 ? Math.round(this.detail.rating) : 5;
    this.pendingRating = Math.max(1, Math.min(5, current));
    this.showRatingDialog = true;
  }

  private previewJumpTotalPages(): number {
    if (this.detail.previewPages > 0) {
      return this.detail.previewPages;
    }
    return this.detail.previewSet.length > 0 ? 1 : 0;
  }

  private openPreviewJumpPanel(): void {
    const total = this.previewJumpTotalPages();
    if (!this.isDetailLoaded || total <= 1) {
      return;
    }
    this.previewJumpPageIndex = Math.max(0, Math.min(this.previewJumpPageIndex, total - 1));
    this.previewJumpPanelVisible = true;
  }

  private closePreviewJumpPanel(pageIndex: number): void {
    const total = this.previewJumpTotalPages();
    const target = Math.max(0, Math.min(pageIndex, Math.max(0, total - 1)));
    this.previewJumpPageIndex = target;
    this.previewJumpPanelVisible = false;
    if (total > 1) {
      this.onJumpPreviewPage(target);
    }
  }

  private openTagVotePanel(info: GalleryTagInfo): void {
    this.tagVoteTarget = cloneTagInfo(info);
    this.tagVotePanelVisible = true;
  }

  private closeTagVotePanel(): void {
    this.tagVotePanelVisible = false;
  }

  private submitTagVote(vote: number): void {
    const fullTag = this.tagVoteTarget.fullTag;
    this.tagVotePanelVisible = false;
    this.onVoteTag(fullTag, vote);
  }

  private showTaggedGalleries(): void {
    const tag = cloneTagInfo(this.tagVoteTarget);
    this.tagVotePanelVisible = false;
    this.onTagSearch(tag.namespace, tag.tag);
  }

  private showTagDefinition(): void {
    const fullTag = this.tagVoteTarget.fullTag;
    this.tagVotePanelVisible = false;
    this.onShowTagDefinition(fullTag);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        EhSubNavBar({
          statusBarHeight: this.statusBarVp(),
          title: galleryDisplayTitle(this.detail),
          onBack: this.onBack
        })

        Refresh({ refreshing: $$this.detailRefreshing }) {
          List({ space: 0, scroller: this.detailScroller }) {
            ListItem() {
              DetailHeader({
                detail: this.detail,
                downloadText: this.downloadText,
                onDownload: this.onDownload,
                onRead: this.onRead
              })
            }
            .reuseId('detail-header')
            ListItem() {
              DetailInfoBlock({
                detail: this.detail,
                requestUrl: this.requestUrl,
                isDetailLoaded: this.isDetailLoaded,
                onMoreInfo: this.onShowInfo
              })
            }
            .reuseId('detail-info')
            ListItem() {
              DetailActions({
                detail: this.detail,
                isDetailLoaded: this.isDetailLoaded,
                isFavorited: this.isFavorited,
                onFavorite: this.onFavorite,
                onShare: this.onShare,
                onRate: () => {
                  this.startRating();
                },
                onTorrent: this.onTorrent,
                onArchive: this.onArchive,
                onHath: this.onHath,
                onSimilar: this.onSimilar,
                onSearchCover: this.onSearchCover
              })
            }
            .reuseId('detail-actions')
            ListItem() {
              DetailTags({
                renderVersion: this.renderVersion,
                tags: this.detail.tags,
                isDetailLoaded: this.isDetailLoaded,
                onTagSearch: this.onTagSearch,
                onAddTag: this.onAddTag,
                onOpenTagVote: (info: GalleryTagInfo) => {
                  this.openTagVotePanel(info);
                }
              })
            }
            .reuseId('detail-tags')
            ListItem() {
              DetailComments({
                comments: this.detail.comments,
                isDetailLoaded: this.isDetailLoaded,
                onComments: this.onComments,
                onVoteComment: this.onVoteComment,
                onOpenGalleryLink: this.onOpenCommentGalleryLink
              })
            }
            .reuseId('detail-comments')
            ListItem() {
              DetailPreviews({
                previews: this.detail.previewSet,
                previewPages: this.detail.previewPages,
                totalPages: this.previewJumpTotalPages(),
                isDetailLoaded: this.isDetailLoaded,
                onSelectPreview: this.onSelectPreview,
                onOpenJumpPanel: () => {
                  this.openPreviewJumpPanel();
                }
              })
            }
            .reuseId('detail-previews')
          }
          .width('100%')
          .height('100%')
          .backgroundColor(themePageBackground())
          .cachedCount(3)
          .onAppear(() => {
            if (this.initialDetailScrollOffset > 0) {
              this.detailScroller.scrollTo({ xOffset: 0, yOffset: this.initialDetailScrollOffset });
            }
          })
          .onScrollStop(() => {
            this.onDetailScrollUpdate(this.detailScroller.currentOffset().yOffset);
          })
          .onReachEnd(() => {
            this.onLoadMorePreviews();
          })
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .backgroundColor(themePageBackground())
        .refreshOffset(64)
        .pullToRefresh(true)
        .onRefreshing(() => {
          this.detailRefreshing = true;
          this.onRefreshDetail(() => {
            this.detailRefreshing = false;
          });
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(themePageBackground())

      if (this.showRatingDialog) {
        Column() {
          RatingPanel({
            rating: this.pendingRating,
            onChange: (rating: number) => {
              this.pendingRating = rating;
            },
            onCancel: () => {
              this.showRatingDialog = false;
            },
            onSubmit: () => {
              this.showRatingDialog = false;
              this.onRate(this.pendingRating);
            }
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding(24)
          .backgroundColor(themeScrimColor())
      }
      if (this.previewJumpPanelVisible) {
        DetailPreviewJumpOverlay({
          totalPages: this.previewJumpTotalPages(),
          initialPageIndex: this.previewJumpPageIndex,
          onClose: (pageIndex: number) => {
            this.closePreviewJumpPanel(pageIndex);
          }
        })
        .zIndex(12)
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }
      if (this.tagVotePanelVisible) {
        TagVoteOverlay({
          tag: this.tagVoteTarget,
          onDismiss: () => {
            this.closeTagVotePanel();
          },
          onVote: (vote: number) => {
            this.submitTagVote(vote);
          },
          onShowTaggedGalleries: () => {
            this.showTaggedGalleries();
          },
          onShowTagDefinition: () => {
            this.showTagDefinition();
          }
        })
        .zIndex(14)
        .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
      }
      if (this.archivePanelVisible) {
        ArchiveOptionsOverlay({
          mode: this.archivePanelMode,
          statusText: this.archivePanelStatus,
          busy: this.archiveBusy,
          archiverInfo: this.archiverInfo,
          hathArchiveList: this.hathArchiveList,
          onDismiss: this.onCloseArchivePanel,
          onSelectArchiverOption: this.onSelectArchiverOption,
          onSelectHathOption: this.onSelectHathOption
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}

@Component
struct TagVoteOverlay {
  tag: GalleryTagInfo = createEmptyTagInfo();
  onDismiss: () => void = () => {};
  onVote: (vote: number) => void = (_vote: number) => {};
  onShowTaggedGalleries: () => void = () => {};
  onShowTagDefinition: () => void = () => {};

  private translatedTitle(): string {
    return translatedTagLabel(this.tag);
  }

  private showTranslatedTitle(): boolean {
    return shouldUseChineseUi() && this.translatedTitle().length > 0 && this.translatedTitle() !== this.tag.tag;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {}
        .width('100%')
        .height('100%')
        .backgroundColor(themeScrimColor())
        .onClick(() => {
          this.onDismiss();
        })

      Column({ space: 14 }) {
        Row() {
          Column({ space: 3 }) {
            Text(this.showTranslatedTitle() ? this.translatedTitle() : this.tag.fullTag)
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(themePrimaryText())
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            if (this.showTranslatedTitle()) {
              Text(this.tag.fullTag)
                .fontSize(13)
                .fontColor(themeSecondaryText())
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
          }
          .layoutWeight(1)

          Button({ type: ButtonType.Normal, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([themeSecondaryText()])
          }
          .width(34)
          .height(34)
          .padding(0)
          .borderRadius(17)
          .backgroundColor(themeSurfaceVariant())
          .onClick(() => {
            this.onDismiss();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Row({ space: 10 }) {
          TagVoteWideButton({
            symbolIcon: $r('sys.symbol.arrow_up_circle'),
            label: 'Vote+',
            enabledValue: this.tag.id > 0,
            selected: this.tag.voteUpEd === true,
            accentColor: '#0A8F5A',
            selectedBackground: '#E8F6EF',
            onClickAction: () => {
              this.onVote(1);
            }
          })
          .layoutWeight(1)
          TagVoteWideButton({
            symbolIcon: $r('sys.symbol.arrow_down_circle'),
            label: 'Vote-',
            enabledValue: this.tag.id > 0,
            selected: this.tag.voteDownEd === true,
            accentColor: '#C43C3C',
            selectedBackground: '#FDECEC',
            onClickAction: () => {
              this.onVote(-1);
            }
          })
          .layoutWeight(1)
        }
        .width('100%')

        TagActionButton({
          label: 'Show Tagged Galleries',
          symbolIcon: $r('sys.symbol.square_grid_2x2'),
          onTap: this.onShowTaggedGalleries
        })
        TagActionButton({
          label: 'Show Tag Definition',
          symbolIcon: $r('sys.symbol.book'),
          onTap: this.onShowTagDefinition
        })
      }
      .width('86%')
      .constraintSize({ maxWidth: 440 })
      .padding(16)
      .backgroundColor(themeSurface())
      .borderRadius(8)
      .shadow({ radius: 18, color: themeShadowColor(), offsetX: 0, offsetY: 4 })
      .transition(TransitionEffect.OPACITY
        .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
        .animation({ duration: 180, curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct TagVoteWideButton {
  symbolIcon: Resource = $r('sys.symbol.arrow_up_circle');
  label: string = '';
  enabledValue: boolean = false;
  selected: boolean = false;
  accentColor: string = '#0A8F5A';
  selectedBackground: string = '#E8F6EF';
  onClickAction: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 8 }) {
        SymbolGlyph(this.symbolIcon)
          .fontSize(22)
          .fontColor([this.enabledValue ? this.accentColor : themeInactiveActionText()])
        Text(this.label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.enabledValue ? themePrimaryText() : themeInactiveActionText())
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .width('100%')
    }
    .width('100%')
    .height(44)
    .padding(0)
    .backgroundColor(this.selected ? this.selectedBackground : themeSurfaceVariant())
    .border({
      width: this.selected ? 1.2 : 0,
      color: this.selected ? this.accentColor : Color.Transparent
    })
    .borderRadius(6)
    .enabled(this.enabledValue)
    .opacity(this.enabledValue ? 1 : 0.56)
    .onClick(() => {
      this.onClickAction();
    })
  }
}

@Component
struct TagActionButton {
  label: string = '';
  symbolIcon: Resource = $r('sys.symbol.square_grid_2x2');
  onTap: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 8 }) {
        SymbolGlyph(this.symbolIcon)
          .fontSize(18)
          .fontColor([themeSecondaryText()])
        Text(uiText(this.label))
          .fontSize(14)
          .fontColor(themePrimaryText())
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(40)
    .padding({ left: 10, right: 10 })
    .backgroundColor(themeSurfaceVariant())
    .borderRadius(6)
    .onClick(() => {
      this.onTap();
    })
  }
}

function createEmptyTagInfo(): GalleryTagInfo {
  return { id: 0, namespace: '', tag: '', fullTag: '' };
}

function cloneTagInfo(info: GalleryTagInfo): GalleryTagInfo {
  return {
    id: info.id,
    namespace: info.namespace,
    tag: info.tag,
    fullTag: info.fullTag,
    voteUpEd: info.voteUpEd,
    voteDownEd: info.voteDownEd
  };
}

function translatedTagLabel(info: GalleryTagInfo): string {
  if (!shouldUseChineseUi()) {
    return '';
  }
  const translated = ehTagTranslationStore.translate(info.namespace, info.tag);
  return translated.length > 0 ? translated : '';
}

@Component
struct ArchiveOptionsOverlay {
  @Prop mode: string = '';
  @Prop statusText: string = '';
  @Prop busy: boolean = false;
  @Prop archiverInfo: ArchiverInfo = { funds: '', options: [] };
  @Prop hathArchiveList: HathArchiveList = { formParamOr: '', options: [] };
  onDismiss: () => void = () => {};
  onSelectArchiverOption: (option: ArchiverOption) => void = (_option: ArchiverOption) => {};
  onSelectHathOption: (option: ArchiveOption) => void = (_option: ArchiveOption) => {};

  private title(): string {
    return this.mode === 'hath' ? 'H@H' : uiText('Archive');
  }

  private emptyText(): string {
    if (this.busy) {
      return uiText('Loading...');
    }
    return this.mode === 'hath' ? uiText('No H@H archives') : uiText('No archiver options');
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {}
        .width('100%')
        .height('100%')
        .backgroundColor(themeScrimColor())
        .onClick(() => {
          if (!this.busy) {
            this.onDismiss();
          }
        })

      Column({ space: 0 }) {
        Row() {
          Text(this.title())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
          Button(uiText('Cancel'))
            .type(ButtonType.Normal)
            .height(34)
            .fontSize(13)
            .fontColor(themeSecondaryText())
            .backgroundColor(themeSurfaceVariant())
            .borderRadius(6)
            .onClick(() => {
              if (!this.busy) {
                this.onDismiss();
              }
            })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 16, bottom: 12 })

        if (this.statusText.length > 0 || this.archiverInfo.funds.length > 0) {
          Text(this.statusText.length > 0 ? uiText(this.statusText) : this.archiverInfo.funds)
            .fontSize(13)
            .fontColor(themeSecondaryText())
            .width('100%')
            .padding({ left: 18, right: 18, bottom: 10 })
        }

        Divider().height(1).color(themeDividerColor())

        Scroll() {
          Column({ space: 0 }) {
            if (this.mode === 'hath') {
              if (this.hathArchiveList.options.length === 0) {
                ArchiveEmptyRow({ text: this.emptyText() })
              }
              ForEach(this.hathArchiveList.options, (option: ArchiveOption) => {
                ArchiveOptionRow({
                  title: option.label,
                  subtitle: option.value,
                  busy: this.busy,
                  onTap: () => {
                    this.onSelectHathOption(option);
                  }
                })
              }, (option: ArchiveOption) => option.value + ':' + option.label)
            } else {
              if (this.archiverInfo.options.length === 0) {
                ArchiveEmptyRow({ text: this.emptyText() })
              }
              ForEach(this.archiverInfo.options, (option: ArchiverOption) => {
                ArchiveOptionRow({
                  title: uiText(option.label),
                  subtitle: option.cost.length > 0 || option.size.length > 0 ?
                    option.cost + (option.cost.length > 0 && option.size.length > 0 ? ' / ' : '') + option.size :
                    option.url,
                  busy: this.busy,
                  onTap: () => {
                    this.onSelectArchiverOption(option);
                  }
                })
              }, (option: ArchiverOption) => option.kind + ':' + option.url)
            }
          }
        }
        .width('100%')
        .constraintSize({ maxHeight: 360 })
      }
      .width('100%')
      .constraintSize({ maxWidth: 520 })
      .backgroundColor(themeSurface())
      .borderRadius({ topLeft: 12, topRight: 12 })
      .clip(true)
      .transition(TransitionEffect.move(TransitionEdge.BOTTOM).animation({ duration: 220, curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct ArchiveOptionRow {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop busy: boolean = false;
  onTap: () => void = () => {};

  build() {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text(this.title)
            .fontSize(15)
            .fontColor(this.busy ? themeSecondaryText() : themePrimaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.subtitle.length > 0) {
            Text(this.subtitle)
              .fontSize(12)
              .fontColor(themeSecondaryText())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_forward'))
          .fontSize(18)
          .fontColor([themeSecondaryText()])
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12, bottom: 12 })
      Divider().height(1).color(themeDividerColor()).margin({ left: 18 })
    }
    .width('100%')
    .backgroundColor(themeSurface())
    .onClick(() => {
      if (!this.busy) {
        this.onTap();
      }
    })
  }
}

@Component
struct ArchiveEmptyRow {
  @Prop text: string = '';

  build() {
    Text(this.text)
      .fontSize(14)
      .fontColor(themeSecondaryText())
      .width('100%')
      .padding(24)
      .textAlign(TextAlign.Center)
  }
}
