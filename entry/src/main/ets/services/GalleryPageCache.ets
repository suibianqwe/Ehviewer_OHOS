import { GalleryPage } from '../model/GalleryModels';
import { ehSettingsStore } from './EhSettingsStore';

interface GalleryPageCacheEntry {
  url: string;
  page: GalleryPage;
}

export class GalleryPageCache {
  private entries: GalleryPageCacheEntry[] = [];

  get(url: string): GalleryPage | null {
    if (url.length === 0) {
      return null;
    }
    const key = cacheKeyForUrl(url);

    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].url === key) {
        const entry = this.entries[i];
        this.entries.splice(i, 1);
        this.entries.unshift(entry);
        return cloneGalleryPage(entry.page);
      }
    }
    return null;
  }

  has(url: string): boolean {
    if (url.length === 0) {
      return false;
    }
    const key = cacheKeyForUrl(url);

    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].url === key) {
        return true;
      }
    }
    return false;
  }

  put(url: string, page: GalleryPage, maxSize: number = 80): void {
    // This cache is consumed by network downloads too. Offline pages have no remote image URL.
    if (url.length === 0 || !/^https?:\/\//i.test(page.imageUrl)) {
      return;
    }
    const key = cacheKeyForUrl(url);

    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].url === key) {
        this.entries.splice(i, 1);
        break;
      }
    }
    this.entries.unshift({ url: key, page: cloneGalleryPage(page) });

    while (this.entries.length > maxSize) {
      this.entries.pop();
    }
  }

  remove(url: string): boolean {
    if (url.length === 0) {
      return false;
    }
    const key = cacheKeyForUrl(url);

    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].url === key) {
        this.entries.splice(i, 1);
        return true;
      }
    }
    return false;
  }

  clear(): number {
    const count = this.entries.length;
    this.entries = [];
    return count;
  }
}

function cacheKeyForUrl(url: string): string {
  return url + '#image_size=' + ehSettingsStore.getValue('image_size', 'Auto');
}

function cloneGalleryPage(page: GalleryPage): GalleryPage {
  return {
    pageUrl: page.pageUrl,
    imageUrl: page.imageUrl,
    skipHathKey: page.skipHathKey,
    originImageUrl: page.originImageUrl,
    showKey: page.showKey,
    cachedImagePath: page.cachedImagePath,
    cachedOriginImagePath: page.cachedOriginImagePath
  };
}

export const galleryPageCache: GalleryPageCache = new GalleryPageCache();
