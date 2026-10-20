import { common } from '@kit.AbilityKit';
import { CoverSearchSource, GalleryDetail, GallerySite } from '../model/GalleryModels';
import { readerPageImageCacheKey } from '../shared/EhShared';
import { EhHttpClient } from './EhHttpClient';
import { EhUrl } from './EhUrl';
import { IMAGE_DOWNLOAD_PRIORITY_INTERACTIVE, readerImageCache } from './ReaderImageCache';

export function createCoverSearchSource(detail: GalleryDetail, site: GallerySite,
  referer: string): CoverSearchSource {
  let previewPageUrl = '';
  let firstIndex = Number.MAX_SAFE_INTEGER;
  for (const preview of detail.previewSet) {
    if (preview.index < firstIndex) {
      firstIndex = preview.index;
      previewPageUrl = preview.pageUrl;
    }
  }
  return {
    gid: detail.gid,
    site: site,
    referer: referer.length > 0 ? referer : EhUrl.getGalleryDetailUrl(detail.gid, detail.token, 0, false, site),
    previewPageUrl: previewPageUrl,
    thumb: detail.thumb === undefined ? '' : detail.thumb
  };
}

export async function prepareCoverSearchImage(context: common.UIAbilityContext, client: EhHttpClient,
  source: CoverSearchSource, isCurrent: () => boolean): Promise<string> {
  if (!isCurrent()) {
    return '';
  }
  if (source.previewPageUrl.length > 0) {
    try {
      const result = await client.loadGalleryPageFast(source.previewPageUrl, source.site, source.referer);
      if (!isCurrent()) {
        return '';
      }
      if (result.ok && result.page !== null && result.page.imageUrl.length > 0) {
        const imageUrl = result.page.imageUrl;
        const pageReferer = result.page.pageUrl.length > 0 ? result.page.pageUrl : source.previewPageUrl;
        const existingPath = readerImageCache.getCachedPath(context, imageUrl);
        if (existingPath.length > 0) {
          return existingPath;
        }
        const path = await readerImageCache.ensureCached(context, imageUrl, pageReferer,
          IMAGE_DOWNLOAD_PRIORITY_INTERACTIVE, undefined, readerPageImageCacheKey(result.page, false),
          { retryLimit: 3 });
        if (path.length > 0) {
          return path;
        }
      }
    } catch (_error) {
      // Keep the existing full-size-first behavior, with the thumbnail as a fallback.
    }
  }
  if (!isCurrent() || source.thumb.length === 0) {
    return '';
  }
  return readerImageCache.ensureCached(context, source.thumb, source.referer,
    IMAGE_DOWNLOAD_PRIORITY_INTERACTIVE, undefined, 'cover-search-' + source.gid.toString());
}
