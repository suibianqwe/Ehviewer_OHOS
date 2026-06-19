import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { GalleryCategory, GalleryInfo } from '../model/GalleryModels';

const PREFERENCES_NAME: string = 'ehviewer_downloads';
const VALUES_KEY: string = 'items';
const LABELS_KEY: string = 'labels';

export enum DownloadState {
  Invalid = 'invalid',
  None = 'none',
  Wait = 'wait',
  Downloading = 'downloading',
  Finish = 'finish',
  Failed = 'failed',
  Update = 'update'
}

export interface DownloadInfo extends GalleryInfo {
  state: DownloadState;
  legacy: number;
  time: number;
  label: string;
  archiveUri: string;
  speed: number;
  remaining: number;
  finished: number;
  downloaded: number;
  total: number;
  fileSize: number;
}

export interface DownloadLabel {
  label: string;
  time: number;
}

type DownloadStoreListener = (items: DownloadInfo[], labels: DownloadLabel[]) => void;

interface StoredDownloadInfo {
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
  state?: string;
  legacy?: number;
  time?: number;
  label?: string;
  archiveUri?: string;
  speed?: number;
  remaining?: number;
  finished?: number;
  downloaded?: number;
  total?: number;
  fileSize?: number;
}

interface StoredDownloadLabel {
  label?: string;
  time?: number;
}

export class EhDownloadStore {
  private items: DownloadInfo[] = [];
  private labels: DownloadLabel[] = [];
  private listeners: DownloadStoreListener[] = [];

  subscribe(listener: DownloadStoreListener): () => void {
    this.listeners.push(listener);
    listener(this.getItems(), this.getLabels());
    return () => {
      const next: DownloadStoreListener[] = [];
      for (let i = 0; i < this.listeners.length; i++) {
        if (this.listeners[i] !== listener) {
          next.push(this.listeners[i]);
        }
      }
      this.listeners = next;
    };
  }

  getItems(): DownloadInfo[] {
    return cloneDownloadInfos(this.items);
  }

  getLabels(): DownloadLabel[] {
    return cloneDownloadLabels(this.labels);
  }

  contains(gid: number): boolean {
    return this.findIndex(gid) >= 0;
  }

  addGallery(gallery: GalleryInfo, label: string = ''): DownloadInfo | null {
    if (gallery.gid <= 0 || gallery.token.length === 0) {
      return null;
    }

    const index = this.findIndex(gallery.gid);
    if (index >= 0) {
      const updated = galleryToDownloadInfo(gallery, this.items[index].label);
      updated.state = this.items[index].state;
      updated.legacy = this.items[index].legacy;
      updated.time = this.items[index].time;
      updated.archiveUri = this.items[index].archiveUri;
      updated.speed = this.items[index].speed;
      updated.remaining = this.items[index].remaining;
      updated.finished = this.items[index].finished;
      updated.downloaded = this.items[index].downloaded;
      updated.total = this.items[index].total;
      updated.fileSize = this.items[index].fileSize;
      this.items[index] = updated;
      this.notifyChanged();
      return cloneDownloadInfo(updated);
    }

    const item = galleryToDownloadInfo(gallery, label);
    this.items.unshift(item);
    this.notifyChanged();
    return cloneDownloadInfo(item);
  }

