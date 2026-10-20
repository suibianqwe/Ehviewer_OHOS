import { common } from '@kit.AbilityKit';
import { fileIo as fs, hash } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryPreview } from '../model/GalleryModels';
import { IMAGE_DOWNLOAD_PRIORITY_READER, readerImageCache } from './ReaderImageCache';

// Legacy cloud reads could move a preview sheet into a full-page cache entry.
// Prove byte identity before rejecting/replacing any existing user file.
export class ReaderPageSourceGuard {
  private checks: Map<string, Promise<boolean>> = new Map<string, Promise<boolean>>();
  private rejected: Map<string, string> = new Map<string, string>();
  private repairs: Map<string, Promise<string>> = new Map<string, Promise<string>>();
  private repairSequence: number = 0;

  async isPreview(context: common.UIAbilityContext, path: string, preview: GalleryPreview | undefined,
    previews: GalleryPreview[], referer: string): Promise<boolean> {
    if (path.length === 0 || preview === undefined || !/^https?:\/\//i.test(preview.imageUrl)) {
      return false;
    }
    try {
      const stat = await fs.stat(path);
      const key = path + '|' + stat.size.toString() + '|' + stat.mtime.toString() + '|' + preview.imageUrl;
      const pending = this.checks.get(key);
      if (pending !== undefined) {
        return pending;
      }
      const request = this.compare(context, path, stat.size, preview, previews, referer).catch(() => {
        // Offline/unavailable preview is not evidence of corruption. Retry on a later read.
        this.checks.delete(key);
        return false;
      });
      this.checks.set(key, request);
      if (this.checks.size > 256) {
        this.checks.delete(Array.from(this.checks.keys())[0]);
      }
      return await request;
    } catch (_error) {
      return false;
    }
  }

  private async compare(context: common.UIAbilityContext, path: string, bytes: number, preview: GalleryPreview,
    previews: GalleryPreview[], referer: string): Promise<boolean> {
    let reference = readerImageCache.getCachedPath(context, preview.imageUrl);
    if (reference.length === 0) {
      // A real page smaller than the known sheet bounds cannot be that sheet.
      // This avoids fetching missing preview sheets for ordinary portrait pages.
      if (await this.smallerThanPreviewSheet(path, preview, previews)) {
        return false;
      }
      // This reference is required to open the page. EntryAbility pauses background
      // thumbnails while the independent reader is in front, so it must be promoted.
      reference = await readerImageCache.ensureCached(context, preview.imageUrl, referer,
        IMAGE_DOWNLOAD_PRIORITY_READER, undefined, '', { retryLimit: 1, readerPageUrl: referer });
    }
    if (reference.length === 0) {
      throw new Error('Preview reference unavailable');
    }
    const referenceStat = await fs.stat(reference);
    if (bytes <= 0 || referenceStat.size !== bytes) {
      return false;
    }
    const digest = await hash.hash(path, 'sha256');
    if (digest !== await hash.hash(reference, 'sha256')) {
      return false;
    }
    this.rejected.set(path, digest);
    if (this.rejected.size > 256) {
      this.rejected.delete(Array.from(this.rejected.keys())[0]);
    }
    hilog.warn(0x3210, 'ReaderPageSource', 'Rejected preview sheet as page, index=%{public}d', preview.index);
    return true;
  }

  private async smallerThanPreviewSheet(path: string, preview: GalleryPreview,
    previews: GalleryPreview[]): Promise<boolean> {
    let width = preview.xOffset + preview.width;
    let height = preview.yOffset + preview.height;
    for (let i = 0; i < previews.length; i++) {
      if (previews[i].imageUrl === preview.imageUrl) {
        width = Math.max(width, previews[i].xOffset + previews[i].width);
        height = Math.max(height, previews[i].yOffset + previews[i].height);
      }
    }
    const source = image.createImageSource(path);
    try {
      const info = await source.getImageInfo();
      return info.size.width < width || info.size.height < height;
    } finally {
      await source.release().catch(() => {});
    }
  }

  repairDownload(path: string, replacement: string): Promise<string> {
    const pending = this.repairs.get(path);
    if (pending !== undefined) {
      return pending;
    }
    const request = this.replaceVerifiedPreview(path, replacement).finally(() => this.repairs.delete(path));
    this.repairs.set(path, request);
    return request;
  }

  private async replaceVerifiedPreview(path: string, replacement: string): Promise<string> {
    const badDigest = this.rejected.get(path);
    if (badDigest === undefined || path === replacement) {
      return replacement;
    }
    const suffix = '.preview-backup-' + Date.now().toString() + '-' + (++this.repairSequence).toString();
    const backup = path + suffix;
    const temporary = path + suffix + '.part';
    const extension = /\.(jpg|jpeg|png|webp|gif)$/i.exec(replacement);
    const destination = extension === null ? path : path.replace(/\.[^/.]+$/, extension[0]);
    let backedUp = false;
    try {
      const goodDigest = await hash.hash(replacement, 'sha256');
      if (goodDigest === badDigest || await hash.hash(path, 'sha256') !== badDigest ||
        (destination !== path && await fs.access(destination))) {
        return replacement;
      }
      await fs.copyFile(replacement, temporary);
      if (await hash.hash(temporary, 'sha256') !== goodDigest ||
        await hash.hash(path, 'sha256') !== badDigest) {
        return replacement;
      }
      await fs.rename(path, backup);
      backedUp = true;
      await fs.rename(temporary, destination);
      this.rejected.delete(path);
      this.checks.clear();
      hilog.info(0x3210, 'ReaderPageSource', 'Repaired downloaded page; original retained in preview-backup');
      return destination;
    } catch (_error) {
      if (backedUp) {
        await fs.rename(backup, path).catch(() => {});
      }
      // The verified replacement remains readable even if the download folder is read-only.
      return replacement;
    } finally {
      await fs.unlink(temporary).catch(() => {});
    }
  }
}

export const readerPageSourceGuard: ReaderPageSourceGuard = new ReaderPageSourceGuard();

export function cloudReaderImageKey(gid: number, index: number): string {
  return 'ehviewer://cloud-page/v2/' + gid.toString() + '/' + index.toString();
}
