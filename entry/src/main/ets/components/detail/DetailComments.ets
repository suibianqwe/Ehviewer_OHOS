import { GalleryComment } from '../../model/GalleryModels';
import { uiText } from '../../shared/EhShared';
import { themePrimaryColor, themePrimaryText, themeSecondaryText, themeSurface } from '../../shared/EhTheme';
import { GalleryCommentRow } from './CommentComponents';

@Component
export struct DetailComments {
  @Prop comments: GalleryComment[] = [];
  @Prop isDetailLoaded: boolean = false;
  onComments: () => void = () => {};
  onVoteComment: (comment: GalleryComment, vote: number) => void = (_comment: GalleryComment, _vote: number) => {};
  onOpenGalleryLink: (url: string) => void = (_url: string) => {};

  build() {
    Column() {
      Row() {
        Text(uiText('Comments'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .layoutWeight(1)
        if (!this.isDetailLoaded) {
          Text(uiText('Loading...'))
            .fontSize(13)
            .fontColor(themeSecondaryText())
        } else if (this.comments.length > 0) {
          Text(uiText('See all') + ' (' + this.comments.length.toString() + ')')
            .fontSize(13)
            .fontColor(themePrimaryColor())
            .onClick(() => {
              this.onComments();
            })
        } else {
          Text('0 ' + uiText('comments'))
            .fontSize(13)
            .fontColor(themeSecondaryText())
        }
      }
      .width('100%')
      .margin({ bottom: 10 })
      .onClick(() => {
        if (this.isDetailLoaded && this.comments.length > 0) {
          this.onComments();
        }
      })

      if (!this.isDetailLoaded) {
        Text(uiText('Loading comments...'))
          .fontSize(13)
          .fontColor(themeSecondaryText())
      } else if (this.comments.length === 0) {
        Text(uiText('No comments'))
          .fontSize(13)
          .fontColor(themeSecondaryText())
      } else {
        ForEach(this.comments.slice(0, 2), (comment: GalleryComment) => {
          GalleryCommentRow({
            comment: comment,
            maxLines: 4,
            compact: true,
            openGalleryLinksInApp: true,
            rowClickable: true,
            onVoteComment: this.onVoteComment,
            onOpenGalleryLink: this.onOpenGalleryLink,
            onTapRow: this.onComments
          })
            .margin({ bottom: 6 })
        }, (comment: GalleryComment) => comment.id)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(themeSurface())
  }
}
