import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { GalleryInfo, GalleryTagGroup } from '../model/GalleryModels';

const PREFERENCES_NAME: string = 'ehviewer_filters';
const VALUES_KEY: string = 'filters';

export const FILTER_MODE_TITLE: number = 0;
export const FILTER_MODE_UPLOADER: number = 1;
export const FILTER_MODE_TAG: number = 2;
export const FILTER_MODE_TAG_NAMESPACE: number = 3;
export const FILTER_MODE_RATING: number = 4;

export interface FilterRule {
  id: number;
  mode: number;
  text: string;
  enabled: boolean;
}

interface StoredFilterRule {
  id?: number;
  mode?: number;
  text?: string;
  enabled?: boolean;
}

export class EhFilterStore {
  private rules: FilterRule[] = [];
  private nextId: number = 1;

  getRules(): FilterRule[] {
    return cloneRules(this.rules);
  }

  addRule(mode: number, text: string, enabled: boolean = true): boolean {
    const normalized = normalizeRuleText(mode, text);
    if (normalized.length === 0) {
      return false;
    }
    for (let i = 0; i < this.rules.length; i++) {
      if (this.rules[i].mode === mode && this.rules[i].text.toLowerCase() === normalized.toLowerCase()) {
        return false;
      }
    }
    this.rules.push({
      id: this.nextId++,
      mode: mode,
      text: normalized,
      enabled: enabled
    });
    return true;
  }

  removeRule(id: number): void {
    const next: FilterRule[] = [];
    for (let i = 0; i < this.rules.length; i++) {
      if (this.rules[i].id !== id) {
        next.push(cloneRule(this.rules[i]));
      }
    }
    this.rules = next;
  }

  toggleRule(id: number): void {
    for (let i = 0; i < this.rules.length; i++) {
      if (this.rules[i].id === id) {
        this.rules[i].enabled = !this.rules[i].enabled;
        return;
      }
    }
  }

  isFiltered(gallery: GalleryInfo): boolean {
    for (let i = 0; i < this.rules.length; i++) {
      const rule = this.rules[i];
      if (!rule.enabled || rule.text.length === 0) {
        continue;
      }
      if (matchesRule(rule, gallery)) {
        return true;
      }
    }
    return false;
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const raw = await prefs.get(VALUES_KEY, '');
      this.rules = [];
      this.nextId = 1;
      if (typeof raw !== 'string' || raw.length === 0) {
        return;
      }
      const parsed = JSON.parse(raw) as StoredFilterRule[];
      if (!Array.isArray(parsed)) {
        return;
      }
      for (let i = 0; i < parsed.length; i++) {
        const item = parsed[i];
        if (typeof item.text === 'string' && item.text.length > 0) {
          const mode = typeof item.mode === 'number' ? item.mode : FILTER_MODE_TITLE;
          const normalizedText = normalizeRuleText(mode, item.text);
          if (normalizedText.length === 0) {
            continue;
          }
          const rule: FilterRule = {
            id: typeof item.id === 'number' ? item.id : this.nextId,
            mode: mode,
            text: normalizedText,
            enabled: typeof item.enabled === 'boolean' ? item.enabled : true
          };
          this.rules.push(rule);
          if (rule.id >= this.nextId) {
            this.nextId = rule.id + 1;
          }
        }
      }
    } catch (error) {
      throw new Error(String(error));
    }
  }

  async save(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(VALUES_KEY, JSON.stringify(this.rules));
      await prefs.flush();
    } catch (error) {
      throw new Error(String(error));
    }
  }
}

function matchesRule(rule: FilterRule, gallery: GalleryInfo): boolean {
  const text = rule.text.toLowerCase();
  if (rule.mode === FILTER_MODE_TITLE) {
    const title = gallery.title.toLowerCase();
    const titleJpn = gallery.titleJpn !== undefined ? gallery.titleJpn.toLowerCase() : '';
    return title.indexOf(text) >= 0 || (titleJpn.length > 0 && titleJpn.indexOf(text) >= 0);
  }
  if (rule.mode === FILTER_MODE_UPLOADER) {
    const uploader = gallery.uploader !== undefined ? gallery.uploader.toLowerCase() : '';
    return uploader === text;
  }
  if (rule.mode === FILTER_MODE_TAG) {
    return galleryHasTag(gallery, text);
  }
  if (rule.mode === FILTER_MODE_TAG_NAMESPACE) {
    return galleryHasTagWithNamespace(gallery, text);
  }
  if (rule.mode === FILTER_MODE_RATING) {
    return galleryMatchesRating(gallery, text);
  }
  return false;
}

