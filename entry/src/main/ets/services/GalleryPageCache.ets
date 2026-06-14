import { GalleryPage } from '../model/GalleryModels';

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

    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].url === url) {
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

    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].url === url) {
        return true;
      }
    }
    return false;
  }

  put(url: string, page: GalleryPage, maxSize: number = 80): void {
    if (url.length === 0) {
      return;
    }

    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].url === url) {
        this.entries.splice(i, 1);
        break;
      }
    }
    this.entries.unshift({ url: url, page: cloneGalleryPage(page) });

    while (this.entries.length > maxSize) {
      this.entries.pop();
    }
  }

  clear(): number {
    const count = this.entries.length;
    this.entries = [];
    return count;
  }
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
