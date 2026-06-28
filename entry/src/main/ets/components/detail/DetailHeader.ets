import { GalleryDetail } from '../../model/GalleryModels';
import { createEmptyDetail, detailTitleFontSize, detailTitleMaxLines, galleryDisplayTitle, galleryThumbHeight, galleryThumbWidth, uiStatusText, uiText } from '../../shared/EhShared';
import {
  themeAccentBackground,
  themeDangerBackground,
  themeDangerText,
  themeInfoBackground,
  themeInfoText,
  themeOnAccentText,
  themeOnPrimaryActionBackground,
  themeOnPrimaryActionStrongBackground,
  themeOnPrimarySecondaryText,
  themeOnPrimaryText,
  themePrimaryColor
} from '../../shared/EhTheme';
import { CategoryBadge, GalleryThumb } from '../GalleryCards';
@Component
export struct DetailHeader {
  @Prop detail: GalleryDetail = createEmptyDetail();
  @Prop downloadText: string = 'Download';
  onDownload: () => void = () => {};
  onRead: () => void = () => {};

  build() {
    Column() {
      Row() {
        GalleryThumb({
          url: this.detail.thumb === undefined ? '' : this.detail.thumb,
          widthValue: galleryThumbWidth(),
          heightValue: galleryThumbHeight()
        })
        Column() {
          Text(galleryDisplayTitle(this.detail))
            .fontSize(detailTitleFontSize())
            .fontWeight(FontWeight.Bold)
            .fontColor(themeOnPrimaryText())
            .maxLines(detailTitleMaxLines())
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.detail.uploader === undefined || this.detail.uploader.length === 0 ? uiText('unknown uploader') :
            this.detail.uploader)
            .fontSize(12)
            .fontColor(themeOnPrimarySecondaryText())
            .margin({ top: 8 })
          CategoryBadge({ category: this.detail.category })
            .margin({ top: 12 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 14 })
      }
      .width('100%')

      Row() {
        HeaderActionButton({
          symbolIcon: this.downloadIcon(),
          text: uiText(this.downloadText),
          onTap: this.onDownload
        })
          .layoutWeight(1)
        Column()
          .width(1)
          .height(32)
          .backgroundColor(themeOnPrimaryActionStrongBackground())
        HeaderActionButton({
          symbolIcon: $r('sys.symbol.play_fill'),
          text: uiText('Read'),
          accent: true,
          onTap: this.onRead
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .margin({ top: 16 })
      .padding(4)
      .backgroundColor(themeOnPrimaryActionBackground())
      .borderRadius(6)
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
}

@Component
export struct HeaderActionButton {
  @Prop symbolIcon: Resource = $r('sys.symbol.play_fill');
  @Prop text: string = '';
  @Prop accent: boolean = false;
  onTap: () => void = () => {};
  @State pressed: boolean = false;

  build() {
    Row() {
      SymbolGlyph(this.symbolIcon)
        .fontSize(22)
        .fontColor([this.accent ? themeOnAccentText() : themeOnPrimaryText()])
      Text(this.text)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accent ? themeOnAccentText() : themeOnPrimaryText())
        .margin({ left: 10 })
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .height(48)
    .width('100%')
    .backgroundColor(this.accent ? themeAccentBackground() : themeOnPrimaryActionStrongBackground())
    .borderRadius(4)
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

