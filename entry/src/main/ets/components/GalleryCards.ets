import { GalleryCategory, GalleryInfo } from '../model/GalleryModels';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehTagTranslationStore } from '../services/EhTagTranslationStore';
import {
  cacheThumbnailImage,
  categoryColor,
  categoryDisplayName,
  createEmptyGallery,
  galleryDetailCardBaseHeight,
  galleryDetailCardHeight,
  galleryDetailCardThumbWidth,
  gallerySimpleLanguage,
  galleryDisplayTitle,
  galleryListMode,
  GALLERY_TITLE_REVISION_KEY,
  HISTORY_READ_REVISION_KEY,
  LANGUAGE_REVISION_KEY,
  readerLocalImageSource,
  showGalleryLanguage,
  showGalleryPages,
  showGalleryRating,
  shouldShowTagTranslations,
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
import { TranslationText } from './TranslationComponents';

const GALLERY_THUMB_LOCAL_SOURCE_CACHE: Map<string, string> = new Map<string, string>();
const GALLERY_THUMB_ASPECT_RATIO_CACHE: Map<string, number> = new Map<string, number>();

interface GalleryImageCompleteEvent {
  width: number;
  height: number;
  componentWidth: number;
  componentHeight: number;
  loadingStatus: number;
}

function normalizedThumbnailAspectRatio(width: number, height: number): number {
  if (width <= 0 || height <= 0) {
    return 0.75;
  }
  const ratio = width / height;
  if (Number.isNaN(ratio) || ratio <= 0) {
    return 0.75;
  }
  return Math.max(0.3, Math.min(2.5, ratio));
}

export function galleryThumbnailAspectRatio(gallery: GalleryInfo): number {
  if (gallery.thumbWidth > 0 && gallery.thumbHeight > 0) {
    return normalizedThumbnailAspectRatio(gallery.thumbWidth, gallery.thumbHeight);
  }
  const thumbnailUrl = gallery.thumb === undefined ? '' : gallery.thumb;
  const cachedRatio = GALLERY_THUMB_ASPECT_RATIO_CACHE.get(thumbnailUrl);
  if (cachedRatio !== undefined) {
    return cachedRatio;
  }
  return 0.75;
}

@Component
@Reusable
export struct GalleryListRow {
  @Prop gallery: GalleryInfo = createEmptyGallery();
  @Prop selected: boolean = false;
  @Prop translateTitle: boolean = false;
  onLongPress: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  @StorageProp(HISTORY_READ_REVISION_KEY) historyReadRevision: number = 0;
  @StorageProp(GALLERY_TITLE_REVISION_KEY) galleryTitleRevision: number = 0;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  private cardHeight(): number {
    return galleryDetailCardHeight();
  }

  private detailAreaHeight(): number {
    return galleryDetailCardBaseHeight();
  }

  private cardGap(): number {
    return this.isLooseLayout() ? 8 : 6;
  }

  private metaGap(): number {
    return this.isLooseLayout() ? 4 : 2;
  }

  private titleMaxLines(): number {
    return this.isSmallThumb() ? 2 : 3;
  }

  private titleLineHeight(): number {
    if (this.isSmallThumb()) {
      return 18;
    }
    return this.isLooseLayout() ? 21 : 19;
  }

  private titleHeight(): number {
    return this.titleLineHeight() * this.titleMaxLines();
  }

  private isSmallThumb(): boolean {
    return galleryDetailCardThumbWidth() <= 70 || this.detailAreaHeight() <= 100;
  }

  private isLooseLayout(): boolean {
    return galleryDetailCardThumbWidth() >= 104;
  }

  private cardThumbWidth(): number {
    return galleryDetailCardThumbWidth();
  }

  private titleFontSize(): number {
    if (this.isSmallThumb()) {
      return 14;
    }
    return this.isLooseLayout() ? 17 : 15;
  }

  private uploaderFontSize(): number {
    if (this.isSmallThumb()) {
      return 11;
    }
    return this.isLooseLayout() ? 14 : 12;
  }

  private metaFontSize(): number {
    if (this.isSmallThumb()) {
      return 11;
    }
    return this.isLooseLayout() ? 14 : 13;
  }

  private metaLineHeight(): number {
    if (this.isSmallThumb()) {
      return 14;
    }
    return this.isLooseLayout() ? 20 : 16;
  }

  private ratingHeight(): number {
    if (this.isSmallThumb()) {
      return 14;
    }
    return this.isLooseLayout() ? 18 : 16;
  }

  private ratingWidth(): number {
    if (this.isSmallThumb()) {
      return 76;
    }
    return this.isLooseLayout() ? 96 : 86;
  }

  private categoryFontSize(): number {
    if (this.isSmallThumb()) {
      return 12;
    }
    return this.isLooseLayout() ? 14 : 13;
  }

  private categoryHeight(): number {
    if (this.isSmallThumb()) {
      return 21;
    }
    return this.isLooseLayout() ? 25 : 23;
  }

  private tagFontSize(): number {
    return this.isLooseLayout() ? 14 : 12;
  }

  private tagRowHeight(): number {
    return this.isLooseLayout() ? 25 : 21;
  }

  private isExtendedMode(): boolean {
    return galleryListMode() === 'Extended';
  }

  private previewTags(): string[] {
    const tags: string[] = [];
    if (this.gallery.simpleTags !== undefined) {
      for (let i = 0; i < this.gallery.simpleTags.length && tags.length < 8; i++) {
        this.appendPreviewTag(tags, this.gallery.simpleTags[i]);
      }
    }
    if (this.gallery.tagList !== undefined) {
      for (let i = 0; i < this.gallery.tagList.length && tags.length < 8; i++) {
        this.appendPreviewTag(tags, this.gallery.tagList[i]);
      }
    }
    if (this.gallery.detailTags !== undefined) {
      for (let i = 0; i < this.gallery.detailTags.length && tags.length < 8; i++) {
        const group = this.gallery.detailTags[i];
        for (let j = 0; j < group.tags.length && tags.length < 8; j++) {
          const value = group.namespace.length > 0 ? group.namespace + ':' + group.tags[j] : group.tags[j];
          this.appendPreviewTag(tags, value);
        }
      }
    }
    return tags;
  }

  private appendPreviewTag(tags: string[], value: string): void {
    const normalized = value.trim().toLowerCase();
    if (normalized.length === 0 || normalized.indexOf('language:') === 0) {
      return;
    }
    for (let i = 0; i < tags.length; i++) {
      if (tags[i].trim().toLowerCase() === normalized) {
        return;
      }
    }
    tags.push(value.trim());
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
    const namespace = colon > 0 ? tag.substring(0, colon).trim() : '';
    const value = colon >= 0 && colon < tag.length - 1 ? tag.substring(colon + 1).trim() : tag.trim();
    if (shouldShowTagTranslations()) {
      const translated = ehTagTranslationStore.translate(namespace, value);
      if (translated.length > 0) {
        return translated;
      }
    }
    return value;
  }

  @Builder
  private detailMetadata() {
    Row() {
      Column({ space: this.metaGap() }) {
        Text(this.gallery.uploader === undefined || this.gallery.uploader.length === 0 ?
          uiText('unknown uploader') : this.gallery.uploader)
          .fontSize(this.uploaderFontSize())
          .fontColor(themeSecondaryText())
          .lineHeight(this.metaLineHeight())
          .height(this.metaLineHeight())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row() {
          Text(this.languageText())
            .fontSize(this.metaFontSize())
            .fontColor(themeSecondaryText())
            .fontWeight(FontWeight.Medium)
            .lineHeight(this.metaLineHeight())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.showReadPageText()) {
            Text(this.readPageText())
              .fontSize(this.metaFontSize())
              .fontColor(themeSecondaryText())
              .fontWeight(FontWeight.Medium)
              .lineHeight(this.metaLineHeight())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: 8 })
          }
        }
        .width('100%')
        .height(this.metaLineHeight())

        Text(this.gallery.posted === undefined ? '' : this.gallery.posted)
          .fontSize(this.metaFontSize())
          .fontColor(themeTertiaryText())
          .lineHeight(this.metaLineHeight())
          .height(this.metaLineHeight())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column({ space: this.isLooseLayout() ? 6 : 4 }) {
        Rating({ rating: this.gallery.rating, indicator: true })
          .stars(5)
          .stepSize(0.5)
          .height(this.ratingHeight())
          .width(this.ratingWidth())
        CategoryBadge({
          category: this.gallery.category,
          fontSizeValue: this.categoryFontSize(),
          heightValue: this.categoryHeight(),
          horizontalPadding: this.isLooseLayout() ? 10 : 8
        })
      }
      .alignItems(HorizontalAlign.End)
      .margin({ left: this.isLooseLayout() ? 10 : 8 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Bottom)
  }

  @Builder
  private detailArea() {
    Row() {
      GalleryThumb({
        url: this.gallery.thumb === undefined ? '' : this.gallery.thumb,
        widthValue: this.cardThumbWidth(),
        heightValue: this.detailAreaHeight(),
        radiusValue: 6
      })
        .height('100%')

      Column() {
        Column() {
          TranslationText({
            sourceText: galleryDisplayTitle(this.gallery),
            translationEnabled: this.translateTitle,
            fontSizeValue: this.titleFontSize(),
            fontWeightValue: FontWeight.Medium,
            fontColorValue: themePrimaryText(),
            lineHeightValue: this.titleLineHeight(),
            maxLinesValue: this.titleMaxLines()
          })
        }
        .width('100%')
        .height(this.titleHeight())
        .clip(true)
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)

        Blank()
        this.detailMetadata()
      }
      .height('100%')
      .layoutWeight(1)
      .padding({
        left: this.isLooseLayout() ? 12 : (this.isSmallThumb() ? 8 : 10),
        right: this.isLooseLayout() ? 10 : (this.isSmallThumb() ? 6 : 8),
        top: this.isLooseLayout() ? 8 : (this.isSmallThumb() ? 5 : this.cardGap()),
        bottom: this.isLooseLayout() ? 8 : (this.isSmallThumb() ? 5 : this.cardGap())
      })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(this.detailAreaHeight())
  }

  @Builder
  private extendedTagArea() {
    Scroll() {
      Row({ space: this.isLooseLayout() ? 6 : 4 }) {
        ForEach(this.previewTags(), (tag: string, index: number) => {
          GalleryTagChip({
            text: this.tagDisplayText(tag),
            backgroundColorValue: this.tagColor(index),
            color: this.tagTextColor(index),
            fontSizeValue: this.tagFontSize(),
            heightValue: this.tagRowHeight(),
            horizontalPadding: this.isLooseLayout() ? 9 : 7
          })
            .flexShrink(0)
        }, (tag: string, index: number) => tag + ':' + index.toString())
      }
      .padding({
        left: this.isLooseLayout() ? 12 : 8,
        right: this.isLooseLayout() ? 10 : 6
      })
    }
    .width('100%')
    .layoutWeight(1)
    .clip(true)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .padding({
      top: this.isLooseLayout() ? 6 : 4,
      bottom: this.isLooseLayout() ? 8 : 6
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.detailArea()
        if (this.isExtendedMode()) {
          this.extendedTagArea()
        }
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
  @Prop fontSizeValue: number = 12;
  @Prop heightValue: number = 21;
  @Prop horizontalPadding: number = 7;

  build() {
    Text(this.text)
      .fontSize(this.fontSizeValue)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.color)
      .height(this.heightValue)
      .padding({ left: this.horizontalPadding, right: this.horizontalPadding })
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
  onImageAspectRatio: (aspectRatio: number) => void = (_aspectRatio: number) => {};

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
    const cachedLocalSource = GALLERY_THUMB_LOCAL_SOURCE_CACHE.get(this.url);
    this.localUrl = cachedLocalSource === undefined ? '' : cachedLocalSource;
    this.loadFailed = false;
    if (this.localUrl.length > 0) {
      return;
    }
    cacheThumbnailImage(this.url, (path: string) => {
      if (this.cachedUrl !== this.url) {
        return;
      }
      this.localUrl = readerLocalImageSource(path);
      GALLERY_THUMB_LOCAL_SOURCE_CACHE.set(this.url, this.localUrl);
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
          Text(uiText('EH'))
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
          .onComplete((event?: GalleryImageCompleteEvent) => {
            if (event === undefined || event.width <= 0 || event.height <= 0) {
              return;
            }
            const aspectRatio = normalizedThumbnailAspectRatio(event.width, event.height);
            GALLERY_THUMB_ASPECT_RATIO_CACHE.set(this.url, aspectRatio);
            this.onImageAspectRatio(aspectRatio);
          })
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
  @Prop @Watch('onGalleryChange') gallery: GalleryInfo = createEmptyGallery();
  @Prop selected: boolean = false;
  @Prop translateTitle: boolean = false;
  onLongPress: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  @StorageProp(HISTORY_READ_REVISION_KEY) historyReadRevision: number = 0;
  @StorageProp(GALLERY_TITLE_REVISION_KEY) galleryTitleRevision: number = 0;
  @State resolvedThumbnailAspectRatio: number = 0.75;

  aboutToAppear(): void {
    this.syncThumbnailAspectRatio();
  }

  onGalleryChange(): void {
    this.syncThumbnailAspectRatio();
  }

  private syncThumbnailAspectRatio(): void {
    this.resolvedThumbnailAspectRatio = galleryThumbnailAspectRatio(this.gallery);
  }

  private updateThumbnailAspectRatio(aspectRatio: number): void {
    if (Math.abs(this.resolvedThumbnailAspectRatio - aspectRatio) < 0.001) {
      return;
    }
    this.resolvedThumbnailAspectRatio = aspectRatio;
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

  @Builder
  private thumbnailRightMetadata() {
    Column({ space: 6 }) {
      if (showGalleryLanguage() && showGalleryRating() && this.showReadPageText()) {
        Text(this.languageText())
          .fontSize(14)
          .lineHeight(18)
          .fontColor(themeTertiaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.showReadPageText()) {
        Row({ space: 6 }) {
          if (showGalleryLanguage() && !showGalleryRating()) {
            Text(this.languageText())
              .fontSize(14)
              .lineHeight(18)
              .fontColor(themeTertiaryText())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Text(this.readPageText())
            .fontSize(14)
            .lineHeight(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(themeTertiaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      } else if (showGalleryLanguage()) {
        Text(this.languageText())
          .fontSize(14)
          .lineHeight(18)
          .fontColor(themeTertiaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .alignItems(HorizontalAlign.End)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        GalleryThumb({
          url: this.gallery.thumb === undefined ? '' : this.gallery.thumb,
          widthValue: 0,
          heightValue: 0,
          onImageAspectRatio: (aspectRatio: number) => {
            this.updateThumbnailAspectRatio(aspectRatio);
          }
        })
          .width('100%')
          .aspectRatio(this.resolvedThumbnailAspectRatio)

        Column() {
          Column() {
            TranslationText({
              sourceText: galleryDisplayTitle(this.gallery),
              translationEnabled: this.translateTitle,
              fontSizeValue: 15,
              lineHeightValue: 19,
              fontWeightValue: FontWeight.Medium,
              fontColorValue: themePrimaryText(),
              maxLinesValue: 5
            })
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.Start)

          Row() {
            Column({ space: 6 }) {
              if (showGalleryRating()) {
                Rating({ rating: this.gallery.rating, indicator: true })
                  .stars(5)
                  .stepSize(0.5)
                  .height(16)
                  .width(86)
              }
              CategoryBadge({ category: this.gallery.category })
            }
            .alignItems(HorizontalAlign.Start)
            Blank()
            this.thumbnailRightMetadata()
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
          .margin({ top: 6 })
        }
        .padding({ left: 8, right: 8, top: 7, bottom: 8 })
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
  @Prop fontSizeValue: number = 14;
  @Prop heightValue: number = 24;
  @Prop horizontalPadding: number = 8;

  build() {
    Text(categoryDisplayName(this.category))
      .fontSize(this.fontSizeValue)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .height(this.heightValue)
      .padding({ left: this.horizontalPadding, right: this.horizontalPadding, top: 2, bottom: 2 })
      .backgroundColor(categoryColor(this.category))
      .borderRadius(3)
  }
}
