import { GalleryTagGroup } from '../../model/GalleryModels';
import { ehTagTranslationStore } from '../../services/EhTagTranslationStore';
import { shouldUseChineseUi, uiText } from '../../shared/EhShared';
import { themePrimaryText, themeSecondaryText, themeSurface, themeSurfaceVariant } from '../../shared/EhTheme';

@Component
export struct DetailTags {
  @Prop tags: GalleryTagGroup[] = [];
  @Prop isDetailLoaded: boolean = false;
  onTagSearch: (namespace: string, tag: string) => void = (_namespace: string, _tag: string) => {};

  build() {
    Column() {
      Text(uiText('Tags'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(themePrimaryText())
        .width('100%')
      if (!this.isDetailLoaded) {
        Text(uiText('Loading tags...'))
          .fontSize(12)
          .fontColor(themeSecondaryText())
          .margin({ top: 8 })
      } else if (this.tags.length === 0) {
        Text(uiText('No tags parsed'))
          .fontSize(12)
          .fontColor(themeSecondaryText())
          .margin({ top: 8 })
      } else {
        Column({ space: 4 }) {
          ForEach(this.tags, (group: GalleryTagGroup) => {
            TagGroupRow({
              namespace: group.namespace,
              tags: group.tags,
              onTagSearch: (namespace: string, tag: string) => {
                this.onTagSearch(namespace, tag);
              }
            })
          }, (group: GalleryTagGroup) => group.namespace)
        }
        .width('100%')
        .margin({ top: 8 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(themeSurface())
  }
}

@Component
export struct TagGroupRow {
  namespace: string = '';
  tags: string[] = [];
  onTagSearch: (namespace: string, tag: string) => void = (_namespace: string, _tag: string) => {};

  private tagLabel(tag: string): string {
    if (!shouldUseChineseUi()) {
      return tag;
    }
    const translated = ehTagTranslationStore.translate(this.namespace, tag);
    return translated.length > 0 ? translated : tag;
  }

  build() {
    Row() {
      Text(this.namespace)
        .fontSize(14)
        .fontColor(themeSecondaryText())
        .width(80)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.tags, (tag: string) => {
          Button(this.tagLabel(tag), { type: ButtonType.Normal, stateEffect: true })
            .height(26)
            .fontSize(12)
            .fontColor(themePrimaryText())
            .backgroundColor(themeSurfaceVariant())
            .borderRadius(4)
            .padding({ left: 8, right: 8 })
            .margin({ right: 6, bottom: 6 })
            .onClick(() => {
              this.onTagSearch(this.namespace, tag);
            })
        }, (tag: string) => this.namespace + ':' + tag)
      }
      .clip(true)
      .layoutWeight(1)
    }
    .width('100%')
  }
}
