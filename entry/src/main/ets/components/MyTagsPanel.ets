import { GallerySite } from '../model/GalleryModels';
import { ehMyTagsService, MyTagItem, MyTagKind, MyTagsPage } from '../services/EhMyTagsService';
import { uiStatusText, uiText } from '../shared/EhShared';
import {
  themeFieldBackground,
  themeOnPrimaryText,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSurface,
  themeSurfaceVariant,
  themeTertiaryText
} from '../shared/EhTheme';

@Component
export struct MyTagsPanel {
  site: GallerySite = GallerySite.E;
  @State loading: boolean = false;
  @State saving: boolean = false;
  @State statusText: string = '';
  @State watchedText: string = '';
  @State hiddenText: string = '';
  @State watchedTags: MyTagItem[] = [];
  @State hiddenTags: MyTagItem[] = [];
  private page: MyTagsPage | null = null;

  aboutToAppear(): void {
    this.loadTags();
  }

  private loadTags(): void {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.statusText = 'Loading My Tags...';
    ehMyTagsService.load(this.site).then((page: MyTagsPage) => {
      this.applyPage(page);
      this.statusText = 'My Tags loaded';
    }).catch((error: Error) => {
      this.statusText = 'My Tags load failed: ' + error.message;
    }).finally(() => {
      this.loading = false;
    });
  }

  private saveWatchedTag(): void {
    this.saveTag(this.watchedText, MyTagKind.Watched);
  }

  private saveHiddenTag(): void {
    this.saveTag(this.hiddenText, MyTagKind.Hidden);
  }

  private saveTag(text: string, kind: MyTagKind): void {
    const tag = text.trim();
    if (tag.length === 0) {
      this.statusText = 'Enter a tag first';
      return;
    }
    if (this.saving) {
      return;
    }
    this.saving = true;
    this.statusText = 'Saving My Tags...';
    ehMyTagsService.saveTag(this.site, this.page, tag, kind).then((page: MyTagsPage) => {
      this.applyPage(page);
      if (kind === MyTagKind.Watched) {
        this.watchedText = '';
      } else {
        this.hiddenText = '';
      }
      this.statusText = 'My Tags saved';
    }).catch((error: Error) => {
      this.statusText = 'My Tags save failed: ' + error.message;
    }).finally(() => {
      this.saving = false;
    });
  }

  private applyPage(page: MyTagsPage): void {
    this.page = page;
    this.watchedTags = cloneTags(page.watched);
    this.hiddenTags = cloneTags(page.hidden);
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          Text(uiText('Manage watched and hidden tags for the selected site.'))
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .lineHeight(18)
            .width('100%')

          Row({ space: 10 }) {
            MyTagsColumn({
              title: 'Subscription',
              summary: 'Watched tags are used by the subscription page',
              text: this.watchedText,
              placeholder: 'Tag name',
              tags: this.watchedTags,
              loading: this.loading || this.saving,
              onTextChange: (value: string) => {
                this.watchedText = value;
              },
              onSave: () => {
                this.saveWatchedTag();
              }
            })
              .layoutWeight(1)
            MyTagsColumn({
              title: 'Blocked',
              summary: 'Hidden tags are filtered by the account',
              text: this.hiddenText,
              placeholder: 'Tag name',
              tags: this.hiddenTags,
              loading: this.loading || this.saving,
              onTextChange: (value: string) => {
                this.hiddenText = value;
              },
              onSave: () => {
                this.saveHiddenTag();
              }
            })
              .layoutWeight(1)
          }
          .alignItems(VerticalAlign.Top)
          .width('100%')

          Row() {
            Button(uiText('Refresh'), { type: ButtonType.Normal, stateEffect: true })
              .fontSize(13)
              .fontColor(themeOnPrimaryText())
              .backgroundColor(themePrimaryColor())
              .borderRadius(6)
              .height(36)
              .enabled(!this.loading && !this.saving)
              .onClick(() => {
                this.loadTags();
              })
            Text(uiStatusText(this.statusText))
              .fontSize(12)
              .fontColor(themeTertiaryText())
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: 10 })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .padding({ left: 12, right: 12, top: 12, bottom: 20 })
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}

@Component
struct MyTagsColumn {
  title: string = '';
  summary: string = '';
  text: string = '';
  placeholder: string = '';
  tags: MyTagItem[] = [];
  loading: boolean = false;
  onTextChange: (value: string) => void = (_value: string) => {};
  onSave: () => void = () => {};

  build() {
    Column({ space: 10 }) {
      Text(uiText(this.title))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(themePrimaryText())
        .width('100%')
      Text(uiText(this.summary))
        .fontSize(12)
        .fontColor(themeSecondaryText())
        .lineHeight(18)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Column({ space: 8 }) {
        TextInput({ text: this.text, placeholder: uiText(this.placeholder) })
          .height(38)
          .fontSize(14)
          .fontColor(themePrimaryText())
          .placeholderColor(themeTertiaryText())
          .backgroundColor(themeFieldBackground())
          .borderRadius(6)
          .padding({ left: 10, right: 10 })
          .onChange((value: string) => {
            this.onTextChange(value);
          })
        Button(uiText('Save'), { type: ButtonType.Normal, stateEffect: true })
          .fontSize(13)
          .fontColor(themeOnPrimaryText())
          .backgroundColor(themePrimaryColor())
          .borderRadius(6)
          .height(36)
          .width('100%')
          .enabled(!this.loading && this.text.trim().length > 0)
          .onClick(() => {
            this.onSave();
          })
      }
      .width('100%')

      if (this.tags.length === 0) {
        Text(uiText('No tags'))
          .fontSize(12)
          .fontColor(themeTertiaryText())
          .width('100%')
          .padding(10)
          .backgroundColor(themeSurfaceVariant())
          .borderRadius(6)
      } else {
        ForEach(this.tags, (tag: MyTagItem) => {
          MyTagRow({ tag: tag })
        }, (tag: MyTagItem) => tag.id.toString())
      }
    }
    .padding(12)
    .width('100%')
    .backgroundColor(themeSurface())
    .borderRadius(6)
  }
}

@Component
struct MyTagRow {
  tag: MyTagItem = { id: 0, tag: '', watched: false, hidden: false, color: '', weight: '10' };

  build() {
    Row() {
      Text(this.tag.tag)
        .fontSize(13)
        .fontColor(themePrimaryText())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text('#' + this.tag.id.toString())
        .fontSize(11)
        .fontColor(themeTertiaryText())
        .margin({ left: 6 })
    }
    .width('100%')
    .height(44)
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor(themeSurfaceVariant())
    .borderRadius(6)
  }
}

function cloneTags(tags: MyTagItem[]): MyTagItem[] {
  const result: MyTagItem[] = [];
  for (let i = 0; i < tags.length; i++) {
    result.push({
      id: tags[i].id,
      tag: tags[i].tag,
      watched: tags[i].watched,
      hidden: tags[i].hidden,
      color: tags[i].color,
      weight: tags[i].weight
    });
  }
  return result;
}
