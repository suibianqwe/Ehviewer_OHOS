import { picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { GalleryInfo } from '../model/GalleryModels';
import {
  themeFieldBackground,
  themeDangerText,
  themeOnPrimaryText,
  themeAccentTextColor,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeShadowColor,
  themeSurface,
  themeTertiaryText,
} from '../shared/EhTheme';
import {
  uiButtonMaterial,
  uiTransparentButtonBackgroundEffect,
  uiDialogBlurOptions,
  uiDialogBlurStyle,
  uiDialogMaterial,
  uiDialogSurfaceBackground,
  uiDialogSurfaceRadius,
  uiDialogSurfaceShadow,
  uiMaterialBackground,
  uiMaterialForegroundColor,
  uiRadius,
  uiSwitchHeight,
  uiSwitchWidth,
} from '../shared/EhUiStyle';
import { PopupScrim } from './PopupScrim';
import {
  uiText,
  uiStatusText,
  createEmptyGallery,
  getAbilityContext,
  galleryDisplayTitle,
  downloadButtonText,
} from '../shared/EhShared';
import {
  copyImageSearchSourceToCache,
} from './GalleryListSupport';

@Component
export struct ImageSearchPanel {
  @Prop panelWidth: number = 320;
  @Prop panelMaxHeight: number = 420;
  onClose: () => void = () => {
  };
  onSearch: (path: string, useSimilarityScan: boolean, onlySearchCovers: boolean) => void =
    (_path: string, _useSimilarityScan: boolean, _onlySearchCovers: boolean) => {
    };
  @State selectedPath: string = '';
  @State statusText: string = 'No image selected';
  @State useSimilarityScan: boolean = true;
  @State onlySearchCovers: boolean = false;
  @State uploadOriginalPhoto: boolean = true;
  @State busy: boolean = false;

  private selectedName(): string {
    if (this.selectedPath.length === 0) {
      return uiText('No image selected');
    }
    const slash = Math.max(this.selectedPath.lastIndexOf('/'), this.selectedPath.lastIndexOf('\\'));
    return slash >= 0 ? this.selectedPath.substring(slash + 1) : this.selectedPath;
  }

  private async chooseFromAlbum(): Promise<void> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      if (this.uploadOriginalPhoto) {
        options.assetCompatibleCapability = {
          supportedHighResolution: true
        } as photoAccessHelper.AssetCompatibleCapability;
      }
      const photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const result = await photoPicker.select(options);
      if (result.photoUris.length > 0) {
        await this.usePickedUri(result.photoUris[0], result.isOriginalPhoto);
      }
    } catch (error) {
      this.busy = false;
      this.statusText = 'Image selection failed';
    }
  }

  private async chooseFromFile(): Promise<void> {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Ability context is not ready';
      return;
    }
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = [uiText('Images') + '(.jpg,.jpeg,.png,.webp,.gif)|.jpg,.jpeg,.png,.webp,.gif'];
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris = await documentPicker.select(options);
      if (uris.length > 0) {
        await this.usePickedUri(uris[0], true);
      }
    } catch (error) {
      this.busy = false;
      this.statusText = 'Image selection failed';
    }
  }

  private async usePickedUri(uri: string, isOriginalPhoto: boolean): Promise<void> {
    this.busy = true;
    this.statusText = 'Preparing image...';
    const path = await copyImageSearchSourceToCache(uri);
    this.busy = false;
    if (path.length === 0) {
      this.statusText = 'Image selection failed';
      return;
    }
    this.selectedPath = path;
    this.statusText = isOriginalPhoto ? 'Original image selected' : 'Compatible image selected';
  }

  private submit(): void {
    if (this.selectedPath.length === 0 || this.busy) {
      this.statusText = 'No image selected';
      return;
    }
    this.onSearch(this.selectedPath, this.useSimilarityScan, this.onlySearchCovers);
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Row() {
          Text(uiText('Image search'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([uiMaterialForegroundColor(themePrimaryText())])
          }
          .width(34)
          .height(34)
          .backgroundColor(uiMaterialBackground(themeFieldBackground()))
          .backgroundEffect(uiTransparentButtonBackgroundEffect())
          .systemMaterial(uiButtonMaterial())
          .onClick(() => {
            this.onClose();
          })
        }
        .width('100%')

        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(18)
                .fontColor([uiMaterialForegroundColor(themeOnPrimaryText())])
              Text(uiText('From album'))
                .fontSize(13)
                .fontColor(uiMaterialForegroundColor(themeOnPrimaryText()))
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .width('100%')
          }
          .height(38)
          .layoutWeight(1)
          .borderRadius(uiRadius(6))
          .backgroundColor(uiMaterialBackground(themePrimaryColor()))
          .enabled(!this.busy)
          .backgroundEffect(uiTransparentButtonBackgroundEffect())
          .systemMaterial(uiButtonMaterial())
          .onClick(() => {
            this.chooseFromAlbum();
          })

          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.folder'))
                .fontSize(18)
                .fontColor([uiMaterialForegroundColor(themeAccentTextColor())])
              Text(uiText('From file'))
                .fontSize(13)
                .fontColor(uiMaterialForegroundColor(themeAccentTextColor()))
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .width('100%')
          }
          .height(38)
          .layoutWeight(1)
          .borderRadius(uiRadius(6))
          .backgroundColor(uiMaterialBackground(themeFieldBackground()))
          .enabled(!this.busy)
          .backgroundEffect(uiTransparentButtonBackgroundEffect())
          .systemMaterial(uiButtonMaterial())
          .onClick(() => {
            this.chooseFromFile();
          })
        }
        .width('100%')

        Column({ space: 4 }) {
          Text(uiText('Selected image'))
            .fontSize(12)
            .fontColor(themeSecondaryText())
          Text(this.selectedName())
            .fontSize(13)
            .fontColor(this.selectedPath.length > 0 ? themePrimaryText() : themeTertiaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding(10)
        .backgroundColor(themeFieldBackground())
        .borderRadius(uiRadius(6))

        Row() {
          Text(uiText('Upload original image'))
            .fontSize(14)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.uploadOriginalPhoto })
            .width(uiSwitchWidth())
            .height(uiSwitchHeight())
            .selectedColor(themeAccentTextColor())
            .switchPointColor(Color.White)
            .onChange((isOn: boolean) => {
              this.uploadOriginalPhoto = isOn;
            })
        }
        .width('100%')

        Row() {
          Text(uiText('Similarity scan'))
            .fontSize(14)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.useSimilarityScan })
            .width(uiSwitchWidth())
            .height(uiSwitchHeight())
            .selectedColor(themeAccentTextColor())
            .switchPointColor(Color.White)
            .onChange((isOn: boolean) => {
              this.useSimilarityScan = isOn;
            })
        }
        .width('100%')

        Row() {
          Text(uiText('Only cover search'))
            .fontSize(14)
            .fontColor(themePrimaryText())
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.onlySearchCovers })
            .width(uiSwitchWidth())
            .height(uiSwitchHeight())
            .selectedColor(themeAccentTextColor())
            .switchPointColor(Color.White)
            .onChange((isOn: boolean) => {
              this.onlySearchCovers = isOn;
            })
        }
        .width('100%')

        Text(uiStatusText(this.statusText))
          .fontSize(12)
          .fontColor(this.statusText === 'Image selection failed' ? themeDangerText() : themeSecondaryText())
          .width('100%')
          .maxLines(2)

        Button(uiText('Search image'))
          .height(40)
          .width('100%')
          .fontSize(14)
          .fontColor(uiMaterialForegroundColor(themeOnPrimaryText()))
          .backgroundColor(uiMaterialBackground(themePrimaryColor()))
          .enabled(this.selectedPath.length > 0 && !this.busy)
          .borderRadius(uiRadius(6))
          .backgroundEffect(uiTransparentButtonBackgroundEffect())
          .systemMaterial(uiButtonMaterial())
          .onClick(() => {
            this.submit();
          })
      }
      .width('100%')
      .padding(14)
    }
    .width(this.panelWidth)
    .constraintSize({ maxHeight: this.panelMaxHeight })
    .backgroundColor(themeSurface())
    .borderRadius(uiRadius(8))
    .shadow({ radius: 14, color: themeShadowColor(), offsetX: 0, offsetY: 4 })
  }
}

