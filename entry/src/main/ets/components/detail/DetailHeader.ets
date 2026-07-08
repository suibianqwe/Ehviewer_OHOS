import { GalleryDetail } from '../../model/GalleryModels';
import {
  categoryColor,
  categoryName,
  createEmptyDetail,
  detailTitleFontSize,
  detailTitleMaxLines,
  galleryDisplayTitle,
  uiStatusText,
  uiText
} from '../../shared/EhShared';
import {
  themeDangerBackground,
  themeDangerText,
  themeInfoBackground,
  themeInfoText,
  themeOnPrimarySecondaryText,
  themeOnPrimaryText,
  themePrimaryColor
} from '../../shared/EhTheme';
import { GalleryThumb } from '../GalleryCards';
import { copyTextToClipboard } from './DetailInfo';
@Component
export struct DetailHeader {
  @Prop detail: GalleryDetail = createEmptyDetail();
  @Prop downloadText: string = 'Download';
  onDownload: () => void = () => {};
  onRead: () => void = () => {};
  onUploaderSearch: () => void = () => {};
  onCategorySearch: () => void = () => {};

  build() {
    Column() {
      Row({ space: 10 }) {
        GalleryThumb({
          url: this.detail.thumb === undefined ? '' : this.detail.thumb,
          widthValue: this.detailThumbWidth(),
          heightValue: this.detailThumbHeight()
        })
        Column() {
          Text(galleryDisplayTitle(this.detail))
            .fontSize(detailTitleFontSize())
            .fontWeight(FontWeight.Bold)
            .fontColor(themeOnPrimaryText())
            .maxLines(detailTitleMaxLines())
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => {
              copyTextToClipboard(galleryDisplayTitle(this.detail), this.getUIContext());
            })
          Text(this.detail.uploader === undefined || this.detail.uploader.length === 0 ? uiText('unknown uploader') :
            this.detail.uploader)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(themeOnPrimarySecondaryText())
            .margin({ top: 8 })
            .onClick(() => {
              this.onUploaderSearch();
            })
          DetailCategoryBadge({
            category: this.detail.category,
            onTap: this.onCategorySearch
          })
            .margin({ top: 12 })

          Row({ space: 12 }) {
            HeaderActionButton({
              symbolIcon: this.downloadIcon(),
              text: uiText(this.downloadText),
              onTap: this.onDownload
            })
              .layoutWeight(1)
            HeaderActionButton({
              symbolIcon: $r('sys.symbol.play_fill'),
              text: uiText('Read'),
              accent: true,
              onTap: this.onRead
            })
              .layoutWeight(1)
          }
          .width('100%')
          .margin({ top: 16 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 14 })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(themePrimaryColor())
  }

  private downloadIcon(): Resource {
    if (this.downloadText === 'Downloaded') {
      return $r('sys.symbol.checkmark');
    }
    if (this.downloadText === 'Waiting' || this.downloadText === 'Downloading') {
      return $r('sys.symbol.pause_fill');
    }
    return $r('sys.symbol.save');
  }

  private detailThumbHeight(): number {
    const maxLines = detailTitleMaxLines();
    if (maxLines <= 3) {
      return 160;
    }
    if (maxLines >= 6) {
      return 188;
    }
    return 176;
  }

  private detailThumbWidth(): number {
    return Math.round(this.detailThumbHeight() * 0.73);
  }
}

@Component
struct DetailCategoryBadge {
  @Prop category: number = 0;
  onTap: () => void = () => {};

  build() {
    Text(categoryName(this.category))
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .height(28)
      .padding({ left: 11, right: 11, top: 3, bottom: 3 })
      .backgroundColor(categoryColor(this.category))
      .borderRadius(5)
      .onClick(() => {
        this.onTap();
      })
  }
}

@Component
export struct HeaderActionButton {
  @Prop symbolIcon: Resource = $r('sys.symbol.play_fill');
  @Prop text: string = '';
  @Prop accent: boolean = false;
  onTap: () => void = () => {};
  @State pressed: boolean = false;

  private buttonBackground(): string {
    return this.accent ? '#FFD34D' : '#D9EEF4';
  }

  private contentColor(): string {
    return this.accent ? '#111827' : themePrimaryColor();
  }

  build() {
    Row() {
      SymbolGlyph(this.symbolIcon)
        .fontSize(22)
        .fontColor([this.contentColor()])
      Text(this.text)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.contentColor())
        .margin({ left: 10 })
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .height(46)
    .width('100%')
    .backgroundColor(this.buttonBackground())
    .borderRadius(23)
    .border({
      width: this.accent ? 0 : 1,
      color: this.accent ? '#FFD34D' : '#C2E0E8'
    })
    .shadow({
      radius: this.pressed ? 2 : 6,
      color: '#22000000',
      offsetX: 0,
      offsetY: this.pressed ? 1 : 2
    })
    .scale({ x: this.pressed ? 0.96 : 1, y: this.pressed ? 0.96 : 1 })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      this.onTap();
    })
  }
}

@Component
export struct DetailLoadStatus {
  @Prop statusText: string = '';
  @Prop isError: boolean = false;

  build() {
    Row() {
      if (!this.isError) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(themePrimaryColor())
          .margin({ right: 10 })
      } else {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(18)
          .fontColor([themeDangerText()])
          .margin({ right: 10 })
      }
      Text(uiStatusText(this.statusText))
        .fontSize(12)
        .fontColor(this.isError ? themeDangerText() : themeInfoText())
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(this.isError ? themeDangerBackground() : themeInfoBackground())
  }
}

