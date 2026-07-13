import { GalleryComment } from '../../../model/GalleryModels';
import { TRANSLATION_ENABLED_KEY, ehTranslationService } from '../../../services/EhTranslationService';
import { TRANSLATION_BUTTONS_VISIBLE_KEY } from '../../../services/EhSettingsStore';
import { uiText } from '../../../shared/EhShared';
import {
  themeDividerColor,
  themePageBackground,
  themePrimaryText,
  themeSecondaryText,
  themeSurface
} from '../../../shared/EhTheme';
import { EhSubNavBar } from '../../NavigationComponents';
import { GalleryCommentRow } from '../../detail/CommentComponents';
import { TranslationText } from '../../TranslationComponents';

@Component
export struct CommentsScene {
  @Prop renderVersion: number = 0;
  @Prop comments: GalleryComment[] = [];
  @Prop galleryTitle: string = '';
  onBack: () => void = () => {};
  onVoteComment: (comment: GalleryComment, vote: number) => void = (_comment: GalleryComment, _vote: number) => {};
  onOpenGalleryLink: (url: string) => void = (_url: string) => {};
  @StorageProp('statusBarHeight') statusBarHeightPx: number = 0;
  @StorageLink(TRANSLATION_ENABLED_KEY) translationEnabled: boolean = false;
  @StorageProp(TRANSLATION_BUTTONS_VISIBLE_KEY) translationButtonsVisible: boolean = true;

  private statusBarVp(): number {
    return this.getUIContext().px2vp(this.statusBarHeightPx);
  }

  build() {
    Column() {
      EhSubNavBar({
        statusBarHeight: this.statusBarVp(),
        title: uiText('Comments'),
        showAction: this.translationButtonsVisible,
        actionChecked: this.translationEnabled,
        actionIcon: $r('sys.symbol.translate'),
        onBack: this.onBack,
        onAction: () => {
          ehTranslationService.setEnabled(!this.translationEnabled);
        }
      })
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
        Text(this.comments.length.toString() + ' ' + uiText('total'))
          .fontSize(12)
          .fontColor(themeSecondaryText())
          .margin({ left: 12 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(themeSurface())

      if (this.comments.length === 0) {
        PlaceholderScene({
          title: 'Comments',
          detail: 'No comments for this gallery.'
        })
      } else {
        List({ space: 0 }) {
          ForEach(this.comments, (comment: GalleryComment) => {
            ListItem() {
              GalleryCommentRow({
                comment: comment,
                maxLines: 1000,
                compact: false,
                openGalleryLinksInApp: true,
                translateComment: this.translationEnabled,
                onVoteComment: this.onVoteComment,
                onOpenGalleryLink: this.onOpenGalleryLink
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
        .layoutWeight(1)
        .cachedCount(4)
      }
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
