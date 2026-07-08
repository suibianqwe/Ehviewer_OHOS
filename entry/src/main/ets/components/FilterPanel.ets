import {
  FilterRule,
  FILTER_MODE_RATING,
  FILTER_MODE_TAG,
  FILTER_MODE_TAG_NAMESPACE,
  FILTER_MODE_TITLE,
  FILTER_MODE_UPLOADER
} from '../services/EhFilterStore';
import { uiText } from '../shared/EhShared';
import {
  themeDangerText,
  themeDividerColor,
  themeFieldBackground,
  themeMutedText,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSelectedBackgroundLight,
  themeSurface,
  themeSurfaceVariant,
  themeTertiaryText
} from '../shared/EhTheme';
import {
  buildSearchSuggestions,
  RatingStarBar,
  SearchSuggestionItem,
  SearchSuggestionList,
  SearchSummaryStrip
} from './GallerySearchScenes';
import { SettingsSubToolbar } from './SessionSettingsScenes';

@Component
export struct FilterPanel {
  @Prop @Watch('onRulesChanged') rules: FilterRule[] = [];
  @Prop @Watch('onNewTextChanged') newText: string = '';
  @Prop @Watch('onNewModeChanged') newMode: number = FILTER_MODE_TITLE;
  @State displayRules: FilterRule[] = [];
  @State draftText: string = '';
  @State draftMode: number = FILTER_MODE_TITLE;
  @State tagSuggestions: SearchSuggestionItem[] = [];
  @State selectedTagNamespaces: string[] = [];
  @State suggestionRevision: number = 0;
  onBack: () => void = () => {};
  onNewModeChange: (mode: number) => void = () => {};
  onAddText: (mode: number, text: string) => boolean = (_mode: number, _text: string) => false;
  onRatingSelect: (level: number) => void = (_level: number) => {};
  onRemove: (id: number) => void = () => {};
  onToggle: (id: number) => void = () => {};

  aboutToAppear(): void {
    this.syncAllProps();
  }

  onRulesChanged(): void {
    this.displayRules = cloneFilterRules(this.rules);
  }

  onNewTextChanged(): void {
    if (this.draftText.length === 0 || this.newText.length === 0) {
      this.draftText = this.newText;
      this.refreshTagSuggestions();
    }
  }

  onNewModeChanged(): void {
    this.draftMode = this.newMode;
    this.refreshTagSuggestions();
  }

  private syncAllProps(): void {
    this.displayRules = cloneFilterRules(this.rules);
    this.draftText = this.newText;
    this.draftMode = this.newMode;
    this.refreshTagSuggestions();
  }

  private filterModeName(mode: number): string {
    if (mode === FILTER_MODE_UPLOADER) {
      return uiText('Uploader');
    }
    if (mode === FILTER_MODE_TAG) {
      return uiText('Tag');
    }
    if (mode === FILTER_MODE_TAG_NAMESPACE) {
      return uiText('Namespaced tag');
    }
    if (mode === FILTER_MODE_RATING) {
      return uiText('Rating');
    }
    return uiText('Title');
  }

  private inputPlaceholder(): string {
    if (this.draftMode === FILTER_MODE_UPLOADER) {
      return uiText('Uploader');
    }
    if (this.draftMode === FILTER_MODE_TAG) {
      return uiText('Tag');
    }
    if (this.draftMode === FILTER_MODE_TAG_NAMESPACE) {
      return 'female:yuri';
    }
    return uiText('Title');
  }

  private modeValues(): number[] {
    return [FILTER_MODE_TITLE, FILTER_MODE_UPLOADER, FILTER_MODE_TAG, FILTER_MODE_TAG_NAMESPACE, FILTER_MODE_RATING];
  }

  private tagModeActive(): boolean {
    return this.draftMode === FILTER_MODE_TAG || this.draftMode === FILTER_MODE_TAG_NAMESPACE;
  }

  private selectedTagNamespaceKey(): string {
    return this.selectedTagNamespaces.slice().sort().join('|');
  }

  private suggestionListHeight(): number {
    if (this.tagSuggestions.length <= 0) {
      return 0;
    }
    if (this.tagSuggestions.length <= 2) {
      return 62;
    }
    if (this.tagSuggestions.length <= 6) {
      return 174;
    }
    return 280;
  }