  removeGallery(gid: number): void {
    const next: DownloadInfo[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gid !== gid) {
        next.push(cloneDownloadInfo(this.items[i]));
      }
    }
    this.items = next;
    this.notifyChanged();
  }

  setState(gid: number, state: DownloadState): void {
    const index = this.findIndex(gid);
    if (index < 0) {
      return;
    }
    this.items[index].state = state;
    this.notifyChanged();
  }

  updateGallery(gallery: GalleryInfo): void {
    const index = this.findIndex(gallery.gid);
    if (index < 0) {
      return;
    }
    const previous = this.items[index];
    const updated = galleryToDownloadInfo(gallery, previous.label);
    updated.state = previous.state;
    updated.legacy = previous.legacy;
    updated.time = previous.time;
    updated.archiveUri = previous.archiveUri;
    updated.speed = previous.speed;
    updated.remaining = previous.remaining;
    updated.finished = previous.finished;
    updated.downloaded = previous.downloaded;
    updated.total = previous.total > 0 ? previous.total : updated.total;
    updated.fileSize = previous.fileSize;
    this.items[index] = updated;
    this.notifyChanged();
  }

  setProgress(gid: number, finished: number, total: number, downloaded: number = 0): void {
    const index = this.findIndex(gid);
    if (index < 0) {
      return;
    }
    this.items[index].finished = finished;
    this.items[index].downloaded = downloaded;
    this.items[index].total = total;
    this.notifyChanged();
  }

  setTransfer(gid: number, speed: number, remaining: number): void {
    const index = this.findIndex(gid);
    if (index < 0) {
      return;
    }
    this.items[index].speed = Math.max(0, speed);
    this.items[index].remaining = Math.max(0, remaining);
    this.notifyChanged();
  }

  setStorage(gid: number, archiveUri: string, fileSize: number): void {
    const index = this.findIndex(gid);
    if (index < 0) {
      return;
    }
    this.items[index].archiveUri = archiveUri;
    this.items[index].fileSize = fileSize;
    this.notifyChanged();
  }

  setLabel(gid: number, label: string): void {
    const index = this.findIndex(gid);
    if (index < 0) {
      return;
    }
    this.items[index].label = label;
    this.notifyChanged();
  }

  addLabel(label: string): boolean {
    const normalized = normalizeLabel(label);
    if (normalized.length === 0 || this.containsLabel(normalized)) {
      return false;
    }
    this.labels.push({ label: normalized, time: Date.now() });
    this.notifyChanged();
    return true;
  }

  removeLabel(label: string): void {
    const normalized = normalizeLabel(label);
    const next: DownloadLabel[] = [];
    for (let i = 0; i < this.labels.length; i++) {
      if (this.labels[i].label !== normalized) {
        next.push(cloneDownloadLabel(this.labels[i]));
      }
    }
    this.labels = next;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].label === normalized) {
        this.items[i].label = '';
      }
    }
    this.notifyChanged();
  }

  private containsLabel(label: string): boolean {
    for (let i = 0; i < this.labels.length; i++) {
      if (this.labels[i].label === label) {
        return true;
      }
    }
    return false;
  }

  startAll(): void {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].state === DownloadState.None || this.items[i].state === DownloadState.Failed ||
        this.items[i].state === DownloadState.Finish) {
        this.items[i].state = DownloadState.Wait;
      }
    }
    this.notifyChanged();
  }

  startGallery(gid: number): void {
    const index = this.findIndex(gid);
    if (index < 0) {
      return;
    }
    if (this.items[index].state !== DownloadState.Wait && this.items[index].state !== DownloadState.Downloading) {
      this.items[index].state = DownloadState.Wait;
      this.notifyChanged();
    }
  }

  stopGallery(gid: number): void {
    const index = this.findIndex(gid);
    if (index < 0) {
      return;
    }
    if (this.items[index].state === DownloadState.Wait || this.items[index].state === DownloadState.Downloading) {
      this.items[index].state = DownloadState.None;
      this.notifyChanged();
    }
  }

  stopAll(): void {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].state === DownloadState.Wait || this.items[i].state === DownloadState.Downloading) {
        this.items[i].state = DownloadState.None;
      }
    }
    this.notifyChanged();
  }

  clearFinished(): void {
    const next: DownloadInfo[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].state !== DownloadState.Finish) {
        next.push(cloneDownloadInfo(this.items[i]));
      }
    }
    this.items = next;
    this.notifyChanged();
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const raw = await prefs.get(VALUES_KEY, '');
      const rawLabels = await prefs.get(LABELS_KEY, '');
      this.items = [];
      this.labels = [];
      if (typeof raw !== 'string' || raw.length === 0) {
        this.loadLabels(rawLabels);
        this.notifyChanged();
        return;
      }

      const parsed = JSON.parse(raw) as StoredDownloadInfo[];
      if (!Array.isArray(parsed)) {
        return;
      }

      for (let i = 0; i < parsed.length; i++) {
        const item = storedToDownloadInfo(parsed[i]);
        if (item.gid > 0 && item.token.length > 0) {
          this.items.push(item);
        }
      }
      this.loadLabels(rawLabels);
      this.notifyChanged();
    } catch (error) {
      throw new Error(String(error));
    }
  }

  async save(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(VALUES_KEY, JSON.stringify(this.items));
      await prefs.put(LABELS_KEY, JSON.stringify(this.labels));
      await prefs.flush();
    } catch (error) {
      throw new Error(String(error));
    }
  }

  private loadLabels(rawLabels: preferences.ValueType): void {
    if (typeof rawLabels !== 'string' || rawLabels.length === 0) {
      return;
    }
    const parsed = JSON.parse(rawLabels) as StoredDownloadLabel[];
    if (!Array.isArray(parsed)) {
      return;
    }
    for (let i = 0; i < parsed.length; i++) {
      const label = storedToDownloadLabel(parsed[i]);
      if (label.label.length > 0 && !this.containsLabel(label.label)) {
        this.labels.push(label);
      }
    }
  }

  private findIndex(gid: number): number {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].gid === gid) {
        return i;
      }
    }
    return -1;
  }

  private notifyChanged(): void {
    const items = this.getItems();
    const labels = this.getLabels();
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i](items, labels);
    }
  }
}

