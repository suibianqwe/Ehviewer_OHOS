import { GalleryCategory, GalleryInfo } from '../model/GalleryModels';
import { ehHistoryStore } from '../services/EhHistoryStore';
import {
  cacheThumbnailImage,
  categoryColor,
  categoryName,
  createEmptyGallery,
  gallerySimpleLanguage,
  galleryDisplayTitle,
  galleryListMode,
  galleryThumbHeight,
  galleryThumbWidth,
  GALLERY_TITLE_REVISION_KEY,
  HISTORY_READ_REVISION_KEY,
  readerLocalImageSource,
  showGalleryPages,
  uiText
} from '../shared/EhShared';
import {
  themePlaceholderColor,
  themePrimaryText,
  themeSecondaryText,
  themeSelectedBackground,
  themeSelectedIndicatorColor,
  themeSurface,
  themeSurfaceVariant,
  themeTertiaryText
} from '../shared/EhTheme';

@Component
@Reusable
export struct GalleryListRow {
  @Prop gallery: GalleryInfo = createEmptyGallery();
  @Prop selected: boolean = false;
  onLongPress: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  @StorageProp(HISTORY_READ_REVISION_KEY) historyReadRevision: number = 0;
  @StorageProp(GALLERY_TITLE_REVISION_KEY) galleryTitleRevision: number = 0;

  private cardHeight(): number {
    return galleryThumbHeight();
  }

  private cardGap(): number {
    return 6;
  }

  private metaGap(): number {
    return 2;
  }

  private metaTopGap(): number {
    return galleryListMode() === 'Extended' ? 8 : this.metaGap();
  }

  private titleMaxLines(): number {
    return galleryListMode() === 'Extended' ? 2 : 3;
  }

  private titleHeight(): number {
    return galleryListMode() === 'Extended' ? 38 : 56;
  }

  private uploaderTopGap(): number {
    return galleryListMode() === 'Extended' ? 1 : 3;
  }

  private hasTags(): boolean {
    return galleryListMode() === 'Extended' && this.previewTags().length > 0;
  }

  private previewTags(): string[] {
    if (this.gallery.simpleTags === undefined) {
      return [];
    }
    const tags: string[] = [];
    for (let i = 0; i < this.gallery.simpleTags.length; i++) {
      const normalized = this.gallery.simpleTags[i].toLowerCase();
      if (normalized.indexOf('language:') !== 0) {
        tags.push(this.gallery.simpleTags[i]);
      }
      if (tags.length >= 6) {
        break;
      }
    }
    return tags;
  }

  private readPageText(): string {
    if (this.historyReadRevision < 0) {
      return '';
    }
    if (this.gallery.pages <= 0) {
      return '';
    }
    const readIndex = ehHistoryStore.getReadPage(this.gallery.gid);
    const readPages = readIndex >= 0 ? Math.min(this.gallery.pages, readIndex + 1) : 0;
    return readPages.toString() + '/' + this.gallery.pages.toString() + ' P';
  }

  private showReadPageText(): boolean {
    return showGalleryPages() && this.gallery.pages > 0;
  }

  private languageText(): string {
    const language = gallerySimpleLanguage(this.gallery);
    return language.length > 0 ? language : '-';
  }

  private tagColor(index: number): string {
    const colors: string[] = ['#D8EEF7', '#E6E0F4', '#DDEFD9', '#F7E3C7', '#F6DDE7', '#DDE7F5'];
    return colors[index % colors.length];
  }

  private tagTextColor(index: number): string {
    const colors: string[] = ['#205E78', '#594596', '#2F6841', '#8A5A1F', '#8A3858', '#3A567D'];
    return colors[index % colors.length];
  }

  private tagDisplayText(tag: string): string {
    const colon = tag.indexOf(':');
    if (colon >= 0 && colon < tag.length - 1) {
      return tag.substring(colon + 1);
    }
    return tag;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
        GalleryThumb({
          url: this.gallery.thumb === undefined ? '' : this.gallery.thumb,
          widthValue: galleryThumbWidth(),
          heightValue: this.cardHeight(),
          radiusValue: 6
        })
          .height('100%')

        Column() {
        Column() {
          Column() {
            Text(galleryDisplayTitle(this.gallery))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(themePrimaryText())
              .maxLines(this.titleMaxLines())
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .width('100%')
          .height(this.titleHeight())
          .clip(true)
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.Start)

          Text(this.gallery.uploader === undefined || this.gallery.uploader.length === 0 ? uiText('unknown uploader') :
            this.gallery.uploader)
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: this.uploaderTopGap() })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row() {
          Column() {
            Row() {
              Text(this.languageText())
                .fontSize(13)
                .fontColor(themeSecondaryText())
                .fontWeight(FontWeight.Medium)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (this.showReadPageText()) {
                Text(this.readPageText())
                  .fontSize(13)
                  .fontColor(themeSecondaryText())
                  .fontWeight(FontWeight.Medium)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ left: 8 })
              }
            }
            .width('100%')

            Text(this.gallery.posted === undefined ? '' : this.gallery.posted)
              .fontSize(13)
              .fontColor(themeTertiaryText())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: this.metaGap() })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column() {
            Rating({ rating: this.gallery.rating, indicator: true })
              .stars(5)
              .stepSize(0.5)
              .height(14)
              .width(74)
            CategoryBadge({ category: this.gallery.category })
              .margin({ top: 1 })
          }
          .alignItems(HorizontalAlign.End)
          .margin({ left: 8 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
        .margin({ top: this.metaTopGap() })

        if (this.hasTags()) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.previewTags(), (tag: string, index: number) => {
              GalleryTagChip({
                text: this.tagDisplayText(tag),
                backgroundColorValue: this.tagColor(index),
                color: this.tagTextColor(index)
              })
                .margin({ right: 4 })
            }, (tag: string, index: number) => tag + ':' + index.toString())
          }
          .width('100%')
          .height(21)
          .clip(true)
          .margin({ top: this.metaGap() })
        }
        }
        .height('100%')
        .layoutWeight(1)
        .padding({ left: 10, right: 8, top: this.cardGap(), bottom: this.cardGap() })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')

      if (this.selected) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(24)
          .fontColor([themeSelectedIndicatorColor()])
          .margin({ top: 6, left: 6 })
      }
    }
    .width('100%')
    .height(this.cardHeight())
    .backgroundColor(this.selected ? themeSelectedBackground() : themeSurface())
    .borderRadius(6)
    .clip(true)
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.onLongPress(this.gallery);
        })
    )
  }
}

