import { GalleryDetail } from '../../model/GalleryModels';
import {
  createEmptyDetail,
  uiText
} from '../../shared/EhShared';
import {
  themeFavoriteText,
  themeInactiveActionText,
  themeOnPrimaryText,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSurface,
  themeSurfaceVariant,
  themeTransparentColor
} from '../../shared/EhTheme';
@Component
export struct DetailActions {
  @Prop detail: GalleryDetail = createEmptyDetail();
  @Prop isDetailLoaded: boolean = false;
  @Prop isFavorited: boolean = false;
  onFavorite: () => void = () => {};
  onShare: () => void = () => {};
  onRate: () => void = () => {};
  onTorrent: () => void = () => {};
  onArchive: () => void = () => {};

  build() {
    Column() {
      Scroll() {
        Row() {
          DetailActionItem({
            symbolIcon: this.isFavorited ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
            label: this.isFavorited ? uiText('Favorited') : uiText('Favorite'),
            isActive: this.detail.gid > 0,
            isFilled: this.isFavorited,
            onTap: this.onFavorite
          })
          DetailActionItem({
            symbolIcon: $r('sys.symbol.star'),
            label: uiText('Rate'),
            isActive: this.isDetailLoaded && this.detail.apiUid >= 0 && this.detail.apiKey.length > 0,
            isFilled: this.detail.rated,
            onTap: this.onRate
          })
          DetailActionItem({
            symbolIcon: $r('sys.symbol.share'),
            label: uiText('Share'),
            isActive: this.detail.gid > 0,
            onTap: this.onShare
          })
          DetailActionItem({
            symbolIcon: $r('sys.symbol.save'),
            label: this.isDetailLoaded && this.detail.torrentCount > 0 ?
              'Torrent (' + this.detail.torrentCount.toString() + ')' : 'Torrent',
            isActive: this.isDetailLoaded && this.detail.torrentCount > 0 && this.detail.torrentUrl.length > 0,
            onTap: this.onTorrent
          })
          DetailActionItem({
            symbolIcon: $r('sys.symbol.doc_plaintext'),
            label: uiText('Archive'),
            isActive: this.isDetailLoaded && this.detail.archiveUrl.length > 0,
            onTap: this.onArchive
          })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      RatingSummary({
        rating: this.detail.rating,
        ratingCount: this.detail.ratingCount,
        isDetailLoaded: this.isDetailLoaded
      })
        .margin({ top: 8 })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .backgroundColor(themeSurface())
  }
}

@Component
export struct RatingSummary {
  @Prop rating: number = -1;
  @Prop ratingCount: number = 0;
  @Prop isDetailLoaded: boolean = false;

  private ratingLabel(): string {
    if (this.rating < 0) {
      return '-';
    }
    return this.rating.toString() + ' / 5';
  }

  build() {
    Column() {
      Text(this.isDetailLoaded ? this.ratingLabel() + '  (' + this.ratingCount.toString() + ')' : uiText('Loading rating...'))
        .fontSize(13)
        .fontColor(themeSecondaryText())
      Row({ space: 2 }) {
        ForEach([0, 1, 2, 3, 4], (index: number) => {
          SymbolGlyph($r('sys.symbol.star_fill'))
            .fontSize(16)
            .fontColor([this.rating >= index + 1 ? '#F7C948' : '#D0D5DD'])
        }, (index: number) => index.toString())
      }
      .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}

@Component
export struct RatingPanel {
  @Prop rating: number = 5;
  onChange: (rating: number) => void = (_rating: number) => {};
  onCancel: () => void = () => {};
  onSubmit: () => void = () => {};

  build() {
    Column() {
      Text(uiText('Rate'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(themePrimaryText())
        .width('100%')
      Text(this.rating.toString() + ' / 5')
        .fontSize(13)
        .fontColor(themeSecondaryText())
        .width('100%')
        .margin({ top: 4, bottom: 14 })
      Row({ space: 8 }) {
        ForEach([1, 2, 3, 4, 5], (value: number) => {
          SymbolGlyph($r('sys.symbol.star_fill'))
            .fontSize(32)
            .fontColor([this.rating >= value ? '#F7C948' : '#D0D5DD'])
            .onClick(() => {
              this.onChange(value);
            })
        }, (value: number) => value.toString())
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Row({ space: 10 }) {
        Button(uiText('Cancel'))
          .type(ButtonType.Normal)
          .height(38)
          .fontSize(13)
          .fontColor(themeSecondaryText())
          .backgroundColor(themeSurfaceVariant())
          .borderRadius(4)
          .layoutWeight(1)
          .onClick(() => {
            this.onCancel();
          })
        Button(uiText('Submit'))
          .type(ButtonType.Normal)
          .height(38)
          .fontSize(13)
          .fontColor(themeOnPrimaryText())
          .backgroundColor(themePrimaryColor())
          .borderRadius(4)
          .layoutWeight(1)
          .onClick(() => {
            this.onSubmit();
          })
      }
      .width('100%')
      .margin({ top: 18 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor(themeSurface())
    .borderRadius(8)
  }
}

@Component
export struct DetailActionItem {
  @Prop symbolIcon: Resource = $r('sys.symbol.heart');
  @Prop label: string = '';
  @Prop isActive: boolean = true;
  @Prop isFilled: boolean = false;
  onTap: () => void = () => {};
  @State pressed: boolean = false;

  build() {
    Column({ space: 6 }) {
      SymbolGlyph(this.symbolIcon)
        .fontSize(26)
        .fontColor([this.isActive ? (this.isFilled ? themeFavoriteText() : themePrimaryColor()) :
          themeInactiveActionText()])
      Text(this.label)
        .fontSize(11)
        .fontColor(this.isActive ? themePrimaryColor() : themeInactiveActionText())
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(72)
    .height(68)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.pressed ? themeSurfaceVariant() : themeTransparentColor())
    .borderRadius(6)
    .scale({ x: this.pressed ? 0.92 : 1, y: this.pressed ? 0.92 : 1 })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (!this.isActive) {
        return;
      }
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      if (this.isActive) {
        this.onTap();
      }
    })
  }
}

