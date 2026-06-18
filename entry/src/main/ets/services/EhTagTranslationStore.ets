import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

export interface EhTagSuggestion {
  namespace: string;
  tag: string;
  translated: string;
  searchText: string;
}

const TAG_TRANSLATION_RAWFILE: string = 'ehtag_translations.tsv';

class EhTagTranslationStore {
  private loaded: boolean = false;
  private entries: EhTagSuggestion[] = [];

  suggest(keyword: string, limit: number = 0, namespaces: string[] = []): EhTagSuggestion[] {
    const normalized = keyword.trim().toLowerCase();
    if (normalized.length === 0) {
      return [];
    }
    this.ensureLoaded();
    const filter = normalizeNamespaces(namespaces);
    const result: EhTagSuggestion[] = [];
    const unlimited = limit <= 0;
    for (let i = 0; i < this.entries.length && (unlimited || result.length < limit); i++) {
      const entry = this.entries[i];
      if (filter.length > 0 && filter.indexOf(entry.namespace) < 0) {
        continue;
      }
      if (entry.searchText.indexOf(normalized) >= 0) {
        result.push({
          namespace: entry.namespace,
          tag: entry.tag,
          translated: entry.translated,
          searchText: entry.searchText
        });
      }
    }
    return result;
  }

  private ensureLoaded(): void {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
    if (context === undefined) {
      return;
    }
    try {
      const data = context.resourceManager.getRawFileContentSync(TAG_TRANSLATION_RAWFILE);
      const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      this.entries = this.parse(decoder.decodeToString(data, { stream: false }));
    } catch (error) {
      this.entries = [];
    }
  }

  private parse(text: string): EhTagSuggestion[] {
    const next: EhTagSuggestion[] = [];
    const lines = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      const parts = line.split('\t');
      if (parts.length < 4 || parts[1].length === 0 || parts[2].length === 0) {
        continue;
      }
      next.push({
        namespace: parts[0],
        tag: parts[1],
        translated: parts[2],
        searchText: parts[3]
      });
    }
    return next;
  }
}

export const ehTagTranslationStore = new EhTagTranslationStore();

function normalizeNamespaces(namespaces: string[]): string[] {
  const next: string[] = [];
  for (let i = 0; i < namespaces.length; i++) {
    const value = namespaces[i].trim().toLowerCase();
    if (value.length > 0 && next.indexOf(value) < 0) {
      next.push(value);
    }
  }
  return next;
}
