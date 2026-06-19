import { DownloadInfo, DownloadState } from '../services/EhDownloadStore';
import {
  createEmptyDownloadInfo,
  downloadProgressText,
  downloadSizeText,
  downloadStateLabel,
  downloadStateColor,
  galleryDisplayTitle,
  galleryThumbHeight,
  galleryThumbWidth,
  ratingText,
  uiText,
  uiValue
} from '../shared/EhShared';
import { themeDividerColor, themePrimaryText, themeSecondaryText, themeSurface, themeTertiaryText } from '../shared/EhTheme';
import { CategoryBadge, GalleryThumb } from './GalleryScenes';

@Component
export struct DownloadRow {
  item: DownloadInfo = createEmptyDownloadInfo();
  onOpen: () => void = () => {};
  onThumb: () => void = () => {};
  onState: () => void = () => {};
  onRemove: () => void = () => {};

  private isActive(): boolean {
    return this.item.state === DownloadState.Wait || this.item.state === DownloadState.Downloading;
  }

  private isDownloading(): boolean {
    return this.item.state === DownloadState.Downloading;
  }

  private actionIcon(): Resource {
    return this.isActive() ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill');
  }

  private progressTotal(): number {
    const total = this.item.total > 0 ? this.item.total : this.item.pages;
    return Math.max(0, total);
  }

  private progressPercent(): string {
    const total = this.progressTotal();
    if (total <= 0) {
      return '0%';
    }
    const value = Math.max(0, Math.min(100, Math.round(this.item.finished * 100 / total)));
    return value.toString() + '%';
  }

  private speedText(): string {
    if (this.item.speed <= 0) {
      return '0 B/s';
    }
    return downloadSizeText(this.item.speed) + '/s';
  }

  build() {
    Row() {
      GalleryThumb({
        url: this.item.thumb === undefined ? '' : this.item.thumb,
        widthValue: galleryThumbWidth(),
        heightValue: galleryThumbHeight()
      })
        .onClick(() => {
          this.onThumb();
        })

      Column() {
        Row() {
          Text(galleryDisplayTitle(this.item))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(uiValue(downloadStateLabel(this.item.state)))
            .fontSize(11)
            .fontColor(Color.White)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .backgroundColor(downloadStateColor(this.item.state))
            .borderRadius(3)
        }
        .width('100%')

        if (this.isDownloading()) {
          Row() {
            Text(downloadProgressText(this.item))
              .fontSize(11)
              .fontColor(themeSecondaryText())
            Blank()
            Text(this.speedText())
              .fontSize(11)
              .fontColor(themeSecondaryText())
          }
          .width('100%')
          .margin({ top: 8 })

          Stack({ alignContent: Alignment.Start }) {
            Row()
              .height(4)
              .width('100%')
              .backgroundColor(themeDividerColor())
              .borderRadius(2)
            Row()
              .height(4)
              .width(this.progressPercent())
              .backgroundColor(downloadStateColor(this.item.state))
              .borderRadius(2)
          }
          .width('100%')
          .height(4)
          .margin({ top: 6 })
        } else {
          Text(this.item.uploader === undefined || this.item.uploader.length === 0 ? uiText('unknown uploader') :
            this.item.uploader)
            .fontSize(12)
            .fontColor(themeTertiaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 5 })

          Row() {
            CategoryBadge({ category: this.item.category })
            Text(ratingText(this.item.rating))
              .fontSize(12)
              .fontColor(themeSecondaryText())
              .margin({ left: 8 })
            Text(downloadProgressText(this.item))
              .fontSize(12)
              .fontColor(themeSecondaryText())
              .margin({ left: 8 })
            if (this.item.label.length > 0) {
              Text(this.item.label)
                .fontSize(12)
                .fontColor(themeSecondaryText())
                .margin({ left: 8 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .width('100%')
          .margin({ top: 8 })
        }
      }
      .height(galleryThumbHeight())
      .layoutWeight(1)
      .margin({ left: 10 })
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        this.onOpen();
      })

      Column({ space: 8 }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.actionIcon())
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(38)
        .height(38)
        .backgroundColor(this.isActive() ? '#475467' : '#2F6F8F')
        .onClick(() => {
          this.onState();
        })

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(17)
            .fontColor([themeSecondaryText()])
        }
        .width(34)
        .height(34)
        .backgroundColor('transparent')
        .onClick(() => {
          this.onRemove();
        })
      }
      .justifyContent(FlexAlign.Center)
      .margin({ left: 8 })
    }
    .width('100%')
    .padding(8)
    .backgroundColor(themeSurface())
    .borderRadius(6)
  }
}
