import { LANGUAGE_REVISION_KEY, uiText } from '../shared/EhShared';
import {
  themeOnPrimaryActionBackground,
  themeOnPrimaryText,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSelectedBackground,
  themeSelectedBackgroundLight,
  themeSelectedText,
  themeSurfaceVariant,
  themeTransparentColor
} from '../shared/EhTheme';

@Component
export struct SidePanelHeader {
  @Prop statusBarHeight: number = 0;
  @Prop title: string = '';
  @Prop showFirstAction: boolean = false;
  @Prop firstActionIcon: Resource = $r('sys.symbol.gearshape');
  @Prop showSecondAction: boolean = false;
  @Prop secondActionIcon: Resource = $r('sys.symbol.plus');
  onFirstAction: () => void = () => {};
  onSecondAction: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    Column() {
      Column()
        .width('100%')
        .height(this.statusBarHeight)
        .backgroundColor(themePrimaryColor())

      Row() {
        Text(uiText(this.title))
          .fontSize(19)
          .fontWeight(FontWeight.Medium)
          .fontColor(themeOnPrimaryText())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.showFirstAction) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph(this.firstActionIcon)
              .fontSize(20)
              .fontColor([themeOnPrimaryText()])
          }
          .width(40)
          .height(40)
          .backgroundColor(themeOnPrimaryActionBackground())
          .margin({ right: this.showSecondAction ? 6 : 0 })
          .onClick(() => {
            this.onFirstAction();
          })
        }

        if (this.showSecondAction) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph(this.secondActionIcon)
              .fontSize(20)
              .fontColor([themeOnPrimaryText()])
          }
          .width(40)
          .height(40)
          .backgroundColor(themeOnPrimaryActionBackground())
          .onClick(() => {
            this.onSecondAction();
          })
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 18, right: 12 })
      .backgroundColor(themePrimaryColor())
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }
}

@Component
export struct SidePanelRow {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop selected: boolean = false;
  @Prop icon: Resource = $r('sys.symbol.folder');
  @Prop showDelete: boolean = false;
  onTap: () => void = () => {};
  onDelete: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    Row() {
      Column() {
        SymbolGlyph(this.icon)
          .fontSize(21)
          .fontColor([this.selected ? themeSelectedText() : themeSecondaryText()])
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius(10)
      .backgroundColor(this.selected ? themeSelectedBackgroundLight() : themeSurfaceVariant())

      Column() {
        Text(uiText(this.title))
          .fontSize(15)
          .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.selected ? themeSelectedText() : themePrimaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.subtitle.length > 0) {
          Text(uiText(this.subtitle))
            .fontSize(12)
            .fontColor(themeSecondaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .wordBreak(WordBreak.BREAK_ALL)
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })

      if (this.selected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([themeSelectedText()])
      } else if (this.showDelete) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(17)
            .fontColor([themeSecondaryText()])
        }
        .width(36)
        .height(36)
        .backgroundColor(themeTransparentColor())
        .onClick(() => {
          this.onDelete();
        })
      }
    }
    .width('100%')
    .height(62)
    .padding({ left: 14, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.selected ? themeSelectedBackground() : themeTransparentColor())
    .onClick(() => {
      this.onTap();
    })
  }
}
