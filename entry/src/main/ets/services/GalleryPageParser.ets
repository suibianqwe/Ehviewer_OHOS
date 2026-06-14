import { GalleryPage } from '../model/GalleryModels';

const IMAGE_URL_PATTERN: RegExp = /<img[^>]+id=["']img["'][^>]+src=["']([^"']+)["'][^>]*style/i;
const FALLBACK_IMAGE_URL_PATTERN: RegExp = /<img[^>]*src=["']([^"']+)["'][^>]*style/i;
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
  const primary = IMAGE_URL_PATTERN.exec(body);
  if (primary !== null) {
    return decodeHtml(primary[1]);
  }

  const fallback = FALLBACK_IMAGE_URL_PATTERN.exec(body);
  return fallback === null ? '' : decodeHtml(fallback[1]);
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
