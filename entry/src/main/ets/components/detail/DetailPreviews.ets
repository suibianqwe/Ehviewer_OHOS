import { GalleryPreview } from '../../model/GalleryModels';
import { mainContentWidthFallbackVp, rememberMainContentWidthVp } from '../../services/EhWindowImmersive';
import {
  cachePreviewThumbnail,
  createEmptyPreview,
  readerLocalImageSource,
  shouldUseChineseUi,
  uiText
} from '../../shared/EhShared';
import {
  themePlaceholderColor,
  themeOnPrimaryText,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeScrimColor,
  themeSurface,
  themeSurfaceVariant
} from '../../shared/EhTheme';
import { GalleryThumb } from '../GalleryCards';
@Component
export struct DetailPreviews {
  @Prop previews: GalleryPreview[] = [];
  @Prop previewPages: number = 0;
  @Prop totalPages: number = 0;
  @Prop isDetailLoaded: boolean = false;
  onSelectPreview: (preview: GalleryPreview) => void = () => {};
  onOpenJumpPanel: () => void = () => {};
  @State contentWidth: number = 0;

  private previewGap(): number {
    return 8;
  }

  private previewColumns(): number {
    const available = Math.max(0, this.contentWidth - 32);
    if (available <= 0 || Number.isNaN(available)) {
      return 2;
    }
    const preferred = 132;
    const gap = this.previewGap();
    return Math.max(2, Math.floor((available + gap) / (preferred + gap)));
  }

  private previewTileWidth(): number {
    const available = Math.max(0, this.contentWidth - 32);
    const columns = this.previewColumns();
    const gap = this.previewGap();
    if (available <= 0 || Number.isNaN(available)) {
      return 132;
    }
    return Math.max(112, Math.floor((available - gap * (columns - 1)) / columns));
  }

  private previewTileHeight(): number {
    return Math.round(this.previewTileWidth() * 4 / 3);
  }

  private previewColumnsTemplate(): string {
    const columns = this.previewColumns();
    let value = '1fr';
    for (let i = 1; i < columns; i++) {
      value += ' 1fr';
    }
    return value;
  }

  private previewTotalPages(): number {
    if (this.totalPages > 0) {
      return this.totalPages;
    }
    return this.previewPages;
  }

  private syncContentWidthFromWindow(): void {
    if (this.contentWidth >= 240) {
      return;
    }
    const width = mainContentWidthFallbackVp((value: number) => this.getUIContext().px2vp(value));
    if (width >= 240) {
      this.contentWidth = width;
    }
  }

  build() {
    Column() {
      Text(uiText('Previews'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(themePrimaryText())
        .width('100%')
      Text(!this.isDetailLoaded ? uiText('Loading previews...') :
        (shouldUseChineseUi() ? this.previews.length.toString() + ' 个缩略图 / ' +
          this.previewTotalPages().toString() + ' 页' :
          this.previews.length.toString() + ' thumbnails / ' + this.previewTotalPages().toString() + ' pages'))
        .fontSize(12)
        .fontColor(this.isDetailLoaded && this.previewTotalPages() > 1 ? themePrimaryColor() : themeSecondaryText())
        .width('100%')
        .margin({ top: 6, bottom: 8 })
        .onClick(() => {
          if (this.isDetailLoaded && this.previewTotalPages() > 1) {
            this.onOpenJumpPanel();
          }
        })
      if (this.isDetailLoaded && this.previews.length === 0) {
        Text(uiText('No previews'))
          .fontSize(12)
          .fontColor(themeSecondaryText())
      } else if (!this.isDetailLoaded && this.previews.length === 0) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color(themePlaceholderColor())
          Text(uiText('Loading previews...'))
            .fontSize(12)
            .fontColor(themeSecondaryText())
        }
        .width('100%')
        .height(52)
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.previews, (preview: GalleryPreview) => {
            GridItem() {
              PreviewTile({
                preview: preview,
                tileWidth: this.previewTileWidth(),
                imageHeight: this.previewTileHeight(),
                onSelectPreview: (selected: GalleryPreview) => {
                  this.onSelectPreview(selected);
                }
              })
            }
          }, (preview: GalleryPreview) => preview.index.toString())
        }
        .columnsTemplate(this.previewColumnsTemplate())
        .columnsGap(this.previewGap())
        .rowsGap(12)
        .width('100%')
        .animation({ duration: 220, curve: Curve.EaseOut })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(themeSurface())
    .onAppear(() => {
      this.syncContentWidthFromWindow();
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const width = Math.floor(newArea.width as number);
      if (width > 0 && !Number.isNaN(width) && Math.abs(this.contentWidth - width) >= 1) {
        this.contentWidth = width;
        rememberMainContentWidthVp(width);
      }
    })
  }
}

@Component
export struct DetailPreviewJumpOverlay {
  @Prop totalPages: number = 0;
  @Prop initialPageIndex: number = 0;
  @State draftPageIndex: number = 0;
  onClose: (pageIndex: number) => void = (_pageIndex: number) => {};

  aboutToAppear(): void {
    this.syncDraftPage();
  }

  private syncDraftPage(): void {
    const maxIndex = Math.max(0, this.totalPages - 1);
    this.draftPageIndex = Math.max(0, Math.min(this.initialPageIndex, maxIndex));
  }

