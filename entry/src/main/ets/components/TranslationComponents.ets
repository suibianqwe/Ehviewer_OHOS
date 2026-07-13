import { ehTranslationService } from '../services/EhTranslationService';

@Component
export struct TranslationText {
  @Prop @Watch('onSourceChanged') sourceText: string = '';
  @Prop @Watch('onEnabledChanged') translationEnabled: boolean = false;
  @Prop contentKind: string = 'gallery title';
  @Prop fontSizeValue: number = 15;
  @Prop fontColorValue: ResourceColor = Color.Black;
  @Prop fontWeightValue: number = FontWeight.Regular;
  @Prop maxLinesValue: number = 3;
  @Prop lineHeightValue: number = 20;
  @Prop textAlignValue: TextAlign = TextAlign.Start;
  @Prop selectable: boolean = false;
  @State translatedText: string = '';
  private requestVersion: number = 0;

  aboutToAppear(): void {
    this.updateTranslation();
  }

  onSourceChanged(): void {
    this.updateTranslation();
  }

  onEnabledChanged(): void {
    this.updateTranslation();
  }

  private updateTranslation(): void {
    this.requestVersion++;
    const version = this.requestVersion;
    this.translatedText = '';
    if (!this.translationEnabled || this.sourceText.trim().length === 0) {
      return;
    }
    const request = this.contentKind === 'gallery comment' ?
      ehTranslationService.translateComment(this.sourceText) : ehTranslationService.translateTitle(this.sourceText);
    request.then((translated: string) => {
      if (version === this.requestVersion && this.translationEnabled) {
        this.translatedText = translated;
      }
    }).catch(() => {
      if (version === this.requestVersion) {
        this.translatedText = '';
      }
    });
  }

  private displayText(): string {
    return this.translationEnabled && this.translatedText.length > 0 ? this.translatedText : this.sourceText;
  }

  build() {
    Text(this.displayText())
      .fontSize(this.fontSizeValue)
      .fontColor(this.fontColorValue)
      .fontWeight(this.fontWeightValue)
      .lineHeight(this.lineHeightValue)
      .textAlign(this.textAlignValue)
      .maxLines(this.maxLinesValue)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .copyOption(this.selectable ? CopyOptions.LocalDevice : CopyOptions.None)
      .width('100%')
  }
}