@Component
export struct GalleryTagChip {
  @Prop text: string = '';
  @Prop backgroundColorValue: string = '#D8EEF7';
  @Prop color: string = '#205E78';

  build() {
    Text(this.text)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.color)
      .height(21)
      .padding({ left: 7, right: 7 })
      .backgroundColor(this.backgroundColorValue)
      .borderRadius(3)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }
}

@Component
export struct GalleryThumb {
  @Prop @Watch('onUrlChange') url: string = '';
  widthValue: number = 86;
  heightValue: number = 118;
  radiusValue: number = 4;

  @State localUrl: string = '';
  @State loadFailed: boolean = false;
  private cachedUrl: string = '';

  aboutToAppear(): void {
    if (this.url.length > 0) {
      this.cacheThumb();
    } else {
      this.loadFailed = true;
    }
  }

  onUrlChange(): void {
    if (this.url.length > 0) {
      this.cacheThumb();
    } else {
      this.cachedUrl = '';
      this.localUrl = '';
      this.loadFailed = true;
    }
  }

  private cacheThumb(): void {
    if (this.cachedUrl === this.url && (this.localUrl.length > 0 || this.loadFailed)) {
      return;
    }
    this.cachedUrl = this.url;
    this.localUrl = '';
    this.loadFailed = false;
    cacheThumbnailImage(this.url, (path: string) => {
      if (this.cachedUrl !== this.url) {
        return;
      }
      this.localUrl = readerLocalImageSource(path);
      this.loadFailed = false;
    }, () => {
      if (this.cachedUrl !== this.url) {
        return;
      }
      this.localUrl = '';
      this.loadFailed = true;
    });
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(themeSurfaceVariant())
        .borderRadius(this.radiusValue)

      if (this.loadFailed) {
        Column({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(22)
            .fontColor([themePlaceholderColor()])
          Text('EH')
            .fontSize(10)
            .fontColor(themePlaceholderColor())
        }
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.url.length > 0) {
            this.cachedUrl = '';
            this.cacheThumb();
          }
        })
      } else if (this.localUrl.length > 0) {
        Image(this.localUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .syncLoad(false)
          .borderRadius(this.radiusValue)
          .onError(() => {
            this.loadFailed = true;
          })
      } else {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(themePlaceholderColor())
      }
    }
    .width(this.widthValue > 0 ? this.widthValue : '100%')
    .height(this.heightValue > 0 ? this.heightValue : '100%')
  }
}

@Component
@Reusable
export struct GalleryThumbCard {
  @Prop gallery: GalleryInfo = createEmptyGallery();
  @Prop selected: boolean = false;
  onLongPress: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  @StorageProp(HISTORY_READ_REVISION_KEY) historyReadRevision: number = 0;
  @StorageProp(GALLERY_TITLE_REVISION_KEY) galleryTitleRevision: number = 0;

  private readPageText(): string {
    if (this.historyReadRevision < 0) {
      return '';
    }
    if (this.gallery.pages <= 0) {
      return '';
    }
    const readIndex = ehHistoryStore.getReadPage(this.gallery.gid);
    const readPages = readIndex >= 0 ? Math.min(this.gallery.pages, readIndex + 1) : 0;
    return readPages.toString() + '/' + this.gallery.pages.toString() + ' P';
  }

  private showReadPageText(): boolean {
    return showGalleryPages() && this.gallery.pages > 0;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        GalleryThumb({
          url: this.gallery.thumb === undefined ? '' : this.gallery.thumb,
          widthValue: 0,
          heightValue: 0
        })
          .width('100%')
          .aspectRatio(0.75)

        Column() {
          Column() {
            Text(galleryDisplayTitle(this.gallery))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(themePrimaryText())
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .width('100%')
          .height(32)
          .clip(true)
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.Start)

          Row() {
            CategoryBadge({ category: this.gallery.category })
            Blank()
            if (this.showReadPageText()) {
              Text(this.readPageText())
                .fontSize(11)
                .fontColor(themeTertiaryText())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .width('100%')
          .margin({ top: 4 })
        }
        .padding({ left: 6, right: 6, top: 6, bottom: 6 })
        .alignItems(HorizontalAlign.Start)
      }

      if (this.selected) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(24)
          .fontColor([themeSelectedIndicatorColor()])
          .margin({ top: 6, left: 6 })
      }
    }
    .backgroundColor(this.selected ? themeSelectedBackground() : themeSurface())
    .borderRadius(6)
    .clip(true)
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.onLongPress(this.gallery);
        })
    )
  }
}

@Component
export struct CategoryBadge {
  @Prop category: number = GalleryCategory.Unknown;

  build() {
    Text(categoryName(this.category))
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .height(21)
      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      .backgroundColor(categoryColor(this.category))
      .borderRadius(3)
  }
}
