import { pasteboard } from '@kit.BasicServicesKit';
import { GalleryDetail } from '../../model/GalleryModels';
import {
  categoryDisplayName,
  createEmptyDetail,
  uiText
} from '../../shared/EhShared';
import {
  themeDividerColor,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSurface
} from '../../shared/EhTheme';
import { EhSubNavBar } from '../NavigationComponents';

interface GalleryInfoRowData {
  key: string;
  value: string;
}

@Component
export struct DetailInfoBlock {
  @Prop detail: GalleryDetail = createEmptyDetail();
  @Prop requestUrl: string = '';
  @Prop isDetailLoaded: boolean = false;
  onMoreInfo: () => void = () => {};

  private pagesText(): string {
    if (this.detail.pages <= 0) {
      return '-';
    }
    return uiText(this.detail.pages.toString() + ' pages');
  }

  private favoriteText(): string {
    if (!this.isDetailLoaded) {
      return uiText('Loading...');
    }
    return uiText(this.detail.favoriteCount.toString() + ' favored');
  }

  private languageText(): string {
    if (this.detail.language.length > 0) {
      return this.detail.language;
    }
    if (this.detail.simpleLanguage !== undefined && this.detail.simpleLanguage.length > 0) {
      return this.detail.simpleLanguage;
    }
    return '-';
  }