@Component
export struct GalleryCardActionOverlay {
  @State popupWidth: number = 0;
  @State popupHeight: number = 0;
  @Prop gallery: GalleryInfo = createEmptyGallery();
  @Prop isHistory: boolean = false;
  @Prop isFavorite: boolean = false;
  onDismiss: () => void = () => {
  };
  onShare: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  onDownload: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  onDeleteHistory: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };
  onRemoveFavorite: (gallery: GalleryInfo) => void = (_gallery: GalleryInfo) => {
  };

  @Builder
  private actionRow(label: string, symbolIcon: Resource, color: string, onTap: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row() {
        SymbolGlyph(symbolIcon)
          .fontSize(20)
          .fontColor([uiMaterialForegroundColor(color)])
        Text(uiText(label))
          .fontSize(15)
          .fontColor(uiMaterialForegroundColor(color))
          .margin({ left: 12 })
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height(48)
    .backgroundColor(uiMaterialBackground(Color.Transparent))
    .borderRadius(0)
    .backgroundEffect(uiTransparentButtonBackgroundEffect())
    .systemMaterial(uiButtonMaterial())
    .onClick(onTap)
  }

  @Builder
  private divider() {
    Divider()
      .height(1)
      .color(themeFieldBackground())
      .margin({ left: 16, right: 16 })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      PopupScrim({
        showCutout: this.popupWidth > 0 && this.popupHeight > 0,
        cutoutWidth: this.popupWidth,
        cutoutHeight: this.popupHeight,
        cutoutRadius: uiDialogSurfaceRadius(),
        onDismiss: () => {
          this.onDismiss();
        }
      })

      Column({ space: 0 }) {
        Text(galleryDisplayTitle(this.gallery))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(themePrimaryText())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 10 })

        this.divider()

        this.actionRow('Share', $r('sys.symbol.share'), themePrimaryText(), () => {
          this.onShare(this.gallery);
        })

        this.divider()

        this.actionRow(downloadButtonText(this.gallery.gid), $r('sys.symbol.arrow_down_circle'), themePrimaryText(), () => {
          this.onDownload(this.gallery);
        })

        if (this.isHistory) {
          this.divider()

          this.actionRow('Delete history', $r('sys.symbol.trash'), themeDangerText(), () => {
            this.onDeleteHistory(this.gallery);
          })
        }

        if (this.isFavorite) {
          this.divider()

          this.actionRow('Remove from favorites', $r('sys.symbol.trash'), themeDangerText(), () => {
            this.onRemoveFavorite(this.gallery);
          })
        }
      }
      .width('78%')
      .constraintSize({ maxWidth: 360 })
      .padding({ top: 4, bottom: 6 })
      .backgroundColor(uiMaterialBackground(uiDialogSurfaceBackground()))
      .shadow(uiDialogSurfaceShadow())
      .clip(true)
      .borderRadius(uiDialogSurfaceRadius())
      .backgroundBlurStyle(uiDialogBlurStyle(), uiDialogBlurOptions())
      .systemMaterial(uiDialogMaterial())
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.popupWidth = Number.parseFloat(newArea.width.toString());
        this.popupHeight = Number.parseFloat(newArea.height.toString());
      })
    }
    .width('100%')
    .height('100%')
  }
}
