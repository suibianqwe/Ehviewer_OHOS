import { GalleryPreview } from '../../model/GalleryModels';
import { cacheThumbnailImage, createEmptyPreview, readerLocalImageSource, shouldUseChineseUi, uiText } from '../../shared/EhShared';
import { GalleryThumb } from '../GalleryCards';
@Component
export struct DetailPreviews {
  @Prop previews: GalleryPreview[] = [];
  @Prop previewPages: number = 0;
  @Prop isDetailLoaded: boolean = false;
  onSelectPreview: (preview: GalleryPreview) => void = () => {};
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

  private previewRows(): GalleryPreview[][] {
    const columns = this.previewColumns();
    const items = this.previews;
    const rows: GalleryPreview[][] = [];
    for (let i = 0; i < items.length; i += columns) {
      rows.push(items.slice(i, i + columns));
    }
    return rows;
  }

  build() {
    Column() {
      Text(uiText('Previews'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#17202A')
        .width('100%')
      Text(!this.isDetailLoaded ? uiText('Loading previews...') :
        (shouldUseChineseUi() ? this.previews.length.toString() + ' 个缩略图 / ' + this.previewPages.toString() + ' 页' :
          this.previews.length.toString() + ' thumbnails / ' + this.previewPages.toString() + ' pages'))
        .fontSize(12)
        .fontColor('#667085')
        .width('100%')
        .margin({ top: 6, bottom: 8 })
      if (this.isDetailLoaded && this.previews.length === 0) {
        Text(uiText('No previews'))
          .fontSize(12)
          .fontColor('#667085')
      } else {
        Column() {
          ForEach(this.previewRows(), (row: GalleryPreview[], rowIndex: number) => {
            Row() {
              ForEach(row, (preview: GalleryPreview, colIndex: number) => {
                PreviewTile({
                  preview: preview,
                  tileWidth: this.previewTileWidth(),
                  imageHeight: this.previewTileHeight(),
                  onSelectPreview: (selected: GalleryPreview) => {
                    this.onSelectPreview(selected);
                  }
                })
                  .margin({ right: colIndex < row.length - 1 ? this.previewGap() : 0 })
              }, (preview: GalleryPreview) => preview.index.toString())
            }
            .width('100%')
            .justifyContent(FlexAlign.Start)
            .margin({ bottom: rowIndex < this.previewRows().length - 1 ? 12 : 0 })
            .animation({ duration: 220, curve: Curve.EaseOut })
          }, (row: GalleryPreview[], rowIndex: number) => rowIndex.toString() + ':' +
            row.map((preview: GalleryPreview) => preview.index.toString()).join('-'))
        }
        .width('100%')
        .animation({ duration: 220, curve: Curve.EaseOut })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const width = newArea.width as number;
      if (width > 0 && !Number.isNaN(width) && this.contentWidth !== width) {
        this.contentWidth = width;
      }
    })
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
          .fontColor('#17202A')
        Text(this.preview.pageUrl)
          .fontSize(11)
          .fontColor('#667085')
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
        .fontColor('#40566F')
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
    const url = this.preview.imageUrl;
    if (url.length === 0 || (url === this.cachedUrl && (this.localUrl.length > 0 || this.loadFailed))) {
      return;
    }
    this.cachedUrl = url;
    this.localUrl = '';
    this.loadFailed = false;
    cacheThumbnailImage(url, (localPath: string) => {
      if (this.cachedUrl !== url) {
        return;
      }
      if (localPath.length > 0) {
        this.localUrl = readerLocalImageSource(localPath);
        this.loadFailed = false;
      }
    }, () => {
      if (this.cachedUrl === url) {
        this.localUrl = '';
        this.loadFailed = true;
      }
    });
  }

  private usesSpriteCrop(): boolean {
    return this.preview.width > 0 && this.preview.height > 0;
  }

  private spriteScale(): number {
    const sourceWidth = this.preview.width > 0 ? this.preview.width : this.widthValue;
    const sourceHeight = this.preview.height > 0 ? this.preview.height : this.heightValue;
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      return 1;
    }
    return Math.max(this.widthValue / sourceWidth, this.heightValue / sourceHeight);
  }

  private spriteXPosition(): number {
    const scale = this.spriteScale();
    const sourceWidth = this.preview.width > 0 ? this.preview.width : this.widthValue;
    return Math.round(-this.preview.xOffset * scale + (this.widthValue - sourceWidth * scale) / 2);
  }

  private spriteYPosition(): number {
    const scale = this.spriteScale();
    const sourceHeight = this.preview.height > 0 ? this.preview.height : this.heightValue;
    return Math.round(-this.preview.yOffset * scale + (this.heightValue - sourceHeight * scale) / 2);
  }

  private spriteDisplayWidth(): number {
    const sourceWidth = this.preview.width > 0 ? this.preview.width : this.widthValue;
    return Math.max(1, Math.round(sourceWidth * this.spriteScale()));
  }

  private spriteDisplayHeight(): number {
    const sourceHeight = this.preview.height > 0 ? this.preview.height : this.heightValue;
    return Math.max(1, Math.round(sourceHeight * this.spriteScale()));
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#E7ECF1')
        .borderRadius(this.radiusValue)

      if (this.loadFailed) {
        Column({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor(['#9BB8CB'])
          Text((this.preview.index + 1).toString())
            .fontSize(10)
            .fontColor('#9BB8CB')
        }
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.cachedUrl = '';
          this.cacheThumb();
        })
      } else if (this.localUrl.length > 0 && this.usesSpriteCrop()) {
        Stack() {
          Image(this.localUrl)
            .fitOriginalSize(true)
            .objectFit(ImageFit.None)
            .width(this.spriteDisplayWidth())
            .height(this.spriteDisplayHeight())
            .position({ x: this.spriteXPosition(), y: this.spriteYPosition() })
            .syncLoad(true)
            .onError(() => {
              this.loadFailed = true;
            })
        }
        .width('100%')
        .height('100%')
        .clip(true)
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
          .color('#9BB8CB')
      }
    }
    .width(this.widthValue)
    .height(this.heightValue)
    .clip(true)
    .borderRadius(this.radiusValue)
  }
}

