import { ALL_CATEGORY, GalleryCategory, GalleryInfo, GalleryTagGroup } from '../model/GalleryModels';
import { DEFAULT_ADVANCE_SEARCH, ListMode } from './EhUrl';

export interface LocalGallerySearchOptions {
  mode: ListMode;
  category: number;
  advancedEnabled: boolean;
  advancedPanelOpened: boolean;
  advanceSearch: number;
  minRating: number;
}

export const DEFAULT_LOCAL_GALLERY_SEARCH_OPTIONS: LocalGallerySearchOptions = {
  mode: ListMode.Normal,
  category: GalleryCategory.None,
  advancedEnabled: false,
  advancedPanelOpened: false,
  advanceSearch: DEFAULT_ADVANCE_SEARCH,
  minRating: -1
};

export function galleryMatchesLocalSearch(item: GalleryInfo, keyword: string,
  options: LocalGallerySearchOptions): boolean {
  if (!matchesCategory(item, options)) {
    return false;
  }
  if (!matchesRating(item, options)) {
    return false;
  }
  return matchesKeyword(item, keyword, options.mode);
}

function matchesCategory(item: GalleryInfo, options: LocalGallerySearchOptions): boolean {
  const mask = options.category;
  if (mask === GalleryCategory.None || mask === ALL_CATEGORY) {
    return true;
  }
  return (mask & item.category) !== 0;
}

function matchesRating(item: GalleryInfo, options: LocalGallerySearchOptions): boolean {
  if (!options.advancedEnabled && !options.advancedPanelOpened) {
    return true;
  }
  if (options.minRating <= 0) {
    return true;
  }
  return item.rating >= options.minRating;
}

function matchesKeyword(item: GalleryInfo, keyword: string, mode: ListMode): boolean {
  const query = keyword.trim().toLowerCase();
  if (query.length === 0) {
    return true;
  }
  if (mode === ListMode.Tag) {
    return matchesTagQuery(item, query);
  }
  if (mode === ListMode.Uploader) {
    return textContains(item.uploader, query);
  }
  return matchesPlainText(item, query);
}

function matchesPlainText(item: GalleryInfo, query: string): boolean {
  if (textContains(item.title, query) || textContains(item.titleJpn, query) ||
    textContains(item.uploader, query) || textContains(item.simpleLanguage, query)) {
    return true;
  }
  if (arrayContainsText(item.simpleTags, query) || arrayContainsText(item.tagList, query)) {
    return true;
  }
  if (groupsContainText(item.detailTags, query)) {
    return true;
  }
  return item.gid.toString() === query;
}

function matchesTagQuery(item: GalleryInfo, query: string): boolean {
  const terms = splitSearchTerms(query);
  if (terms.length === 0) {
    return true;
  }
  for (let i = 0; i < terms.length; i++) {
    if (!matchesTagTerm(item, terms[i])) {
      return false;
    }
  }
  return true;
}

function matchesTagTerm(item: GalleryInfo, term: string): boolean {
  const normalized = normalizeTagTerm(term);
  if (normalized.length === 0) {
    return true;
  }
  const separator = normalized.indexOf(':');
  if (separator > 0) {
    const namespace = normalized.substring(0, separator).trim();
    const tag = normalizeTagTerm(normalized.substring(separator + 1));
    return matchesNamespacedTag(item, namespace, tag);
  }
  return arrayContainsTag(item.simpleTags, normalized) || arrayContainsTag(item.tagList, normalized) ||
    groupsContainTag(item.detailTags, '', normalized);
}

function matchesNamespacedTag(item: GalleryInfo, namespace: string, tag: string): boolean {
  const full = namespace + ':' + tag;
  if (arrayContainsTag(item.simpleTags, full) || arrayContainsTag(item.tagList, full)) {
    return true;
  }
  return groupsContainTag(item.detailTags, namespace, tag);
}

function groupsContainTag(groups: GalleryTagGroup[] | undefined, namespace: string, tag: string): boolean {
  if (groups === undefined) {
    return false;
  }
  for (let i = 0; i < groups.length; i++) {
    const groupNamespace = groups[i].namespace.toLowerCase();
    if (namespace.length > 0 && groupNamespace !== namespace) {
      continue;
    }
    for (let j = 0; j < groups[i].tags.length; j++) {
      if (normalizeTagTerm(groups[i].tags[j]).indexOf(tag) >= 0) {
        return true;
      }
    }
  }
  return false;
}

function groupsContainText(groups: GalleryTagGroup[] | undefined, query: string): boolean {
  if (groups === undefined) {
    return false;
  }
  for (let i = 0; i < groups.length; i++) {
    const namespace = groups[i].namespace.toLowerCase();
    if (namespace.indexOf(query) >= 0) {
      return true;
    }
    for (let j = 0; j < groups[i].tags.length; j++) {
      const tag = normalizeTagTerm(groups[i].tags[j]);
      if (tag.indexOf(query) >= 0 || (namespace + ':' + tag).indexOf(query) >= 0) {
        return true;
      }
    }
  }
  return false;
}

function splitSearchTerms(query: string): string[] {
  const terms: string[] = [];
  const pattern = /"([^"]+)"|'([^']+)'|(\S+)/g;
  let match: RegExpExecArray | null = pattern.exec(query);
  while (match !== null) {
    const term = match[1] !== undefined ? match[1] : (match[2] !== undefined ? match[2] : match[3]);
    const normalized = normalizeTagTerm(term);
    if (normalized.length > 0) {
      terms.push(normalized);
    }
    match = pattern.exec(query);
  }
  return terms;
}

function normalizeTagTerm(value: string): string {
  let normalized = value.trim().toLowerCase();
  if (normalized.length >= 2 &&
      ((normalized.charAt(0) === '"' && normalized.charAt(normalized.length - 1) === '"') ||
        (normalized.charAt(0) === '\'' && normalized.charAt(normalized.length - 1) === '\''))) {
    normalized = normalized.substring(1, normalized.length - 1);
  }
  return normalized.replace(/\\"/g, '"').trim();
}

function arrayContainsText(values: string[] | undefined, query: string): boolean {
  if (values === undefined) {
    return false;
  }
  for (let i = 0; i < values.length; i++) {
    if (textContains(values[i], query)) {
      return true;
    }
  }
  return false;
}

function arrayContainsTag(values: string[] | undefined, query: string): boolean {
  if (values === undefined) {
    return false;
  }
  for (let i = 0; i < values.length; i++) {
    if (normalizeTagTerm(values[i]).indexOf(query) >= 0) {
      return true;
    }
  }
  return false;
}

function textContains(value: string | undefined, query: string): boolean {
  if (value === undefined) {
    return false;
  }
  return value.toLowerCase().indexOf(query) >= 0;
}