function galleryToDownloadInfo(gallery: GalleryInfo, label: string): DownloadInfo {
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
    simpleTags: gallery.simpleTags,
    pages: gallery.pages,
    thumbWidth: gallery.thumbWidth,
    thumbHeight: gallery.thumbHeight,
    favoriteSlot: gallery.favoriteSlot,
    favoriteName: gallery.favoriteName,
    tagList: gallery.tagList,
    state: DownloadState.None,
    legacy: 0,
    time: Date.now(),
    label: label,
    archiveUri: '',
    speed: 0,
    remaining: 0,
    finished: 0,
    downloaded: 0,
    total: gallery.pages,
    fileSize: -1
  };
}

function storedToDownloadInfo(item: StoredDownloadInfo): DownloadInfo {
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
    tagList: item.tagList,
    state: normalizeDownloadState(item.state),
    legacy: typeof item.legacy === 'number' ? item.legacy : 0,
    time: typeof item.time === 'number' ? item.time : Date.now(),
    label: typeof item.label === 'string' ? item.label : '',
    archiveUri: typeof item.archiveUri === 'string' ? item.archiveUri : '',
    speed: typeof item.speed === 'number' ? item.speed : 0,
    remaining: typeof item.remaining === 'number' ? item.remaining : 0,
    finished: typeof item.finished === 'number' ? item.finished : 0,
    downloaded: typeof item.downloaded === 'number' ? item.downloaded : 0,
    total: typeof item.total === 'number' ? item.total : (typeof item.pages === 'number' ? item.pages : 0),
    fileSize: typeof item.fileSize === 'number' ? item.fileSize : -1
  };
}

function normalizeDownloadState(value: string | undefined): DownloadState {
  if (value === DownloadState.Wait || value === DownloadState.Downloading || value === DownloadState.Finish ||
    value === DownloadState.Failed || value === DownloadState.Update || value === DownloadState.Invalid) {
    return value as DownloadState;
  }
  return DownloadState.None;
}

function storedToDownloadLabel(item: StoredDownloadLabel): DownloadLabel {
  return {
    label: typeof item.label === 'string' ? normalizeLabel(item.label) : '',
    time: typeof item.time === 'number' ? item.time : Date.now()
  };
}

function normalizeLabel(label: string): string {
  const normalized = label.replace(/\s+/g, ' ').trim();
  if (normalized === 'Default') {
    return '';
  }
  return normalized.length > 40 ? normalized.substring(0, 40).trim() : normalized;
}

function cloneDownloadInfos(items: DownloadInfo[]): DownloadInfo[] {
  const cloned: DownloadInfo[] = [];
  for (let i = 0; i < items.length; i++) {
    cloned.push(cloneDownloadInfo(items[i]));
  }
  return cloned;
}

function cloneDownloadInfo(item: DownloadInfo): DownloadInfo {
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
    tagList: item.tagList,
    state: item.state,
    legacy: item.legacy,
    time: item.time,
    label: item.label,
    archiveUri: item.archiveUri,
    speed: item.speed,
    remaining: item.remaining,
    finished: item.finished,
    downloaded: item.downloaded,
    total: item.total,
    fileSize: item.fileSize
  };
}

function cloneDownloadLabels(labels: DownloadLabel[]): DownloadLabel[] {
  const cloned: DownloadLabel[] = [];
  for (let i = 0; i < labels.length; i++) {
    cloned.push(cloneDownloadLabel(labels[i]));
  }
  return cloned;
}

function cloneDownloadLabel(label: DownloadLabel): DownloadLabel {
  return {
    label: label.label,
    time: label.time
  };
}

export const ehDownloadStore: EhDownloadStore = new EhDownloadStore();
