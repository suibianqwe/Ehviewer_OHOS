import {
  GalleryPage,
} from '../model/GalleryModels';

const IMAGE_URL_PATTERN: RegExp = /<img[^>]*src=["']([^"']+)["'][^>]*style/i;
const IMAGE_CONTAINER_SRC_PATTERN: RegExp =
  /<div[^>]*id=["']i3["'][^>]*>[\s\S]*?<img[^>]*src=["']([^"']+)["'][^>]*>/i;
const IMAGE_ID_SRC_PATTERN: RegExp = /<img[^>]*id=["']img["'][^>]*src=["']([^"']+)["'][^>]*>/i;
const IMAGE_SRC_ID_PATTERN: RegExp = /<img[^>]*src=["']([^"']+)["'][^>]*id=["']img["'][^>]*>/i;
const IMAGE_SRC_ACTION_PATTERN: RegExp = /<img[^>]*src=["']([^"']+)["'][^>]*(onclick|onerror|alt|title)=/i;
const IMAGE_LINK_PATTERN: RegExp = /<a[^>]+href=["']([^"']+)["'][^>]*>\s*<img/i;
const SKIP_HATH_KEY_PATTERN: RegExp = /onclick=["']return nl\(['"]([^'")]+)['"]\)/i;
const ORIGIN_IMAGE_URL_PATTERN: RegExp = /<a[^>]+href=["']([^"']*fullimg[^"']*)["'][^>]*>/i;
const ORIGIN_IMAGE_PROMPT_PATTERN: RegExp = /prompt\(['"]Copy the URL below\.['"],\s*['"]([^'"]+)['"]\)/i;
const SHOW_KEY_PATTERN: RegExp = /var\s+showkey\s*=\s*["']([0-9a-z]+)["'];/i;

export interface GalleryPageParseResult {
  page: GalleryPage | null;
  warning: string;
}

export function parseGalleryPage(body: string, pageUrl: string = ''): GalleryPageParseResult {
  const imageUrl = parseImageUrl(body);
  const showKey = parseFirst(body, SHOW_KEY_PATTERN);
  if (imageUrl.length === 0) {
    return { page: null, warning: 'No image URL parsed' };
  }

  return {
    page: {
      pageUrl: pageUrl,
      imageUrl: imageUrl,
      skipHathKey: parseFirst(body, SKIP_HATH_KEY_PATTERN),
      originImageUrl: parseOriginImageUrl(body),
      showKey: showKey
    },
    warning: showKey.length === 0 ? 'Image parsed without showkey' : ''
  };
}

function parseImageUrl(body: string): string {
  const container = IMAGE_CONTAINER_SRC_PATTERN.exec(body);
  if (container !== null && isImageUrlCandidate(normalizeImageUrl(container[1]))) {
    return normalizeImageUrl(container[1]);
  }

  const idBeforeSrc = IMAGE_ID_SRC_PATTERN.exec(body);
  if (idBeforeSrc !== null) {
    return normalizeImageUrl(idBeforeSrc[1]);
  }

  const srcBeforeId = IMAGE_SRC_ID_PATTERN.exec(body);
  if (srcBeforeId !== null) {
    return normalizeImageUrl(srcBeforeId[1]);
  }

  const primary = IMAGE_URL_PATTERN.exec(body);
  if (primary !== null) {
    return normalizeImageUrl(primary[1]);
  }

  const actionImage = IMAGE_SRC_ACTION_PATTERN.exec(body);
  if (actionImage !== null) {
    return normalizeImageUrl(actionImage[1]);
  }

  const imageLink = IMAGE_LINK_PATTERN.exec(body);
  if (imageLink !== null) {
    const link = normalizeImageUrl(imageLink[1]);
    if (isImageUrlCandidate(link)) {
      return link;
    }
  }

  return '';
}

function parseOriginImageUrl(body: string): string {
  const direct = ORIGIN_IMAGE_URL_PATTERN.exec(body);
  if (direct !== null) {
    return decodeHtml(direct[1]);
  }

  const prompt = ORIGIN_IMAGE_PROMPT_PATTERN.exec(body);
  return prompt === null ? '' : decodeHtml(prompt[1]);
}

function parseFirst(body: string, pattern: RegExp): string {
  const match = pattern.exec(body);
  return match === null ? '' : decodeHtml(match[1]);
}

function decodeHtml(value: string): string {
  return value
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, '\'')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

function normalizeImageUrl(value: string): string {
  return decodeHtml(value).trim();
}

function isImageUrlCandidate(value: string): boolean {
  const lower = value.split('?')[0].toLowerCase();
  return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp') ||
    lower.endsWith('.gif');
}

export interface GalleryPageUrlInfo {
  pageToken: string;
  gid: number;
  pageIndex: number;
}

export function parseGalleryPageUrl(url: string): GalleryPageUrlInfo | null {
  const match = /^https?:\/\/[^\/?#]+\/s\/([^\/?#]+)\/(\d+)-(\d+)/i.exec(url);
  if (match === null) {
    return null;
  }

  const gid = Number.parseInt(match[2]);
  const page = Number.parseInt(match[3]);
  if (Number.isNaN(gid) || Number.isNaN(page) || page <= 0) {
    return null;
  }

  return {
    pageToken: match[1],
    gid: gid,
    pageIndex: page - 1
  };
}