function normalizeRuleText(mode: number, text: string): string {
  const trimmed = text.replace(/\s+/g, ' ').trim();
  if (mode === FILTER_MODE_RATING) {
    const rating = parseRatingThreshold(trimmed);
    if (rating <= 1 || rating > 5) {
      return '';
    }
    return rating.toString();
  }
  if (mode === FILTER_MODE_TAG || mode === FILTER_MODE_TAG_NAMESPACE) {
    return normalizeTagText(trimmed);
  }
  return trimmed;
}

function galleryHasTag(gallery: GalleryInfo, text: string): boolean {
  const separator = text.indexOf(':');
  if (separator > 0) {
    return galleryHasTagWithNamespace(gallery, text);
  }
  if (gallery.simpleTags !== undefined) {
    for (let i = 0; i < gallery.simpleTags.length; i++) {
      if (gallery.simpleTags[i].toLowerCase() === text) {
        return true;
      }
    }
  }
  if (gallery.tagList !== undefined) {
    for (let i = 0; i < gallery.tagList.length; i++) {
      const tag = gallery.tagList[i].toLowerCase();
      const colon = tag.indexOf(':');
      const tagOnly = colon >= 0 ? tag.substring(colon + 1).trim() : tag;
      if (tagOnly === text || tag === text) {
        return true;
      }
    }
  }
  return groupsContainTag(gallery.detailTags, '', text);
}

function galleryHasTagWithNamespace(gallery: GalleryInfo, text: string): boolean {
  const separator = text.indexOf(':');
  const namespace = separator > 0 ? text.substring(0, separator).trim() : '';
  const tagText = separator > 0 ? text.substring(separator + 1).trim() : text;
  if (gallery.simpleTags !== undefined) {
    for (let i = 0; i < gallery.simpleTags.length; i++) {
      if (normalizeTagText(gallery.simpleTags[i]) === text) {
        return true;
      }
    }
  }
  if (gallery.tagList !== undefined) {
    for (let i = 0; i < gallery.tagList.length; i++) {
      if (normalizeTagText(gallery.tagList[i]) === text) {
        return true;
      }
    }
  }
  if (namespace.length === 0) {
    return galleryHasTag(gallery, tagText);
  }
  return groupsContainTag(gallery.detailTags, namespace, tagText);
}

function groupsContainTag(groups: GalleryTagGroup[] | undefined, namespace: string, tag: string): boolean {
  if (groups === undefined) {
    return false;
  }
  const normalizedNamespace = normalizeTagText(namespace);
  const normalizedTag = normalizeTagText(tag);
  for (let i = 0; i < groups.length; i++) {
    const groupNamespace = normalizeTagText(groups[i].namespace);
    if (normalizedNamespace.length > 0 && groupNamespace !== normalizedNamespace) {
      continue;
    }
    for (let j = 0; j < groups[i].tags.length; j++) {
      if (normalizeTagText(groups[i].tags[j]) === normalizedTag) {
        return true;
      }
    }
  }
  return false;
}

function galleryMatchesRating(gallery: GalleryInfo, text: string): boolean {
  const threshold = parseRatingThreshold(text);
  if (threshold <= 1 || threshold > 5) {
    return false;
  }
  return gallery.rating < threshold;
}

function parseRatingThreshold(text: string): number {
  let valueText = text.trim();
  if (valueText.startsWith('<=')) {
    valueText = valueText.substring(2).trim();
  } else if (valueText.startsWith('>=')) {
    valueText = valueText.substring(2).trim();
  } else if (valueText.startsWith('<')) {
    valueText = valueText.substring(1).trim();
  } else if (valueText.startsWith('>')) {
    valueText = valueText.substring(1).trim();
  } else if (valueText.startsWith('=')) {
    valueText = valueText.substring(1).trim();
  }
  const value = Number.parseFloat(valueText);
  if (!Number.isFinite(value)) {
    return -1;
  }
  return Math.max(1, Math.min(5, Math.round(value)));
}

function normalizeTagText(text: string): string {
  return text.replace(/\s+/g, ' ').trim().toLowerCase();
}

function cloneRule(rule: FilterRule): FilterRule {
  return {
    id: rule.id,
    mode: rule.mode,
    text: rule.text,
    enabled: rule.enabled
  };
}

function cloneRules(rules: FilterRule[]): FilterRule[] {
  const cloned: FilterRule[] = [];
  for (let i = 0; i < rules.length; i++) {
    cloned.push(cloneRule(rules[i]));
  }
  return cloned;
}

export const ehFilterStore: EhFilterStore = new EhFilterStore();