  private closeWithSelection(): void {
    const maxIndex = Math.max(0, this.totalPages - 1);
    this.onClose(Math.max(0, Math.min(this.draftPageIndex, maxIndex)));
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(themeScrimColor())
        .onClick(() => {
          this.closeWithSelection();
        })

      Column() {
        Text(uiText('Jump'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .width('100%')
        Text(uiText('Page') + ' ' + (this.draftPageIndex + 1).toString() + ' / ' +
          Math.max(1, this.totalPages).toString())
          .fontSize(15)
          .fontColor(themeSecondaryText())
          .width('100%')
          .margin({ top: 12, bottom: 12 })
        Slider({
          value: this.draftPageIndex,
          min: 0,
          max: Math.max(0, this.totalPages - 1),
          step: 1,
          style: SliderStyle.OutSet
        })
          .blockColor(themePrimaryColor())
          .selectedColor(themePrimaryColor())
          .trackColor(themeSurfaceVariant())
          .enabled(this.totalPages > 1)
          .onChange((value: number, _mode: SliderChangeMode) => {
            this.draftPageIndex = Math.round(value);
          })
        Button(uiText('Close'), { type: ButtonType.Normal, stateEffect: true })
          .height(38)
          .fontSize(14)
          .fontColor(themeOnPrimaryText())
          .backgroundColor(themePrimaryColor())
          .borderRadius(6)
          .width('100%')
          .margin({ top: 16 })
          .onClick(() => {
            this.closeWithSelection();
          })
      }
      .width('86%')
      .constraintSize({ maxWidth: 420 })
      .padding(18)
      .backgroundColor(themeSurface())
      .borderRadius(8)
      .shadow({
        radius: 18,
        color: '#33000000',
        offsetX: 0,
        offsetY: 8
      })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct PreviewRow {
  preview: GalleryPreview = createEmptyPreview();
  onSelectPreview: (preview: GalleryPreview) => void = () => {};

  build() {
    Row() {
      GalleryThumb({
        url: this.preview.imageUrl,
        widthValue: 74,
        heightValue: 54
      })
      Column() {
        Text(uiText('Page') + ' ' + (this.preview.index + 1).toString())
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
        Text(this.preview.pageUrl)
          .fontSize(11)
          .fontColor(themeSecondaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 5 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .margin({ top: 8 })
    .onClick(() => {
      this.onSelectPreview(this.preview);
    })
  }
}

@Component
export struct PreviewTile {
  preview: GalleryPreview = createEmptyPreview();
  tileWidth: number = 132;
  imageHeight: number = 96;
  onSelectPreview: (preview: GalleryPreview) => void = () => {};

  build() {
    Column() {
      PreviewThumb({
        preview: this.preview,
        widthValue: this.tileWidth,
        heightValue: this.imageHeight,
        radiusValue: 4
      })
      Text((this.preview.index + 1).toString())
        .fontSize(11)
        .fontColor(themeSecondaryText())
        .margin({ top: 6 })
    }
    .width(this.tileWidth)
    .padding({ bottom: 2 })
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.onSelectPreview(this.preview);
    })
  }
}

@Component
export struct PreviewThumb {
  @Prop @Watch('onPreviewChange') preview: GalleryPreview = createEmptyPreview();
  widthValue: number = 132;
  heightValue: number = 96;
  radiusValue: number = 4;
  @State localUrl: string = '';
  @State loadFailed: boolean = false;
  private cachedUrl: string = '';

  aboutToAppear(): void {
    if (this.preview.imageUrl.length > 0) {
      this.cacheThumb();
    } else {
      this.loadFailed = true;
    }
  }

  onPreviewChange(): void {
    if (this.preview.imageUrl.length > 0) {
      this.cacheThumb();
    } else {
      this.cachedUrl = '';
      this.localUrl = '';
      this.loadFailed = true;
    }
  }

  private cacheThumb(): void {
    const cacheKey = this.preview.imageUrl + '#' + this.preview.xOffset.toString() + ',' +
      this.preview.yOffset.toString() + ',' + this.preview.width.toString() + 'x' + this.preview.height.toString();
    if (this.preview.imageUrl.length === 0 ||
      (cacheKey === this.cachedUrl && (this.localUrl.length > 0 || this.loadFailed))) {
      return;
    }
    this.cachedUrl = cacheKey;
    this.localUrl = '';
    this.loadFailed = false;
    cachePreviewThumbnail(this.preview, (localPath: string) => {
      if (this.cachedUrl !== cacheKey) {
        return;
      }
      if (localPath.length > 0) {
        this.localUrl = readerLocalImageSource(localPath);
        this.loadFailed = false;
      }
    }, () => {
      if (this.cachedUrl === cacheKey) {
        this.localUrl = '';
        this.loadFailed = true;
      }
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
            .fontSize(20)
            .fontColor([themePlaceholderColor()])
          Text((this.preview.index + 1).toString())
            .fontSize(10)
            .fontColor(themePlaceholderColor())
        }
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.cachedUrl = '';
          this.cacheThumb();
        })
      } else if (this.localUrl.length > 0) {
        Image(this.localUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .syncLoad(true)
          .onError(() => {
            this.loadFailed = true;
          })
      } else {
        LoadingProgress()
          .width(28)
          .height(28)
          .color(themePlaceholderColor())
      }
    }
    .width(this.widthValue)
    .height(this.heightValue)
    .clip(true)
    .borderRadius(this.radiusValue)
  }
}

