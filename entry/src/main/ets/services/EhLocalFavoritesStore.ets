import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { GalleryCategory, GalleryInfo, GalleryTagGroup } from '../model/GalleryModels';

const PREFERENCES_NAME: string = 'ehviewer_local_favorites';
const VALUES_KEY: string = 'items';

interface StoredLocalFavoriteInfo {
  gid?: number;
  token?: string;
  title?: string;
  titleJpn?: string;
  thumb?: string;
  category?: number;
  posted?: string;
  uploader?: string;
  rating?: number;
  rated?: boolean;
  simpleLanguage?: string;
  simpleTags?: string[];
  pages?: number;
  thumbWidth?: number;
  thumbHeight?: number;
  favoriteSlot?: number;
  favoriteName?: string;
  tagList?: string[];
  detailTags?: StoredGalleryTagGroup[];
  detailLanguage?: string;
  time?: number;
}

interface StoredGalleryTagGroup {
  namespace?: string;
  tags?: string[];
}

interface LocalFavoriteEntry {
  gallery: GalleryInfo;
  time: number;
}

export class EhLocalFavoritesStore {
  private items: LocalFavoriteEntry[] = [];
  private context: common.UIAbilityContext | undefined = undefined;
  private loaded: boolean = false;
  private loadPromise: Promise<void> | null = null;
  private saveChain: Promise<void> = Promise.resolve();

  async ensureLoaded(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      this.context = context;
      return;
    }
    if (this.loadPromise !== null) {
      return this.loadPromise;
    }
    this.context = context;
    this.loadPromise = this.load(context);
    return this.loadPromise;
  }

  getItems(keyword: string = ''): GalleryInfo[] {
    const normalized = keyword.trim().toLowerCase();
    const result: GalleryInfo[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const gallery = this.items[i].gallery;
      if (normalized.length === 0 || localFavoriteMatches(gallery, normalized)) {
        result.push(cloneLocalFavoriteGallery(gallery));
      }
    }
    return result;
  }

  count(): number {
    return this.items.length;
  }

  contains(gid: number): boolean {
    return this.findIndex(gid) >= 0;
  }

  addGallery(gallery: GalleryInfo): void {
    if (gallery.gid <= 0 || gallery.token.length === 0) {
      return;
    }
    this.putGallery(gallery, Date.now(), true);
  }

  importGallery(gallery: GalleryInfo, time: number): boolean {
    if (gallery.gid <= 0 || gallery.token.length === 0) {
      return false;
    }
    this.putGallery(gallery, time, false);
    return true;
  }

  async save(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    await this.saveSnapshot(context, this.snapshot());
  }

  private putGallery(gallery: GalleryInfo, time: number, queueSave: boolean): void {
    const nextGallery = cloneLocalFavoriteGallery(gallery);
    nextGallery.favoriteSlot = -1;
    nextGallery.favoriteName = undefined;
    const nextEntry: LocalFavoriteEntry = {
      gallery: nextGallery,
      time: time
    };
    const next: LocalFavoriteEntry[] = [nextEntry];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gallery.gid !== gallery.gid) {
        next.push(cloneLocalFavoriteEntry(this.items[i]));
      }
    }
    next.sort((left: LocalFavoriteEntry, right: LocalFavoriteEntry): number => right.time - left.time);
    this.items = next;
    if (queueSave) {
      this.queueSave();
    }
  }

  removeGallery(gid: number): void {
    const next: LocalFavoriteEntry[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gallery.gid !== gid) {
        next.push(cloneLocalFavoriteEntry(this.items[i]));
      }
    }
    this.items = next;
    this.queueSave();
  }

  private async load(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const raw = await prefs.get(VALUES_KEY, '[]');
      const text = typeof raw === 'string' ? raw : '[]';
      const parsed = JSON.parse(text) as StoredLocalFavoriteInfo[];
      const next: LocalFavoriteEntry[] = [];
      for (let i = 0; i < parsed.length; i++) {
        const stored = parsed[i];
        const gallery = storedLocalFavoriteToGallery(stored);
        if (gallery !== null) {
          next.push({
            gallery: gallery,
            time: typeof stored.time === 'number' ? stored.time : 0
          });
        }
      }
      next.sort((left: LocalFavoriteEntry, right: LocalFavoriteEntry): number => right.time - left.time);
      this.items = next;
    } catch (error) {
      this.items = [];
    }
    this.loaded = true;
    this.loadPromise = null;
  }

  private queueSave(): void {
    const context = this.context;
    if (context === undefined) {
      return;
    }
    const snapshot = this.snapshot();
    this.saveChain = this.saveChain.then(async () => {
      await this.saveSnapshot(context, snapshot);
    }).catch(() => {});
  }

  private snapshot(): StoredLocalFavoriteInfo[] {
    return this.items.map((entry: LocalFavoriteEntry): StoredLocalFavoriteInfo => {
      return galleryToStoredLocalFavorite(entry.gallery, entry.time);
    });
  }

  private async saveSnapshot(context: common.UIAbilityContext, snapshot: StoredLocalFavoriteInfo[]): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(VALUES_KEY, JSON.stringify(snapshot));
      await prefs.flush();
    } catch (error) {
      throw new Error(String(error));
    }
  }

  private findIndex(gid: number): number {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gallery.gid === gid) {
        return i;
      }
    }
    return -1;
  }
}

