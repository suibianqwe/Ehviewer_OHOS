import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { GalleryInfo } from '../model/GalleryModels';

const PREFERENCES_NAME: string = 'ehviewer_filters';
const VALUES_KEY: string = 'filters';

export const FILTER_MODE_TITLE: number = 0;
export const FILTER_MODE_UPLOADER: number = 1;
export const FILTER_MODE_TAG: number = 2;
export const FILTER_MODE_TAG_NAMESPACE: number = 3;

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

  addRule(mode: number, text: string): boolean {
    const normalized = text.trim();
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
      enabled: true
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
          const rule: FilterRule = {
            id: typeof item.id === 'number' ? item.id : this.nextId,
            mode: typeof item.mode === 'number' ? item.mode : FILTER_MODE_TITLE,
            text: item.text,
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
  return false;
}

function galleryHasTag(gallery: GalleryInfo, text: string): boolean {
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
  return false;
}

function galleryHasTagWithNamespace(gallery: GalleryInfo, text: string): boolean {
  if (gallery.tagList !== undefined) {
    for (let i = 0; i < gallery.tagList.length; i++) {
      if (gallery.tagList[i].toLowerCase() === text) {
        return true;
      }
    }
  }
  return false;
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
