export interface SavedTranslationApi {
  name: string;
  baseUrl: string;
  apiKey: string;
  model: string;
}

interface StoredTranslationApi {
  name?: string;
  baseUrl?: string;
  apiKey?: string;
  model?: string;
}

export function parseSavedTranslationApis(raw: string): SavedTranslationApi[] {
  if (raw.trim().length === 0) {
    return [];
  }
  try {
    const parsed = JSON.parse(raw) as StoredTranslationApi[];
    if (!Array.isArray(parsed)) {
      return [];
    }
    const result: SavedTranslationApi[] = [];
    for (let i = 0; i < parsed.length; i++) {
      const item = parsed[i];
      if (typeof item.name !== 'string' || item.name.trim().length === 0 ||
        typeof item.baseUrl !== 'string' || typeof item.apiKey !== 'string' || typeof item.model !== 'string') {
        continue;
      }
      const name = uniqueTranslationApiName(result, item.name.trim());
      result.push({
        name: name,
        baseUrl: item.baseUrl.trim(),
        apiKey: item.apiKey,
        model: item.model.trim()
      });
    }
    return result;
  } catch (_error) {
    return [];
  }
}

export function serializeSavedTranslationApis(items: SavedTranslationApi[]): string {
  return JSON.stringify(items);
}

export function cloneSavedTranslationApis(items: SavedTranslationApi[]): SavedTranslationApi[] {
  const result: SavedTranslationApi[] = [];
  for (let i = 0; i < items.length; i++) {
    result.push({
      name: items[i].name,
      baseUrl: items[i].baseUrl,
      apiKey: items[i].apiKey,
      model: items[i].model
    });
  }
  return result;
}

export function findSavedTranslationApi(items: SavedTranslationApi[], name: string): SavedTranslationApi | null {
  for (let i = 0; i < items.length; i++) {
    if (items[i].name === name) {
      return items[i];
    }
  }
  return items.length > 0 ? items[0] : null;
}

export function uniqueTranslationApiName(items: SavedTranslationApi[], preferred: string,
  currentName: string = ''): string {
  const base = preferred.trim().length > 0 ? preferred.trim() : 'Custom API';
  let candidate = base;
  let suffix = 2;
  while (translationApiNameExists(items, candidate, currentName)) {
    candidate = base + ' ' + suffix.toString();
    suffix++;
  }
  return candidate;
}

export function createSavedTranslationApi(items: SavedTranslationApi[]): SavedTranslationApi {
  return {
    name: uniqueTranslationApiName(items, 'Custom API'),
    baseUrl: 'https://api.example.com/v1',
    apiKey: '',
    model: ''
  };
}

function translationApiNameExists(items: SavedTranslationApi[], name: string, currentName: string): boolean {
  for (let i = 0; i < items.length; i++) {
    if (items[i].name === name && items[i].name !== currentName) {
      return true;
    }
  }
  return false;
}
