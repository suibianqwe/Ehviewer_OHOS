import { GalleryComment } from '../../../model/GalleryModels';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { CommentComposer } from '../../detail/CommentComposer';
import {
  TRANSLATION_ENABLED_KEY,
  ehTranslationService
} from '../../../services/EhTranslationService';
import { TRANSLATION_BUTTONS_VISIBLE_KEY } from '../../../services/EhSettingsStore';
import { nextFloatingToolbarOffset, uiText } from '../../../shared/EhShared';
import { ArrayDataSource } from '../../../shared/ListDataSource';
import { buildCommentListItems, CommentListItem } from '../../../services/CommentListSupport';
import {
  themeDividerColor,
  themePageBackground,
  themePrimaryText,
  themeSecondaryText,
  themeSurface
} from '../../../shared/EhTheme';
import { EhSubNavBar } from '../../NavigationComponents';
import { MAIN_CONTENT_WIDTH_VP_KEY } from '../../../services/EhWindowImmersive';
import { uiAdaptiveToolbarHeight, uiSearchFieldHeight } from '../../../shared/EhUiStyle';
import { GalleryCommentRow } from '../../detail/CommentComponents';
import { TranslationText } from '../../TranslationComponents';
import {
  COMMENT_BLACKLIST_REVISION_KEY,
  ehCommentBlacklistStore
} from '../../../services/EhCommentBlacklistStore';

@Component
export struct CommentsScene {
  @StorageProp(COMMENT_BLACKLIST_REVISION_KEY) @Watch('refreshVisibleComments') blacklistRevision: number = 0;
  @Prop renderVersion: number = 0;
  @Prop @Watch('refreshVisibleComments') comments: GalleryComment[] = [];
  @Prop galleryTitle: string = '';
  @Prop commentDraft: string = '';
  @Prop commentPosting: boolean = false;
  @Prop commentPostStatus: string = '';
  onCommentDraftChange: (value: string) => void = (_value: string) => {};
  onPostComment: () => void = () => {};
  onBack: () => void = () => {};
  onVoteComment: (comment: GalleryComment, vote: number) => void = (_comment: GalleryComment, _vote: number) => {};
  onOpenGalleryLink: (url: string) => void = (_url: string) => {};
  @StorageProp('statusBarHeight') statusBarHeightPx: number = 0;
  @StorageLink(TRANSLATION_ENABLED_KEY) translationEnabled: boolean = false;
  @StorageProp(TRANSLATION_BUTTONS_VISIBLE_KEY) translationButtonsVisible: boolean = true;
  @State visibleCommentItems: GalleryComment[] = [];
  @State toolbarOffsetY: number = 0;
  @State composerHeight: number = uiSearchFieldHeight() + 18;
  @StorageProp(MAIN_CONTENT_WIDTH_VP_KEY) contentWidth: number = 360;
  private commentsScroller: Scroller = new Scroller();
  private commentItems: CommentListItem[] = [];
  private commentsSource: ArrayDataSource<CommentListItem> = new ArrayDataSource<CommentListItem>([]);
  private toolbarRestoring: boolean = false;
  private toolbarRestoreTimer: number = -1;
  private previousKeyboardAvoidMode: KeyboardAvoidMode | null = null;

  aboutToAppear(): void {
    this.refreshVisibleComments();
    try {
      this.previousKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode();
      // Comments contains a List and an auto-growing TextArea. RESIZE only
      // reacts to the first keyboard presentation; the caret-aware mode keeps
      // later line changes visible without repeatedly rebuilding the input
      // hierarchy (API 14+, compatible SDK 20).
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
    } catch (_error) {
      this.previousKeyboardAvoidMode = null;
    }
  }

