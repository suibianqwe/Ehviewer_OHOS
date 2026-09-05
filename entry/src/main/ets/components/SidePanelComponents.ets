import { LANGUAGE_REVISION_KEY, THEME_REVISION_KEY, uiText } from '../shared/EhShared';
import {
  themeDangerText,
  themeFieldBackground,
  themeMaterialContentColor,
  themePrimaryText,
  themeSecondaryText,
  themeSelectedBackground,
  themeSelectedBackgroundLight,
  themeSelectedText,
  themeShadowColor,
  themeSurface,
  themeSurfaceVariant,
  themeTransparentColor
} from '../shared/EhTheme';
import {
  uiButtonMaterial,
  uiButtonHighlightBorderColor,
  uiCardRadius,
  uiControlRadius,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiPanelRadius,
  uiPillRadius,
  uiPopupEffectBackground,
  uiPopupBlurOptions,
  uiPopupBlurStyle,
  uiSearchFieldHeight,
  uiInputFieldBorder,
  uiSearchMaterial
} from '../shared/EhUiStyle';
import { PopupScrim } from './PopupScrim';

function sidePanelChromeText(): string {
  return themeMaterialContentColor();
}

function sidePanelChromeBackground(): ResourceColor {
  return Color.Transparent;
}

export const SIDE_PANEL_WIDTH: number = 288;

export function sidePanelLeft(contentWidth: number, fallbackWidth: number): number {
  const width = contentWidth > 0 ? contentWidth : fallbackWidth;
  return Math.max(0, width - SIDE_PANEL_WIDTH);
}

export function shouldOpenSidePanel(event: GestureEvent | undefined): boolean {
  if (event === undefined) {
    return false;
  }
  const distanceX = event.offsetX;
  const distanceY = Math.abs(event.offsetY);
  return distanceX < -72 && distanceY < Math.max(48, Math.abs(distanceX) * 0.7) && event.velocityX <= 80;
}

@Component
export struct RightSidePanelLayer {
  @Prop layerWidth: number = 0;
  @Prop drawerLeft: number = 0;
  @Prop drawerOffsetX: number = SIDE_PANEL_WIDTH;
  @Prop overlayOpacity: number = 0;
  @Prop layerZIndex: number = 15;
  onClose: () => void = () => {};
  @BuilderParam content: () => void = this.EmptyContent;
  @StorageProp(THEME_REVISION_KEY) themeRevision: number = 0;

  @Builder
  private EmptyContent() {
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PopupScrim({
        showCutout: true,
        positionedCutout: true,
        cutoutX: this.drawerLeft + this.drawerOffsetX,
        cutoutY: 0,
        cutoutWidth: SIDE_PANEL_WIDTH,
        cutoutHeight: '100%',
        cutoutRadius: 0,
        scrimOpacity: this.overlayOpacity,
        onDismiss: () => {
          this.onClose();
        }
      })
        .gesture(
          PanGesture({ fingers: 1, direction: PanDirection.Right, distance: 28 })
            .onActionEnd(() => {
              this.onClose();
            })
        )

      Column() {
        this.content()
      }
      .width(SIDE_PANEL_WIDTH)
      .height('100%')
      .backgroundColor(uiPopupEffectBackground(themeSurface()))
      .backgroundBlurStyle(uiPopupBlurStyle(), uiPopupBlurOptions())
      .position({ x: this.drawerLeft, y: 0 })
      .translate({ x: this.drawerOffsetX })
      .shadow({ radius: 32, color: themeShadowColor(), offsetX: -8, offsetY: 0 })
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Right, distance: 28 })
          .onActionEnd(() => {
            this.onClose();
          })
      )
    }
    .width(this.layerWidth > 0 ? this.layerWidth : '100%')
    .height('100%')
    .clip(true)
    .zIndex(this.layerZIndex)
  }
}

@Component
export struct SidePanelManagerHeader {
  @Prop statusBarHeight: number = 0;
  @Prop title: string = '';
  @Prop showAdd: boolean = false;
  onBack: () => void = () => {};
  onAdd: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    Column() {
      Column()
        .width('100%')
        .height(this.statusBarHeight)
        .backgroundColor(sidePanelChromeBackground())

      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([sidePanelChromeText()])
        }
        .width(40)
        .height(40)
        .backgroundColor(sidePanelChromeBackground())
        .systemMaterial(uiButtonMaterial())
        .border({ width: 1, color: uiButtonHighlightBorderColor() })
        .onClick(() => {
          this.onBack();
        })

