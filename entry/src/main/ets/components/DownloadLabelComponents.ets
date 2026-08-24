import { DownloadInfo, DownloadLabel } from '../services/EhDownloadStore';
import { LANGUAGE_REVISION_KEY, uiText } from '../shared/EhShared';
import {
  themeDividerColor,
  themeAccentTextColor,
  themeFieldBackground,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeScrimColor,
  themeSecondaryText,
  themeSelectedBackground,
  themeSelectedText,
  themeShadowColor,
  themeSurface,
  themeSurfaceVariant,
  themeTertiaryText,
  themeTransparentColor
} from '../shared/EhTheme';
import {
  uiButtonMaterial,
  uiDialogMaterial,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiRadius,
  uiSearchMaterial
} from '../shared/EhUiStyle';
import {
  SidePanelEditableManagerRow,
  SidePanelHeader,
  SidePanelManagerHeader,
  SidePanelRow
} from './SidePanelComponents';

export const DOWNLOAD_LABEL_FILTER_ALL: string = '__all__';
export const DOWNLOAD_LABEL_OPTION_ASK: string = '__ask__';

function downloadLabelItemCount(items: DownloadInfo[], label: string): number {
  if (label === DOWNLOAD_LABEL_FILTER_ALL) {
    return items.length;
  }
  let count = 0;
  for (let i = 0; i < items.length; i++) {
    if (items[i].label === label) {
      count++;
    }
  }
  return count;
}

@Component
export struct DownloadLabelDrawer {
  @Prop statusBarHeight: number = 0;
  @Prop labels: DownloadLabel[] = [];
  @Prop items: DownloadInfo[] = [];
  @Prop selectedLabel: string = DOWNLOAD_LABEL_FILTER_ALL;
  onSelect: (label: string) => void = (_label: string) => {};
  onDefaultLabel: () => void = () => {};
  onSettings: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    Column() {
      SidePanelHeader({
        statusBarHeight: this.statusBarHeight,
        title: 'Download labels',
        showFirstAction: true,
        firstActionIcon: $r('sys.symbol.arrow_down_circle'),
        showSecondAction: true,
        secondActionIcon: $r('sys.symbol.gearshape'),
        onFirstAction: () => {
          this.onDefaultLabel();
        },
        onSecondAction: () => {
          this.onSettings();
        }
      })

      List() {
        ListItem() {
          SidePanelRow({
            title: 'All',
            subtitle: downloadLabelItemCount(this.items, DOWNLOAD_LABEL_FILTER_ALL).toString(),
            selected: this.selectedLabel === DOWNLOAD_LABEL_FILTER_ALL,
            icon: $r('sys.symbol.folder'),
            onTap: () => {
              this.onSelect(DOWNLOAD_LABEL_FILTER_ALL);
            }
          })
        }

        ListItem() {
          SidePanelRow({
            title: 'Default',
            subtitle: downloadLabelItemCount(this.items, '').toString(),
            selected: this.selectedLabel === '',
            icon: $r('sys.symbol.folder'),
            onTap: () => {
              this.onSelect('');
            }
          })
        }

        ForEach(this.labels, (item: DownloadLabel) => {
          ListItem() {
            SidePanelRow({
              title: item.label,
              subtitle: downloadLabelItemCount(this.items, item.label).toString(),
              selected: this.selectedLabel === item.label,
              icon: $r('sys.symbol.folder'),
              onTap: () => {
                this.onSelect(item.label);
              }
            })
          }
          .reuseId('download-label-drawer-row')
        }, (item: DownloadLabel) => item.label + ':' + item.time.toString())
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(Color.Transparent)
      .cachedCount(6)
    }
    .width(288)
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}

@Component
export struct DownloadLabelSelectionDialog {
  @Prop title: string = 'Download labels';
  @Prop labels: DownloadLabel[] = [];
  @Prop selectedLabel: string = '';
  @Prop includeAsk: boolean = false;
  @Prop showRemember: boolean = false;
  @Prop showAddButton: boolean = false;
  @Prop panelMaxHeight: number = 680;
  onSelect: (label: string) => void = (_label: string) => {};
  onRememberChange: (remember: boolean) => void = (_remember: boolean) => {};
  onAdd: () => void = () => {};
  onClose: () => void = () => {};
  @State remember: boolean = false;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  private optionCount(): number {
    return this.labels.length + (this.includeAsk ? 2 : 1);
  }

