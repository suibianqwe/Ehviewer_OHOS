import { GalleryCategory, GalleryDetail, GallerySite, GalleryTagGroup } from '../model/GalleryModels';
import { EhUrl, ListMode } from './EhUrl';

export interface DetailSearchRequest {
  title: string;
  keyword: string;
  mode: ListMode;
  category: number;
  imagePath: string;
  useSimilarityScan: boolean;
  onlySearchCovers: boolean;
  showExpunged: boolean;
}

export function createTagSearchRequest(namespace: string, tag: string): DetailSearchRequest | null {
  const trimmedNamespace = namespace.trim();
  const trimmedTag = tag.trim();
  if (trimmedNamespace.length === 0 || trimmedTag.length === 0) {
    return null;
  }
  const tagQuery = trimmedTag.indexOf(' ') >= 0 ? '"' + trimmedTag.replace(/"/g, '\\"') + '"' : trimmedTag;
  const keyword = trimmedNamespace + ':' + tagQuery;
  return createKeywordSearchRequest(keyword, ListMode.Tag, keyword);
}

export function createSimilarGallerySearch(detail: GalleryDetail): DetailSearchRequest | null {
  const title = extractSimilarTitle(detail.title);
  if (title.length > 0) {
    return createKeywordSearchRequest('"' + title + '"', ListMode.Normal, 'Similar');
  }
  const artist = firstArtistTag(detail.tags);
  if (artist.length > 0) {
    return createKeywordSearchRequest('artist:' + artist, ListMode.Tag, 'Similar');
  }
  if (detail.uploader !== undefined && detail.uploader.length > 0) {
    return createKeywordSearchRequest(detail.uploader, ListMode.Uploader, 'Similar');
  }
  return null;
}

export function createCoverSearchRequest(imagePath: string): DetailSearchRequest {
  return {
    title: 'Search cover',
    keyword: '',
    mode: ListMode.ImageSearch,
    category: GalleryCategory.None,
    imagePath: imagePath,
    useSimilarityScan: true,
    onlySearchCovers: false,
    showExpunged: true
  };
}

export function createKeywordSearchRequest(keyword: string, mode: ListMode, title: string): DetailSearchRequest {
  return {
    title: title.length > 0 ? title : 'Search',
    keyword: keyword,
    mode: mode,
    category: GalleryCategory.None,
    imagePath: '',
    useSimilarityScan: false,
    onlySearchCovers: false,
    showExpunged: false
  };
}

export function createUploaderSearchRequest(uploader: string): DetailSearchRequest | null {
  const value = uploader.trim();
  if (value.length === 0) {
    return null;
  }
  return createKeywordSearchRequest(value, ListMode.Uploader, value);
}

export function createCategorySearchRequest(category: number, title: string): DetailSearchRequest {
  return {
    title: title.length > 0 ? title : 'Search',
    keyword: '',
    mode: ListMode.Normal,
    category: category,
    imagePath: '',
    useSimilarityScan: false,
    onlySearchCovers: false,
    showExpunged: false
  };
}

export function archiveUnavailableReason(detailLoaded: boolean, detail: GalleryDetail): string {
  if (!detailLoaded || detail.gid <= 0 || detail.archiveUrl.length === 0) {
    return 'Archive needs a loaded gallery';
  }
  if (detail.apiUid < 0) {
    return 'Sign in first';
  }
  return '';
}

export function detailArchiveReferer(detail: GalleryDetail, site: GallerySite): string {
  return detail.archiveUrl.length > 0 ? detail.archiveUrl :
    EhUrl.getGalleryDetailUrl(detail.gid, detail.token, 0, false, site);
}

export function detailCoverCacheKey(detail: GalleryDetail): string {
  return 'cover-search-' + detail.gid.toString();
}

function extractSimilarTitle(title: string): string {
  let value = title
    .replace(/^(?:(?:\([^\)]*\))|(?:\[[^\]]*\])|(?:\{[^\}]*\})|(?:~[^~]*~)|\s+)*/g, '')
    .replace(/(?:\s+ch\.[\s\d-]+)?(?:(?:\([^\)]*\))|(?:\[[^\]]*\])|(?:\{[^\}]*\})|(?:~[^~]*~)|\s+)*$/gi, '');
  const splitIndex = value.indexOf('|');
  if (splitIndex >= 0) {
    value = value.substring(0, splitIndex);
  }
  return value.trim();
}

function firstArtistTag(groups: GalleryTagGroup[]): string {
  for (let i = 0; i < groups.length; i++) {
    if (groups[i].namespace === 'artist' && groups[i].tags.length > 0) {
      return groups[i].tags[0];
    }
  }
  return '';
}