  build() {
    Column() {
      Row() {
        DetailSummaryCell({ value: this.languageText(), textAlignValue: TextAlign.Start })
        DetailSummaryCell({ value: this.pagesText(), textAlignValue: TextAlign.Center })
        DetailSummaryCell({
          value: this.isDetailLoaded ? (this.detail.size.length > 0 ? this.detail.size : '-') : uiText('Loading...'),
          textAlignValue: TextAlign.End
        })
      }
      .width('100%')

      Row() {
        DetailSummaryCell({ value: this.favoriteText(), textAlignValue: TextAlign.Start })
        DetailSummaryCell({
          value: this.detail.posted === undefined || this.detail.posted.length === 0 ? '-' : this.detail.posted,
          textAlignValue: TextAlign.End
        })
      }
      .width('100%')
      .margin({ top: 8 })

      Text(uiText('More information'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(themePrimaryColor())
        .alignSelf(ItemAlign.Center)
        .margin({ top: 16 })
        .onClick(() => {
          this.onMoreInfo();
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(themeSurface())
  }
}

@Component
export struct DetailSummaryCell {
  @Prop value: string = '';
  @Prop textAlignValue: TextAlign = TextAlign.Start;

  build() {
    Text(this.value.length === 0 ? '-' : this.value)
      .fontSize(13)
      .fontColor(themePrimaryText())
      .textAlign(this.textAlignValue)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .layoutWeight(1)
  }
}

@Component
export struct GalleryInfoScene {
  @Prop detail: GalleryDetail = createEmptyDetail();
  @Prop requestUrl: string = '';
  @Prop statusBarHeight: number = 0;
  onBack: () => void = () => {};

  private valueOrDash(value: string | undefined): string {
    if (value === undefined || value.length === 0) {
      return '-';
    }
    return value;
  }

  private galleryUrl(): string {
    if (this.requestUrl.length > 0) {
      return this.requestUrl;
    }
    if (this.detail.gid <= 0 || this.detail.token.length === 0) {
      return '';
    }
    return 'https://e-hentai.org/g/' + this.detail.gid.toString() + '/' + this.detail.token + '/';
  }

  private booleanText(value: boolean): string {
    return value ? 'true' : 'false';
  }

  private languageText(): string {
    if (this.detail.language.length > 0) {
      return this.detail.language;
    }
    return this.valueOrDash(this.detail.simpleLanguage);
  }

  private infoRows(): GalleryInfoRowData[] {
    const rows: GalleryInfoRowData[] = [];
    rows.push({ key: 'Gid', value: this.detail.gid > 0 ? this.detail.gid.toString() : '-' });
    rows.push({ key: 'Token', value: this.valueOrDash(this.detail.token) });
    rows.push({ key: 'URL', value: this.valueOrDash(this.galleryUrl()) });
    rows.push({ key: 'Title', value: this.valueOrDash(this.detail.title) });
    rows.push({ key: 'Jpn Title', value: this.valueOrDash(this.detail.titleJpn) });
    rows.push({ key: 'Thumb', value: this.valueOrDash(this.detail.thumb) });
    rows.push({ key: 'Category', value: categoryDisplayName(this.detail.category) });
    rows.push({ key: 'Uploader', value: this.valueOrDash(this.detail.uploader) });
    rows.push({ key: 'Posted', value: this.valueOrDash(this.detail.posted) });
    rows.push({ key: 'Parent', value: this.valueOrDash(this.detail.parent) });
    rows.push({ key: 'Visible', value: this.valueOrDash(this.detail.visible) });
    rows.push({ key: 'Language', value: this.languageText() });
    rows.push({ key: 'Pages', value: this.detail.pages > 0 ? this.detail.pages.toString() : '-' });
    rows.push({ key: 'File Size', value: this.valueOrDash(this.detail.size) });
    rows.push({ key: 'Favorite count', value: this.detail.favoriteCount >= 0 ? this.detail.favoriteCount.toString() : '-' });
    rows.push({ key: 'Favorited', value: this.booleanText(this.detail.isFavorited) });
    rows.push({ key: 'Rating count', value: this.detail.ratingCount >= 0 ? this.detail.ratingCount.toString() : '-' });
    rows.push({ key: 'Rating', value: this.detail.rating > 0 ? this.detail.rating.toString() : '-' });
    rows.push({ key: 'Torrents', value: this.detail.torrentCount >= 0 ? this.detail.torrentCount.toString() : '-' });
    rows.push({ key: 'Torrent URL', value: this.valueOrDash(this.detail.torrentUrl) });
    rows.push({ key: 'Favorite name', value: this.valueOrDash(this.detail.favoriteName) });
    return rows;
  }

  private copyValue(value: string): void {
    copyTextToClipboard(value, this.getUIContext());
  }

  build() {
    Column() {
      EhSubNavBar({
        statusBarHeight: this.statusBarHeight,
        title: uiText('Gallery Info'),
        onBack: this.onBack
      })

      List({ space: 0 }) {
        ListItem() {
          GalleryInfoHeaderRow()
        }
        .reuseId('gallery-info-header')

        ForEach(this.infoRows(), (row: GalleryInfoRowData) => {
          ListItem() {
            GalleryInfoDataRow({
              label: uiText(row.key),
              value: row.value,
              onCopy: () => {
                this.copyValue(row.value);
              }
            })
          }
          .reuseId('gallery-info-row')
        }, (row: GalleryInfoRowData) => row.key)
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .backgroundColor(themePageBackground())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}

@Component
struct GalleryInfoHeaderRow {
  build() {
    Row() {
      Text(uiText('Key'))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(themeSecondaryText())
        .width(112)
      Text(uiText('Value'))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(themeSecondaryText())
        .layoutWeight(1)
    }
    .width('100%')
    .height(42)
    .padding({ left: 16, right: 16 })
    .backgroundColor(themeSurface())
  }
}

@Component
struct GalleryInfoDataRow {
  @Prop label: string = '';
  @Prop value: string = '';
  onCopy: () => void = () => {};

  build() {
    Row() {
      Text(this.label)
        .fontSize(13)
        .fontColor(themeSecondaryText())
        .width(112)
      Text(this.value.length === 0 ? '-' : this.value)
        .fontSize(13)
        .fontColor(themePrimaryText())
        .copyOption(CopyOptions.LocalDevice)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .maxLines(3)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(themeSurface())
    .border({ width: { bottom: 1 }, color: themeDividerColor() })
    .onClick(() => {
      this.onCopy();
    })
  }
}

export function copyTextToClipboard(value: string, uiContext: UIContext): void {
  const text = value.trim();
  if (text.length === 0 || text === '-') {
    return;
  }
  try {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      showCopyToast(uiContext, 'Copied to clipboard');
    }).catch(() => {
      showCopyToast(uiContext, 'Copy failed');
    });
  } catch (error) {
    showCopyToast(uiContext, 'Copy failed');
  }
}

function showCopyToast(uiContext: UIContext, message: string): void {
  try {
    uiContext.getPromptAction().showToast({ message: uiText(message) });
  } catch (error) {
  }
}
