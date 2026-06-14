import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { GalleryCategory, GalleryInfo } from '../model/GalleryModels';

const PREFERENCES_NAME: string = 'ehviewer_history';
const VALUES_KEY: string = 'items';
const READ_POSITIONS_KEY: string = 'read_positions';
const DEFAULT_MAX_SIZE: number = 100;

interface StoredGalleryInfo {
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
}

interface StoredReadPosition {
  gid?: number;
  pageIndex?: number;
  updatedAt?: number;
}

interface ReadPosition {
  gid: number;
  pageIndex: number;
  updatedAt: number;
}

export class EhHistoryStore {
  private items: GalleryInfo[] = [];
  private readPositions: ReadPosition[] = [];

  getItems(): GalleryInfo[] {
    return cloneGalleryInfos(this.items);
  }

  addGallery(gallery: GalleryInfo, maxSize: number = DEFAULT_MAX_SIZE): void {
    if (gallery.gid <= 0 || gallery.token.length === 0) {
      return;
    }

    const next: GalleryInfo[] = [cloneGalleryInfo(gallery)];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gid !== gallery.gid) {
        next.push(cloneGalleryInfo(this.items[i]));
      }
      if (next.length >= maxSize) {
        break;
      }
    }
    this.items = next;
  }

  removeGallery(gid: number): void {
    const next: GalleryInfo[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gid !== gid) {
        next.push(cloneGalleryInfo(this.items[i]));
      }
    }
    this.items = next;
    this.removeReadPosition(gid);
  }

  clear(): void {
    this.items = [];
    this.readPositions = [];
  }

  getReadPage(gid: number): number {
    for (let i = 0; i < this.readPositions.length; i++) {
      if (this.readPositions[i].gid === gid) {
        return this.readPositions[i].pageIndex;
      }
    }
    return -1;
  }

  setReadPage(gid: number, pageIndex: number): void {
    if (gid <= 0 || pageIndex < 0) {
      return;
    }
    for (let i = 0; i < this.readPositions.length; i++) {
      if (this.readPositions[i].gid === gid) {
        this.readPositions[i].pageIndex = pageIndex;
        this.readPositions[i].updatedAt = Date.now();
        return;
      }
    }
    this.readPositions.push({ gid: gid, pageIndex: pageIndex, updatedAt: Date.now() });
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const raw = await prefs.get(VALUES_KEY, '');
      const rawPositions = await prefs.get(READ_POSITIONS_KEY, '');
      this.items = [];
      this.readPositions = [];
      if (typeof raw !== 'string' || raw.length === 0) {
        this.loadReadPositions(rawPositions);
        return;
      }

      const parsed = JSON.parse(raw) as StoredGalleryInfo[];
      if (!Array.isArray(parsed)) {
        return;
      }

      for (let i = 0; i < parsed.length; i++) {
        const item = storedToGalleryInfo(parsed[i]);
        if (item.gid > 0 && item.token.length > 0) {
          this.items.push(item);
        }
      }
      this.loadReadPositions(rawPositions);
    } catch (error) {
      throw new Error(String(error));
    }
  }

  async save(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(VALUES_KEY, JSON.stringify(this.items));
      await prefs.put(READ_POSITIONS_KEY, JSON.stringify(this.readPositions));
      await prefs.flush();
    } catch (error) {
      throw new Error(String(error));
    }
  }

  private loadReadPositions(raw: preferences.ValueType): void {
    if (typeof raw !== 'string' || raw.length === 0) {
      return;
    }
    try {
      const parsed = JSON.parse(raw) as StoredReadPosition[];
      if (!Array.isArray(parsed)) {
        return;
      }
      for (let i = 0; i < parsed.length; i++) {
        const item = storedToReadPosition(parsed[i]);
        if (item.gid > 0 && item.pageIndex >= 0) {
          this.readPositions.push(item);
        }
      }
    } catch (error) {
    }
  }

  private removeReadPosition(gid: number): void {
    const next: ReadPosition[] = [];
    for (let i = 0; i < this.readPositions.length; i++) {
      if (this.readPositions[i].gid !== gid) {
        next.push(this.readPositions[i]);
      }
    }
    this.readPositions = next;
  }
}

function storedToGalleryInfo(item: StoredGalleryInfo): GalleryInfo {
  return {
    gid: typeof item.gid === 'number' ? item.gid : 0,
    token: typeof item.token === 'string' ? item.token : '',
    title: typeof item.title === 'string' ? item.title : '',
    titleJpn: item.titleJpn,
    thumb: item.thumb,
    category: typeof item.category === 'number' ? item.category : GalleryCategory.Unknown,
    posted: item.posted,
    uploader: item.uploader,
    rating: typeof item.rating === 'number' ? item.rating : -1,
    rated: typeof item.rated === 'boolean' ? item.rated : false,
    simpleLanguage: item.simpleLanguage,
    simpleTags: item.simpleTags,
    pages: typeof item.pages === 'number' ? item.pages : 0,
    thumbWidth: typeof item.thumbWidth === 'number' ? item.thumbWidth : 0,
    thumbHeight: typeof item.thumbHeight === 'number' ? item.thumbHeight : 0,
    favoriteSlot: typeof item.favoriteSlot === 'number' ? item.favoriteSlot : -2,
    favoriteName: item.favoriteName,
    tagList: item.tagList
  };
}

function storedToReadPosition(item: StoredReadPosition): ReadPosition {
  return {
    gid: typeof item.gid === 'number' ? item.gid : 0,
    pageIndex: typeof item.pageIndex === 'number' ? item.pageIndex : -1,
    updatedAt: typeof item.updatedAt === 'number' ? item.updatedAt : 0
  };
}

function cloneGalleryInfos(items: GalleryInfo[]): GalleryInfo[] {
  const cloned: GalleryInfo[] = [];
  for (let i = 0; i < items.length; i++) {
    cloned.push(cloneGalleryInfo(items[i]));
  }
  return cloned;
}

function cloneGalleryInfo(item: GalleryInfo): GalleryInfo {
  return {
    gid: item.gid,
    token: item.token,
    title: item.title,
    titleJpn: item.titleJpn,
    thumb: item.thumb,
    category: item.category,
    posted: item.posted,
    uploader: item.uploader,
    rating: item.rating,
    rated: item.rated,
    simpleLanguage: item.simpleLanguage,
    simpleTags: item.simpleTags,
    pages: item.pages,
    thumbWidth: item.thumbWidth,
    thumbHeight: item.thumbHeight,
    favoriteSlot: item.favoriteSlot,
    favoriteName: item.favoriteName,
    tagList: item.tagList
  };
}

export const ehHistoryStore: EhHistoryStore = new EhHistoryStore();
