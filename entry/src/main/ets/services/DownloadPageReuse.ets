import { GalleryDetail, GalleryPreview } from '../model/GalleryModels';
import { parseGalleryPageUrl } from './GalleryPageParser';

export interface DownloadPageCopy {
  sourceIndex: number;
  targetIndex: number;
}

function pageIdentity(preview: GalleryPreview): string {
  const url = preview.pageUrl.startsWith('/') ? 'https://e-hentai.org' + preview.pageUrl : preview.pageUrl;
  const page = parseGalleryPageUrl(url);
  return page !== null && Number.isSafeInteger(preview.index) && preview.index >= 0 && page.pageIndex === preview.index &&
    /^[a-f0-9]{10,40}$/i.test(page.pageToken) ? page.pageToken.toLowerCase() : '';
}

export function completeDownloadManifest(detail: GalleryDetail): boolean {
  return detail.pages > 0 && detail.previewSet.length === detail.pages &&
    detail.previewSet.every((preview: GalleryPreview, index: number): boolean =>
      preview.index === index && pageIdentity(preview).length > 0);
}

export function planDownloadPageReuse(source: GalleryPreview[], target: GalleryPreview[]): DownloadPageCopy[] {
  const byIdentity = new Map<string, number>();
  for (const preview of source) {
    const identity = pageIdentity(preview);
    if (identity.length > 0 && !byIdentity.has(identity)) {
      byIdentity.set(identity, preview.index);
    }
  }
  const copies: DownloadPageCopy[] = [];
  for (const preview of target) {
    const index = byIdentity.get(pageIdentity(preview));
    if (index !== undefined) copies.push({ sourceIndex: index, targetIndex: preview.index });
  }
  return copies;
}

export function spiderPreviewIdentities(text: string, gid: number): GalleryPreview[] {
  const previews: GalleryPreview[] = [];
  // Android's VERSION1/2 header is followed by zero-based page/token pairs.
  for (const line of text.split(/\r?\n/)) {
    const pair = /^(\d+)\s+([a-f0-9]{10,40})\s*$/i.exec(line);
    if (pair !== null) {
      const index = Number(pair[1]);
      if (Number.isSafeInteger(index)) {
        previews.push({ index: index, pageUrl: 'https://e-hentai.org/s/' + pair[2] + '/' + gid + '-' + (index + 1),
          imageUrl: '', width: 0, height: 0, xOffset: 0, yOffset: 0 });
      }
    }
  }
  return previews;
}
