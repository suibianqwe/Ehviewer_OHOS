import { GalleryDetail, GalleryPreview, GallerySite } from '../model/GalleryModels';
import { cloneGalleryDetail, cloneGalleryPreviews } from '../shared/EhShared';
import { EhHttpClient } from './EhHttpClient';

export interface PreviewMergeResult {
  detail: GalleryDetail;
  previewPageSize: number;
}

export interface NextPreviewPageLoadOptions {
  client: EhHttpClient;
  site: GallerySite;
  referer: string;
  pageIndex: number;
  getDetail: () => GalleryDetail;
  isCurrent: () => boolean;
  onMerge: (detail: GalleryDetail) => void;
  onError: (message: string) => void;
}

export interface DetailPreviewPagerOptions {
  client: EhHttpClient;
  site: GallerySite;
  referer: string;
  getDetail: () => GalleryDetail;
  isVisible: () => boolean;
  onMerge: (detail: GalleryDetail) => void;
  onError: (message: string) => void;
}

export function seedPreviewMap(previewMap: Map<number, GalleryPreview>, previews: GalleryPreview[],
  currentPageSize: number): number {
  let nextPageSize = currentPageSize;
  if (previews.length > 0 && (nextPageSize <= 0 || previews.length > nextPageSize)) {
    nextPageSize = previews.length;
  }
  for (let i = 0; i < previews.length; i++) {
    previewMap.set(previews[i].index, previews[i]);
  }
  return nextPageSize;
}

export function mergeGalleryPreviewSets(current: GalleryDetail, loaded: GalleryDetail,
  previewMap?: Map<number, GalleryPreview>, currentPageSize: number = 0): PreviewMergeResult {
  let nextPageSize = currentPageSize;
  if (previewMap !== undefined) {
    nextPageSize = seedPreviewMap(previewMap, loaded.previewSet, nextPageSize);
  }

  const byIndex: Map<number, GalleryPreview> = new Map();
  for (let i = 0; i < current.previewSet.length; i++) {
    byIndex.set(current.previewSet[i].index, current.previewSet[i]);
  }
  for (let i = 0; i < loaded.previewSet.length; i++) {
    byIndex.set(loaded.previewSet[i].index, loaded.previewSet[i]);
  }

  const merged: GalleryPreview[] = Array.from(byIndex.values());
  merged.sort((left: GalleryPreview, right: GalleryPreview) => left.index - right.index);
  const nextDetail = cloneGalleryDetail(current);
  nextDetail.previewSet = cloneGalleryPreviews(merged);
  nextDetail.previewPages = Math.max(nextDetail.previewPages, loaded.previewPages);
  nextDetail.pages = Math.max(nextDetail.pages, loaded.pages);

  if (previewMap !== undefined) {
    nextPageSize = seedPreviewMap(previewMap, nextDetail.previewSet, nextPageSize);
  }
  return {
    detail: nextDetail,
    previewPageSize: nextPageSize
  };
}

export async function loadGalleryPreviewPage(options: NextPreviewPageLoadOptions): Promise<boolean> {
  const current = options.getDetail();
  if (current.previewPages <= 1 || current.gid <= 0 || current.token.length === 0 ||
    options.pageIndex <= 0 || options.pageIndex >= current.previewPages || !options.isCurrent()) {
    return false;
  }

  try {
    const result = await options.client.loadGalleryDetail(current.gid, current.token, options.pageIndex,
      options.site, options.referer);
    if (!options.isCurrent()) {
      return false;
    }
    if (result.ok && result.detail !== null && result.detail.previewSet.length > 0) {
      options.onMerge(result.detail);
      return true;
    }
    options.onError(result.message);
  } catch (error) {
    if (options.isCurrent()) {
      options.onError(String(error));
    }
  }
  return false;
}

export class DetailPreviewPager {
  private serial: number = 0;
  private nextPageIndex: number = 1;
  private loading: boolean = false;

  start(): void {
    this.serial++;
    this.nextPageIndex = 1;
    this.loading = false;
  }

  reset(): void {
    this.start();
  }

  async loadNext(options: DetailPreviewPagerOptions): Promise<void> {
    const current = options.getDetail();
    if (this.loading || current.previewPages <= 1 || this.nextPageIndex >= current.previewPages) {
      return;
    }

    const activeSerial = this.serial;
    const pageIndex = this.nextPageIndex;
    this.loading = true;
    const loaded = await loadGalleryPreviewPage({
      client: options.client,
      site: options.site,
      referer: options.referer,
      pageIndex: pageIndex,
      getDetail: options.getDetail,
      isCurrent: () => activeSerial === this.serial && options.isVisible(),
      onMerge: options.onMerge,
      onError: options.onError
    });
    if (activeSerial !== this.serial) {
      return;
    }
    this.loading = false;
    if (loaded && this.nextPageIndex === pageIndex) {
      this.nextPageIndex = pageIndex + 1;
    }
  }
}
