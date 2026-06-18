import { GalleryDetail, GalleryPreview, GallerySite } from '../model/GalleryModels';
import { cloneGalleryDetail, cloneGalleryPreviews } from '../shared/EhShared';
import { EhHttpClient } from './EhHttpClient';

export interface PreviewMergeResult {
  detail: GalleryDetail;
  previewPageSize: number;
}

export interface RemainingPreviewLoadOptions {
  client: EhHttpClient;
  site: GallerySite;
  referer: string;
  getDetail: () => GalleryDetail;
  isCurrent: () => boolean;
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

export async function loadRemainingGalleryPreviews(options: RemainingPreviewLoadOptions): Promise<void> {
  const initial = options.getDetail();
  if (initial.previewPages <= 1 || initial.gid <= 0 || initial.token.length === 0) {
    return;
  }

  for (let pageIndex = 1; pageIndex < initial.previewPages; pageIndex++) {
    if (!options.isCurrent()) {
      return;
    }

    try {
      const current = options.getDetail();
      const result = await options.client.loadGalleryDetail(current.gid, current.token, pageIndex,
        options.site, options.referer);
      if (!options.isCurrent()) {
        return;
      }
      if (result.ok && result.detail !== null && result.detail.previewSet.length > 0) {
        options.onMerge(result.detail);
      }
    } catch (error) {
      if (options.isCurrent()) {
        options.onError(String(error));
      }
    }
  }
}
