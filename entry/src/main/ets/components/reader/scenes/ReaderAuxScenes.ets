import { GalleryComment } from '../../../model/GalleryModels';
import {
  TRANSLATION_ENABLED_KEY,
  ehTranslationService,
  translationPriorityForIndex
} from '../../../services/EhTranslationService';
import { TRANSLATION_BUTTONS_VISIBLE_KEY } from '../../../services/EhSettingsStore';
import { nextFloatingToolbarOffset, uiText } from '../../../shared/EhShared';
import {
  themeDividerColor,
  themePageBackground,
  themePrimaryText,
  themeSecondaryText,
  themeSurface
} from '../../../shared/EhTheme';
import { EhSubNavBar } from '../../NavigationComponents';
import { MAIN_CONTENT_WIDTH_VP_KEY } from '../../../services/EhWindowImmersive';
import { uiAdaptiveToolbarHeight } from '../../../shared/EhUiStyle';
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
  onBack: () => void = () => {};
  onVoteComment: (comment: GalleryComment, vote: number) => void = (_comment: GalleryComment, _vote: number) => {};
  onOpenGalleryLink: (url: string) => void = (_url: string) => {};
  @StorageProp('statusBarHeight') statusBarHeightPx: number = 0;
  @StorageLink(TRANSLATION_ENABLED_KEY) translationEnabled: boolean = false;
  @StorageProp(TRANSLATION_BUTTONS_VISIBLE_KEY) translationButtonsVisible: boolean = true;
  @State translationVisibleStart: number = -1;
  @State translationVisibleEnd: number = -1;
  @State visibleCommentItems: GalleryComment[] = [];
  @State toolbarOffsetY: number = 0;
  @StorageProp(MAIN_CONTENT_WIDTH_VP_KEY) contentWidth: number = 360;
  private commentsScroller: Scroller = new Scroller();
  private toolbarRestoring: boolean = false;

  aboutToAppear(): void {
    this.refreshVisibleComments();
  }

  private translationPriorityFor(index: number): number {
    if (!this.translationEnabled) {
      return 0;
    }
    return translationPriorityForIndex(index, this.translationVisibleStart, this.translationVisibleEnd);
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
      const previousOffsetY = this.toolbarOffsetY;
      this.toolbarRestoring = false;
      this.toolbarOffsetY = nextFloatingToolbarOffset(this.toolbarOffsetY, scrollOffset, yOffset,
        this.totalBarHeight());
      return Math.max(0, scrollOffset - Math.max(0, previousOffsetY - this.toolbarOffsetY));
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
    setTimeout(() => {
      this.toolbarRestoring = false;
    }, 280);
  }

  private refreshVisibleComments(): void {
    this.visibleCommentItems = ehCommentBlacklistStore.filterComments(this.comments);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.visibleCommentItems.length === 0) {
        Column() {
          PlaceholderScene({
            title: 'Comments',
            detail: 'No comments for this gallery.'
          })
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.visibleBarHeight() })
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

          ForEach(this.visibleCommentItems, (comment: GalleryComment, index: number) => {
            ListItem() {
              GalleryCommentRow({
                comment: comment,
                maxLines: 1000,
                compact: false,
                openGalleryLinksInApp: true,
                translateComment: this.translationEnabled,
                translationPriority: this.translationPriorityFor(index),
                onVoteComment: this.onVoteComment,
                onOpenGalleryLink: this.onOpenGalleryLink,
                onBlockUser: () => {
                  this.refreshVisibleComments();
                }
              })
            }
            .reuseId('comment-row')
          }, (comment: GalleryComment) => comment.id)
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
        .padding({ top: this.visibleBarHeight() })
        .cachedCount(4)
        .onScrollFrameBegin((offset: number, _state: ScrollState) => {
          return { offsetRemain: this.handleScrollFrame(offset) };
        })
        .onScrollIndex((first: number, last: number) => {
          this.translationVisibleStart = Math.max(0, first - 1);
          this.translationVisibleEnd = Math.min(Math.max(0, last - 1), this.visibleCommentItems.length - 1);
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
}



@Component
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