  private listHeight(): number {
    return Math.min(this.optionCount() * 52, Math.max(156, this.panelMaxHeight - 57 - (this.showRemember ? 52 : 0)));
  }

  @Builder
  private optionRow(value: string, text: string, icon: Resource) {
    Row() {
      Column() {
        SymbolGlyph(icon)
          .fontSize(21)
          .fontColor([value === this.selectedLabel ? themeSelectedText() : themeSecondaryText()])
      }
      .width(38)
      .height(38)
      .borderRadius(uiRadius(9))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(value === this.selectedLabel ? themeSelectedBackground() : themeSurfaceVariant())

      Text(uiText(text))
        .fontSize(15)
        .fontWeight(value === this.selectedLabel ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(value === this.selectedLabel ? themeSelectedText() : themePrimaryText())
        .layoutWeight(1)
        .margin({ left: 12 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (value === this.selectedLabel) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([themeSelectedText()])
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 18, right: 18 })
    .backgroundColor(value === this.selectedLabel ? themeSelectedBackground() : themeTransparentColor())
    .onClick(() => {
      this.onSelect(value);
    })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(themeScrimColor())
        .onClick(() => {
          this.onClose();
        })

      Column() {
        Row() {
          Text(uiText(this.title))
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.showAddButton) {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(20)
                .fontColor([uiMaterialForegroundColor(themePrimaryText())])
            }
            .width(40)
            .height(40)
            .margin({ right: 8 })
            .backgroundColor(themeFieldBackground())
            .systemMaterial(uiButtonMaterial())
            .accessibilityText(uiText('New label'))
            .onClick(() => {
              this.onAdd();
            })
          }

          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(20)
              .fontColor([uiMaterialForegroundColor(themePrimaryText())])
          }
          .width(40)
          .height(40)
          .backgroundColor(themeFieldBackground())
          .systemMaterial(uiButtonMaterial())
          .onClick(() => {
            this.onClose();
          })
        }
        .width('100%')
        .height(56)
        .padding({ left: 18, right: 12 })
        .alignItems(VerticalAlign.Center)

        Divider().color(themeDividerColor()).strokeWidth(0.5)

        List() {
          if (this.includeAsk) {
            ListItem() {
              this.optionRow(DOWNLOAD_LABEL_OPTION_ASK, 'Let me select', $r('sys.symbol.list_number'))
            }
          }

          ListItem() {
            this.optionRow('', 'Default', $r('sys.symbol.folder'))
          }

          ForEach(this.labels, (item: DownloadLabel) => {
            ListItem() {
              this.optionRow(item.label, item.label, $r('sys.symbol.folder'))
            }
          }, (item: DownloadLabel) => item.label + ':' + item.time.toString())
        }
        .width('100%')
        .height(this.listHeight())
        .cachedCount(5)

        if (this.showRemember) {
          Row() {
            Text(uiText('Remember download label'))
              .fontSize(14)
              .fontColor(themePrimaryText())
              .layoutWeight(1)

            Checkbox({ name: 'remember-download-label', group: 'download-label' })
              .select(this.remember)
              .selectedColor(themeAccentTextColor())
              .onChange((value: boolean) => {
                this.remember = value;
                this.onRememberChange(value);
              })
          }
          .width('100%')
          .height(52)
          .padding({ left: 18, right: 18 })
        }
      }
      .width('78%')
      .height(this.listHeight() + 57 + (this.showRemember ? 52 : 0))
      .constraintSize({ maxWidth: 380, minWidth: 280, maxHeight: this.panelMaxHeight })
      .backgroundColor(themeSurface())
      .borderRadius(uiRadius(10))
      .shadow({ radius: 24, color: themeShadowColor(), offsetX: 0, offsetY: 8 })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct DownloadLabelEditDialog {
  @Prop title: string = 'New label';
  @Link value: string;
  onConfirm: () => void = () => {};
  onClose: () => void = () => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(themeScrimColor())
        .onClick(() => {
          this.onClose();
        })

      Column({ space: 14 }) {
        Row() {
          Text(uiText(this.title))
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .layoutWeight(1)

          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(20)
              .fontColor([uiMaterialForegroundColor(themePrimaryText())])
          }
          .width(40)
          .height(40)
          .backgroundColor(themeFieldBackground())
          .systemMaterial(uiButtonMaterial())
          .onClick(() => {
            this.onClose();
          })
        }
        .width('100%')

        TextInput({ text: this.value, placeholder: uiText('Label name') })
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontColor(uiMaterialForegroundColor(themePrimaryText()))
          .backgroundColor(uiMaterialBackground(themeFieldBackground()))
          .systemMaterial(uiSearchMaterial())
          .borderRadius(uiRadius(24))
          .onChange((value: string) => {
            this.value = value;
          })

        Button(uiText('Confirm'))
          .width('100%')
          .height(46)
          .fontSize(16)
          .fontColor(uiMaterialForegroundColor(themeSelectedText()))
          .backgroundColor(themeSelectedBackground())
          .systemMaterial(uiButtonMaterial())
          .onClick(() => {
            this.onConfirm();
          })
      }
      .width('78%')
      .constraintSize({ maxWidth: 380, minWidth: 280 })
      .padding(18)
      .backgroundColor(uiMaterialBackground(themeSurface()))
      .systemMaterial(uiDialogMaterial())
      .borderRadius(uiRadius(20))
      .shadow({ radius: 24, color: themeShadowColor(), offsetX: 0, offsetY: 8 })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct DownloadLabelManagerScene {
  @Prop labels: DownloadLabel[] = [];
  @Prop statusBarHeight: number = 0;
  onBack: () => void = () => {};
  onAdd: () => void = () => {};
  onRename: (label: string, value: string) => void = (_label: string, _value: string) => {};
  onDelete: (label: string) => void = (_label: string) => {};
  onMove: (from: number, to: number) => void = (_from: number, _to: number) => {};
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @State editingLabel: string = '';

  build() {
    Column() {
      SidePanelManagerHeader({
        statusBarHeight: this.statusBarHeight,
        title: 'Download labels',
        showAdd: true,
        onBack: () => {
          this.onBack();
        },
        onAdd: () => {
          this.onAdd();
        }
      })

      if (this.labels.length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(34)
            .fontColor([themeTertiaryText()])
          Text(uiText('No download labels'))
            .fontSize(16)
            .fontColor(themeSecondaryText())
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 8 }) {
          ListItem() {
            Row()
              .height(0)
          }

          ForEach(this.labels, (item: DownloadLabel) => {
            ListItem() {
              SidePanelEditableManagerRow({
                rowId: item.label,
                value: item.label,
                placeholder: 'Label name',
                editing: this.editingLabel === item.label,
                onStartEdit: () => {
                  this.editingLabel = item.label;
                },
                onFinishEdit: () => {
                  if (this.editingLabel === item.label) {
                    this.editingLabel = '';
                  }
                },
                onCommit: (value: string) => {
                  this.onRename(item.label, value);
                },
                onDelete: () => {
                  this.onDelete(item.label);
                }
              })
            }
          }, (item: DownloadLabel) => item.label + ':' + item.time.toString())
            .onMove((from: number, to: number) => {
              this.onMove(from, to);
            })

          ListItem() {
            Row()
              .height(0)
          }
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .padding({ left: 10, right: 10 })
        .clip(false)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}