  aboutToDisappear(): void {
    if (this.toolbarRestoreTimer >= 0) {
      clearTimeout(this.toolbarRestoreTimer);
      this.toolbarRestoreTimer = -1;
    }
    if (this.previousKeyboardAvoidMode !== null) {
      try {
        this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardAvoidMode);
      } catch (_error) {
      }
    }
  }

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  private totalBarHeight(): number {
    return this.statusBarVp() + uiAdaptiveToolbarHeight(this.contentWidth);
  }

  private visibleBarHeight(): number {
    return Math.max(0, Math.min(this.totalBarHeight(), this.totalBarHeight() + this.toolbarOffsetY));
  }

  private handleScrollFrame(scrollOffset: number): number {
    const yOffset = Math.max(0, this.commentsScroller.currentOffset().yOffset);
    if (yOffset <= 4) {
      this.toolbarRestoring = false;
      this.toolbarOffsetY = 0;
      return scrollOffset;
    }
    if (scrollOffset > 0 && this.visibleBarHeight() > 0) {
      this.toolbarRestoring = false;
      this.toolbarOffsetY = nextFloatingToolbarOffset(this.toolbarOffsetY, scrollOffset, yOffset,
        this.totalBarHeight());
      return scrollOffset;
    }
    if (scrollOffset < 0 && this.toolbarOffsetY < 0) {
      this.restoreToolbarOnReverseScroll();
    }
    return scrollOffset;
  }

  private restoreToolbarOnReverseScroll(): void {
    if (this.toolbarRestoring) {
      return;
    }
    this.toolbarRestoring = true;
    this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseOut }, () => {
      this.toolbarOffsetY = 0;
    });
    if (this.toolbarRestoreTimer >= 0) {
      clearTimeout(this.toolbarRestoreTimer);
    }
    this.toolbarRestoreTimer = setTimeout(() => {
      this.toolbarRestoring = false;
      this.toolbarRestoreTimer = -1;
    }, 280);
  }

  private refreshVisibleComments(): void {
    this.visibleCommentItems = ehCommentBlacklistStore.filterComments(this.comments);
    this.commentItems = buildCommentListItems(this.visibleCommentItems, this.commentItems);
    this.commentsSource.setItems(this.commentItems);
  }

  private updateComposerHeight(height: number): void {
    if (Number.isFinite(height) && height > 0 && Math.abs(height - this.composerHeight) > 0.5) {
      this.composerHeight = height;
    }
  }

  @Builder
  private commentsContent() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.visibleCommentItems.length === 0) {
        Column() {
          PlaceholderScene({
            title: uiText('Comments'),
            detail: uiText('No comments')
          })
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.totalBarHeight() })
      } else {
        List({ space: 0, scroller: this.commentsScroller }) {
          ListItem() {
            Row() {
              TranslationText({
                sourceText: this.galleryTitle,
                translationEnabled: this.translationEnabled,
                fontSizeValue: 12,
                lineHeightValue: 18,
                fontColorValue: themeSecondaryText(),
                maxLinesValue: 1
              })
                .layoutWeight(1)
              Text(this.visibleCommentItems.length.toString() + ' ' + uiText('total'))
                .fontSize(12)
                .fontColor(themeSecondaryText())
                .margin({ left: 12 })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor(themeSurface())
          }
          .reuseId('comments-summary')

          LazyForEach(this.commentsSource, (item: CommentListItem) => {
            ListItem() {
              GalleryCommentRow({
                comment: item.comment,
                maxLines: 1000,
                compact: false,
                openGalleryLinksInApp: true,
                translateComment: this.translationEnabled,
                prioritizeVisibleTranslation: true,
                onVoteComment: this.onVoteComment,
                onOpenGalleryLink: this.onOpenGalleryLink,
                onBlockUser: () => {
                  this.refreshVisibleComments();
                }
              })
            }
            .reuseId('comment-row')
          }, (item: CommentListItem) => item.key)
          ListItem() {
            Divider()
              .height(1)
              .color(themeDividerColor())
          }
          .reuseId('comment-divider')
        }
        .divider({ strokeWidth: 1, color: themeDividerColor() })
        .width('100%')
        .height('100%')
        .contentStartOffset(this.totalBarHeight())
        .contentEndOffset(this.composerHeight)
        .scrollBar(BarState.Auto)
        .cachedCount(4)
        .onScrollFrameBegin((offset: number, _state: ScrollState) => {
          return { offsetRemain: this.handleScrollFrame(offset) };
        })
      }

      EhSubNavBar({
        statusBarHeight: this.statusBarVp(),
        title: uiText('Comments'),
        showAction: this.translationButtonsVisible,
        actionChecked: this.translationEnabled,
        actionIcon: $r('sys.symbol.translate'),
        translateY: this.toolbarOffsetY,
        onBack: this.onBack,
        onAction: () => {
          ehTranslationService.setEnabled(!this.translationEnabled);
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      this.commentsContent()
      // Let list content pass behind the field so its blur samples comments,
      // not an opaque footer. The end inset keeps the last comment reachable.
      CommentComposer({
        draft: this.commentDraft,
        posting: this.commentPosting,
        status: this.commentPostStatus,
        onDraftChange: this.onCommentDraftChange,
        onPost: this.onPostComment
      })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.updateComposerHeight(Number.parseFloat(newArea.height.toString()));
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
    .clip(true)
  }
}



@Component
// Reader auxiliary scenes share this placeholder from several hosts.
// eslint-disable-next-line @performance/avoid-overusing-custom-component-check
export struct PlaceholderScene {
  title: string = '';
  detail: string = '';

  build() {
    Column() {
      Text(this.title)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(themePrimaryText())
      Text(this.detail)
        .fontSize(14)
        .fontColor(themeSecondaryText())
        .lineHeight(22)
        .textAlign(TextAlign.Center)
        .margin({ top: 10 })
        .width('80%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
    .backgroundColor(themePageBackground())
  }
}