  private currentRatingLevel(): number {
    for (let i = 0; i < this.displayRules.length; i++) {
      const rule = this.displayRules[i];
      if (rule.mode === FILTER_MODE_RATING && rule.enabled) {
        const value = Number.parseInt(rule.text);
        if (!Number.isNaN(value) && value > 1) {
          return Math.max(1, Math.min(5, value));
        }
      }
    }
    return 1;
  }

  private updateDraftText(value: string): void {
    this.draftText = value;
    this.refreshTagSuggestions();
  }

  private updateDraftMode(mode: number): void {
    this.draftMode = mode;
    this.onNewModeChange(mode);
    this.refreshTagSuggestions();
  }

  private toggleTagNamespace(namespace: string): void {
    const next = this.selectedTagNamespaces.slice();
    const index = next.indexOf(namespace);
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(namespace);
    }
    this.selectedTagNamespaces = next;
    this.refreshTagSuggestions();
  }

  private refreshTagSuggestions(): void {
    if (!this.tagModeActive()) {
      this.tagSuggestions = [];
      this.suggestionRevision++;
      return;
    }
    const text = this.draftText.trim();
    if (activeFilterTagText(text).length < 2) {
      this.tagSuggestions = [];
      this.suggestionRevision++;
      return;
    }
    this.tagSuggestions = cloneSuggestions(buildSearchSuggestions(text, 0, this.selectedTagNamespaces)
      .filter((item: SearchSuggestionItem) => item.kind === 'tag'));
    this.suggestionRevision++;
  }

  private applyTagSuggestion(suggestion: SearchSuggestionItem): void {
    if (suggestion.kind !== 'tag') {
      return;
    }
    this.updateDraftText(suggestion.query);
  }

  private submitTextRule(): void {
    if (this.onAddText(this.draftMode, this.draftText)) {
      this.draftText = '';
      this.refreshTagSuggestions();
    }
  }

  @Builder
  private modeTabs() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.modeValues(), (mode: number) => {
          FilterModeTab({
            label: this.filterModeName(mode),
            selected: this.draftMode === mode,
            onTap: () => {
              this.updateDraftMode(mode);
            }
          })
        }, (mode: number) => mode.toString())
      }
      .padding({ left: 2, right: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  private textFilterEditor() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        TextInput({ text: this.draftText, placeholder: this.inputPlaceholder() })
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor(themePrimaryText())
          .placeholderColor(themeTertiaryText())
          .backgroundColor(themeFieldBackground())
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.updateDraftText(value);
          })
          .onSubmit(() => {
            this.submitTextRule();
          })
          .onFocus(() => {
            this.refreshTagSuggestions();
          })
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(22)
            .fontColor([Color.White])
        }
        .width(44)
        .height(44)
        .padding(0)
        .borderRadius(22)
        .backgroundColor(themePrimaryColor())
        .onClick(() => {
          this.submitTextRule();
        })
      }
      .width('100%')

      if (this.tagModeActive() && this.draftText.trim().length > 0) {
        SearchSummaryStrip({
          selectedTagNamespaces: this.selectedTagNamespaces,
          selectedTagNamespaceKey: this.selectedTagNamespaceKey(),
          revision: this.suggestionRevision,
          onToggleTagNamespace: (namespace: string) => {
            this.toggleTagNamespace(namespace);
          }
        })
      }

      if (this.tagModeActive() && this.tagSuggestions.length > 0) {
        SearchSuggestionList({
          suggestions: this.tagSuggestions,
          revision: this.suggestionRevision,
          onSelect: (suggestion: SearchSuggestionItem) => {
            this.applyTagSuggestion(suggestion);
          }
        })
        .width('100%')
        .height(this.suggestionListHeight())
      }
    }
    .width('100%')
  }

  @Builder
  private ratingFilterEditor() {
    Column({ space: 10 }) {
      Text(uiText('Rating'))
        .fontSize(13)
        .fontColor(themeSecondaryText())
        .width('100%')
      RatingStarBar({
        level: this.currentRatingLevel(),
        onSelect: (level: number) => {
          this.onRatingSelect(level);
        }
      })
    }
    .width('100%')
  }

  @Builder
  private editorCard() {
    Column({ space: 14 }) {
      this.modeTabs()
      if (this.draftMode === FILTER_MODE_RATING) {
        this.ratingFilterEditor()
      } else {
        this.textFilterEditor()
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(themeSurface())
    .borderRadius(8)
  }

  @Builder
  private rulesContent() {
    if (this.displayRules.length === 0) {
      EmptyFilterCard()
    } else {
      Column({ space: 10 }) {
        ForEach(this.displayRules, (rule: FilterRule) => {
          FilterRuleCard({
            rule: rule,
            modeLabel: this.filterModeName(rule.mode),
            onToggle: () => {
              this.onToggle(rule.id);
            },
            onRemove: () => {
              this.onRemove(rule.id);
            }
          })
        }, (rule: FilterRule) => rule.id.toString() + ':' + rule.enabled.toString() + ':' + rule.text)
      }
      .width('100%')
    }
  }

  build() {
    Column() {
      SettingsSubToolbar({
        title: uiText('Filter rules'),
        onBack: this.onBack
      })

      Scroll() {
        Column({ space: 14 }) {
          this.editorCard()
          this.rulesContent()
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 14, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor(themePageBackground())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}

@Component
struct FilterModeTab {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  onTap: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(13)
      .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.selected ? Color.White : themePrimaryText())
      .height(34)
      .padding({ left: 14, right: 14 })
      .backgroundColor(this.selected ? themePrimaryColor() : themeSurfaceVariant())
      .borderRadius(17)
      .onClick(() => {
        this.onTap();
      })
  }
}

@Component
struct FilterRuleCard {
  @Prop rule: FilterRule = { id: 0, mode: FILTER_MODE_TITLE, text: '', enabled: true };
  @Prop modeLabel: string = '';
  onToggle: () => void = () => {};
  onRemove: () => void = () => {};

  build() {
    Row({ space: 10 }) {
      Column({ space: 5 }) {
        Text(this.rule.text)
          .fontSize(15)
          .fontWeight(this.rule.enabled ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.rule.enabled ? themePrimaryText() : themeMutedText())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 8 }) {
          Text(this.modeLabel)
            .fontSize(11)
            .fontColor(themeSecondaryText())
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(themeFieldBackground())
            .borderRadius(10)
          Text(this.rule.enabled ? uiText('On') : uiText('Off'))
            .fontSize(11)
            .fontColor(this.rule.enabled ? themePrimaryColor() : themeMutedText())
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph(this.rule.enabled ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.xmark'))
          .fontSize(21)
          .fontColor([this.rule.enabled ? themePrimaryColor() : themeMutedText()])
      }
      .width(38)
      .height(38)
      .padding(0)
      .borderRadius(19)
      .backgroundColor(this.rule.enabled ? themeSelectedBackgroundLight() : themeSurfaceVariant())
      .onClick(() => {
        this.onToggle();
      })

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(20)
          .fontColor([themeDangerText()])
      }
      .width(38)
      .height(38)
      .padding(0)
      .borderRadius(19)
      .backgroundColor(themeSurfaceVariant())
      .onClick(() => {
        this.onRemove();
      })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(themeSurface())
    .borderRadius(8)
    .border({ width: 1, color: themeDividerColor() })
  }
}

@Component
struct EmptyFilterCard {
  build() {
    Column({ space: 8 }) {
      Text(uiText('No filters'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(themePrimaryText())
      Text(uiText('Add a filter rule above to hide matching galleries from lists.'))
        .fontSize(13)
        .fontColor(themeSecondaryText())
        .textAlign(TextAlign.Center)
        .lineHeight(19)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 28, bottom: 28 })
    .backgroundColor(themeSurface())
    .borderRadius(8)
    .border({ width: 1, color: themeDividerColor() })
  }
}

function cloneFilterRules(rules: FilterRule[]): FilterRule[] {
  const next: FilterRule[] = [];
  for (let i = 0; i < rules.length; i++) {
    next.push({
      id: rules[i].id,
      mode: rules[i].mode,
      text: rules[i].text,
      enabled: rules[i].enabled
    });
  }
  return next;
}

function cloneSuggestions(suggestions: SearchSuggestionItem[]): SearchSuggestionItem[] {
  const result: SearchSuggestionItem[] = [];
  for (let i = 0; i < suggestions.length; i++) {
    result.push({
      kind: suggestions[i].kind,
      title: suggestions[i].title,
      subtitle: suggestions[i].subtitle,
      query: suggestions[i].query,
      translated: suggestions[i].translated,
      namespace: suggestions[i].namespace
    });
  }
  return result;
}

function activeFilterTagText(text: string): string {
  const trimmed = text.trim();
  const colon = trimmed.indexOf(':');
  return colon < 0 ? trimmed : trimmed.substring(colon + 1).trim();
}
