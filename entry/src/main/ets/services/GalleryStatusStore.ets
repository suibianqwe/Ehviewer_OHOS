import { GalleryInfo } from '../model/GalleryModels';

export const GALLERY_STATUS_REVISION_KEY: string = 'gallery_status_revision';

// 卡片只关心任务是否存在，进度、排序和标签变化不应刷新状态标记。
export class GalleryStatusStore {
  private downloads: Set<number> = new Set<number>();
  private localFavorites: Set<number> = new Set<number>();
  private cloudFavorites: Map<number, boolean> = new Map<number, boolean>();
  private cloudAccount: string = '';

  setCloudAccount(account: string): void {
    if (this.cloudAccount !== account) {
      this.cloudAccount = account;
      this.cloudFavorites.clear();
      this.notifyChanged();
    }
  }

  syncDownloads(gids: number[]): void {
    if (!this.sameMembers(this.downloads, gids)) {
      this.downloads = new Set<number>(gids);
      this.notifyChanged();
    }
  }

  syncLocalFavorites(gids: number[]): void {
    if (!this.sameMembers(this.localFavorites, gids)) {
      this.localFavorites = new Set<number>(gids);
      this.notifyChanged();
    }
  }

  hasDownload(gid: number): boolean {
    return gid > 0 && this.downloads.has(gid);
  }

  isFavorite(gallery: GalleryInfo): boolean {
    if (gallery.gid <= 0) {
      return false;
    }
    // 本地收藏以存储为准，避免缓存中的 -1 在删除后仍显示爱心。
    const cloud = this.cloudFavorites.get(gallery.gid);
    return this.localFavorites.has(gallery.gid) ||
      (cloud !== undefined ? cloud : gallery.favoriteSlot >= 0 && gallery.favoriteSlot <= 10);
  }

  setCloudFavorite(gid: number, favorite: boolean): void {
    if (gid > 0 && this.cloudFavorites.get(gid) !== favorite) {
      this.cloudFavorites.set(gid, favorite);
      this.notifyChanged();
    }
  }

  syncCloudFavorites(galleries: GalleryInfo[]): void {
    let changed = false;
    for (const gallery of galleries) {
      if (gallery.gid <= 0) {
        continue;
      }
      const favorite = gallery.favoriteSlot >= 0 && gallery.favoriteSlot <= 10;
      if (this.cloudFavorites.get(gallery.gid) !== favorite) {
        this.cloudFavorites.set(gallery.gid, favorite);
        changed = true;
      }
    }
    if (changed) {
      this.notifyChanged();
    }
  }

  private sameMembers(current: Set<number>, gids: number[]): boolean {
    const next = new Set<number>(gids);
    if (current.size !== next.size) {
      return false;
    }
    for (const gid of next) {
      if (!current.has(gid)) {
        return false;
      }
    }
    return true;
  }

  private notifyChanged(): void {
    const revision = AppStorage.get<number>(GALLERY_STATUS_REVISION_KEY) ?? 0;
    AppStorage.setOrCreate<number>(GALLERY_STATUS_REVISION_KEY, revision + 1);
  }
}

export const galleryStatusStore: GalleryStatusStore = new GalleryStatusStore();