        Text(uiText(this.title))
          .fontSize(19)
          .fontWeight(FontWeight.Medium)
          .fontColor(sidePanelChromeText())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 12 })

        if (this.showAdd) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(20)
              .fontColor([sidePanelChromeText()])
          }
          .width(40)
          .height(40)
          .backgroundColor(sidePanelChromeBackground())
          .systemMaterial(uiButtonMaterial())
          .border({ width: 1, color: uiButtonHighlightBorderColor() })
          .onClick(() => {
            this.onAdd();
          })
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
      .backgroundColor(sidePanelChromeBackground())
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }
}

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
        .backgroundColor(sidePanelChromeBackground())

      Row() {
        Text(uiText(this.title))
          .fontSize(19)
          .fontWeight(FontWeight.Medium)
          .fontColor(sidePanelChromeText())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.showFirstAction) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph(this.firstActionIcon)
              .fontSize(20)
              .fontColor([sidePanelChromeText()])
          }
          .width(40)
          .height(40)
          .backgroundColor(sidePanelChromeBackground())
          .systemMaterial(uiButtonMaterial())
          .border({ width: 1, color: uiButtonHighlightBorderColor() })
          .margin({ right: this.showSecondAction ? 6 : 0 })
          .onClick(() => {
            this.onFirstAction();
          })
        }

        if (this.showSecondAction) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph(this.secondActionIcon)
              .fontSize(20)
              .fontColor([sidePanelChromeText()])
          }
          .width(40)
          .height(40)
          .backgroundColor(sidePanelChromeBackground())
          .systemMaterial(uiButtonMaterial())
          .border({ width: 1, color: uiButtonHighlightBorderColor() })
          .onClick(() => {
            this.onSecondAction();
          })
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 18, right: 12 })
      .backgroundColor(sidePanelChromeBackground())
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
      .borderRadius(uiCardRadius(10))
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
        .systemMaterial(uiButtonMaterial())
        .border({ width: 1, color: uiButtonHighlightBorderColor() })
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

@Component
export struct SidePanelEditableManagerRow {
  @Prop rowId: string = '';
  @Prop @Watch('onValueChanged') value: string = '';
  @Prop placeholder: string = '';
  @Prop subtitle: string = '';
  @Prop editing: boolean = false;
  onStartEdit: () => void = () => {};
  onFinishEdit: () => void = () => {};
  onValueChange: (value: string) => void = (_value: string) => {};
  onCommit: (value: string) => void = (_value: string) => {};
  onDelete: () => void = () => {};
  @State draftValue: string = '';
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  private finishPending: boolean = false;

  aboutToAppear(): void {
    this.draftValue = this.value;
  }

  onValueChanged(): void {
    this.draftValue = this.value;
  }

  private inputFocusId(): string {
    let hash = 0;
    for (let index = 0; index < this.rowId.length; index++) {
      hash = ((hash * 31) + this.rowId.charCodeAt(index)) | 0;
    }
    return 'side-panel-manager-input-' + Math.abs(hash).toString();
  }

  private finishEditing(): void {
    if (this.finishPending) {
      return;
    }
    this.finishPending = true;
    this.onCommit(this.draftValue);
    this.onFinishEdit();
    setTimeout(() => {
      this.finishPending = false;
    }, 0);
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Column() {
          Text('≡')
            .fontSize(22)
            .fontColor(themeSecondaryText())
        }
        .width(38)
        .height(38)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(themeSurfaceVariant())
        .borderRadius(uiPillRadius(19))

        if (this.editing) {
          TextInput({ text: this.draftValue, placeholder: uiText(this.placeholder) })
            .id(this.inputFocusId())
            .defaultFocus(true)
            .onAppear(() => {
              focusControl.requestFocus(this.inputFocusId());
            })
            .height(uiSearchFieldHeight())
            .layoutWeight(1)
            .fontSize(14)
            .fontColor(uiMaterialForegroundColor(themePrimaryText()))
            .backgroundColor(uiMaterialBackground(themeFieldBackground()))
            .systemMaterial(uiSearchMaterial())
            .border(uiInputFieldBorder())
            .borderRadius(uiPillRadius(uiSearchFieldHeight() / 2))
            .padding({ left: 10, right: 10 })
            .onChange((value: string) => {
              this.draftValue = value;
              this.onValueChange(value);
            })
            .onSubmit(() => {
              this.finishEditing();
            })
            .onBlur(() => {
              this.finishEditing();
            })
        } else {
          Row() {
            Text(this.draftValue.length > 0 ? this.draftValue : uiText(this.placeholder))
              .fontSize(14)
              .fontColor(this.draftValue.length > 0 ? themePrimaryText() : themeSecondaryText())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .height(38)
          .layoutWeight(1)
          .padding({ left: 10, right: 10 })
          .backgroundColor(themeFieldBackground())
          .borderRadius(uiControlRadius(8))
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.onStartEdit();
          })
        }

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(18)
            .fontColor([themeDangerText()])
        }
        .width(38)
        .height(38)
        .backgroundColor(themeSurfaceVariant())
        .systemMaterial(uiButtonMaterial())
        .border({ width: 1, color: uiButtonHighlightBorderColor() })
        .onClick(() => {
          this.onDelete();
        })
      }
      .width('100%')

      if (this.subtitle.length > 0) {
        Text(uiText(this.subtitle))
          .fontSize(12)
          .fontColor(themeSecondaryText())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(themeSurface())
    .borderRadius(uiPanelRadius(8))
  }
}