function storedLocalFavoriteToGallery(stored: StoredLocalFavoriteInfo): GalleryInfo | null {
  if (typeof stored.gid !== 'number' || stored.gid <= 0 || typeof stored.token !== 'string' ||
    stored.token.length === 0) {
    return null;
  }
  return {
    gid: stored.gid,
    token: stored.token,
    title: stored.title === undefined ? '' : stored.title,
    titleJpn: stored.titleJpn,
    thumb: stored.thumb,
    category: typeof stored.category === 'number' ? stored.category : GalleryCategory.Unknown,
    posted: stored.posted,
    uploader: stored.uploader,
    rating: typeof stored.rating === 'number' ? stored.rating : 0,
    rated: stored.rated === true,
    simpleLanguage: stored.simpleLanguage,
    simpleTags: cloneStringArray(stored.simpleTags),
    pages: typeof stored.pages === 'number' ? stored.pages : 0,
    thumbWidth: typeof stored.thumbWidth === 'number' ? stored.thumbWidth : 0,
    thumbHeight: typeof stored.thumbHeight === 'number' ? stored.thumbHeight : 0,
    favoriteSlot: -1,
    favoriteName: undefined,
    tagList: cloneStringArray(stored.tagList),
    detailTags: storedGalleryTagGroupsToTags(stored.detailTags),
    detailLanguage: stored.detailLanguage
  };
}

function galleryToStoredLocalFavorite(gallery: GalleryInfo, time: number): StoredLocalFavoriteInfo {
  return {
    gid: gallery.gid,
    token: gallery.token,
    title: gallery.title,
    titleJpn: gallery.titleJpn,
    thumb: gallery.thumb,
    category: gallery.category,
    posted: gallery.posted,
    uploader: gallery.uploader,
    rating: gallery.rating,
    rated: gallery.rated,
    simpleLanguage: gallery.simpleLanguage,
    simpleTags: cloneStringArray(gallery.simpleTags),
    pages: gallery.pages,
    thumbWidth: gallery.thumbWidth,
    thumbHeight: gallery.thumbHeight,
    favoriteSlot: -1,
    favoriteName: undefined,
    tagList: cloneStringArray(gallery.tagList),
    detailTags: galleryTagsToStored(gallery.detailTags),
    detailLanguage: gallery.detailLanguage,
    time: time
  };
}

function localFavoriteMatches(gallery: GalleryInfo, keyword: string): boolean {
  const haystack = [
    gallery.title,
    gallery.titleJpn === undefined ? '' : gallery.titleJpn,
    gallery.uploader === undefined ? '' : gallery.uploader,
    (gallery.simpleTags === undefined ? [] : gallery.simpleTags).join(' '),
    (gallery.tagList === undefined ? [] : gallery.tagList).join(' ')
  ].join(' ').toLowerCase();
  return haystack.indexOf(keyword) >= 0;
}

function cloneLocalFavoriteEntry(entry: LocalFavoriteEntry): LocalFavoriteEntry {
  return {
    gallery: cloneLocalFavoriteGallery(entry.gallery),
    time: entry.time
  };
}

function cloneLocalFavoriteGallery(gallery: GalleryInfo): GalleryInfo {
  return {
    gid: gallery.gid,
    token: gallery.token,
    title: gallery.title,
    titleJpn: gallery.titleJpn,
    thumb: gallery.thumb,
    category: gallery.category,
    posted: gallery.posted,
    uploader: gallery.uploader,
    rating: gallery.rating,
    rated: gallery.rated,
    simpleLanguage: gallery.simpleLanguage,
    simpleTags: cloneStringArray(gallery.simpleTags),
    pages: gallery.pages,
    thumbWidth: gallery.thumbWidth,
    thumbHeight: gallery.thumbHeight,
    favoriteSlot: -1,
    favoriteName: undefined,
    tagList: cloneStringArray(gallery.tagList),
    detailTags: cloneGalleryTagGroups(gallery.detailTags),
    detailLanguage: gallery.detailLanguage
  };
}

function storedGalleryTagGroupsToTags(groups: StoredGalleryTagGroup[] | undefined): GalleryTagGroup[] | undefined {
  if (groups === undefined) {
    return undefined;
  }
  const result: GalleryTagGroup[] = [];
  for (let i = 0; i < groups.length; i++) {
    if (typeof groups[i].namespace === 'string') {
      result.push({
        namespace: groups[i].namespace as string,
        tags: cloneStringArrayRequired(groups[i].tags)
      });
    }
  }
  return result.length === 0 ? undefined : result;
}

function galleryTagsToStored(groups: GalleryTagGroup[] | undefined): StoredGalleryTagGroup[] | undefined {
  if (groups === undefined) {
    return undefined;
  }
  const result: StoredGalleryTagGroup[] = [];
  for (let i = 0; i < groups.length; i++) {
    result.push({
      namespace: groups[i].namespace,
      tags: cloneStringArrayRequired(groups[i].tags)
    });
  }
  return result;
}

function cloneGalleryTagGroups(groups: GalleryTagGroup[] | undefined): GalleryTagGroup[] | undefined {
  if (groups === undefined) {
    return undefined;
  }
  const result: GalleryTagGroup[] = [];
  for (let i = 0; i < groups.length; i++) {
    result.push({
      namespace: groups[i].namespace,
      tags: cloneStringArrayRequired(groups[i].tags)
    });
  }
  return result;
}

function cloneStringArrayRequired(values: string[] | undefined): string[] {
  if (values === undefined) {
    return [];
  }
  return values.slice();
}

function cloneStringArray(values: string[] | undefined): string[] | undefined {
  if (values === undefined) {
    return undefined;
  }
  return values.slice();
}

export const ehLocalFavoritesStore = new EhLocalFavoritesStore();
