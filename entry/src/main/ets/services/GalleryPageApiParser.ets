import { GalleryPage } from '../model/GalleryModels';

const API_IMAGE_URL_PATTERN: RegExp = /<img[^>]*src=["']([^"']+)["'][^>]*style/i;
const API_SKIP_HATH_KEY_PATTERN: RegExp = /onclick=["']return nl\(['"]([^'")]+)['"]\)/i;
const API_ORIGIN_IMAGE_URL_PATTERN: RegExp = /<a[^>]+href=["']([^"']*fullimg[^"']*)["'][^>]*>/i;
const API_ORIGIN_IMAGE_PROMPT_PATTERN: RegExp = /prompt\(['"]Copy the URL below\.['"],\s*['"]([^'"]+)['"]\)/i;

export interface GalleryPageApiParseResult {
  page: GalleryPage | null;
  warning: string;
}

interface GalleryPageApiBody {
  error?: string;
  i3?: string;
  i6?: string;
  i7?: string | null;
}

export function parseGalleryPageApi(body: string, pageUrl: string, showKey: string): GalleryPageApiParseResult {
  let parsed: GalleryPageApiBody;
  try {
    parsed = JSON.parse(body) as GalleryPageApiBody;
  } catch (error) {
    return { page: null, warning: 'Cannot parse showpage JSON' };
  }

  if (typeof parsed.error === 'string' && parsed.error.length > 0) {
    return { page: null, warning: parsed.error };
  }

  const imageHtml = typeof parsed.i3 === 'string' ? parsed.i3 : '';
  const actionHtml = typeof parsed.i6 === 'string' ? parsed.i6 : '';
  const originHtml = typeof parsed.i7 === 'string' ? parsed.i7 : actionHtml;
  const imageUrl = parseFirst(imageHtml, API_IMAGE_URL_PATTERN);
  const fallbackUrl = parseFirst(actionHtml, API_ORIGIN_IMAGE_PROMPT_PATTERN);
  const displayUrl = imageUrl.length > 0 ? imageUrl : fallbackUrl;
  if (displayUrl.length === 0) {
    return { page: null, warning: 'No image URL parsed from showpage API' };
  }

  return {
    page: {
      pageUrl: pageUrl,
      imageUrl: displayUrl,
      skipHathKey: parseFirst(actionHtml, API_SKIP_HATH_KEY_PATTERN),
      originImageUrl: parseOriginUrl(originHtml, actionHtml),
      showKey: showKey
    },
    warning: ''
  };
}

function parseOriginUrl(primaryHtml: string, fallbackHtml: string): string {
  const primary = parseFirst(primaryHtml, API_ORIGIN_IMAGE_URL_PATTERN);
  if (primary.length > 0) {
    return primary;
  }
  return parseFirst(fallbackHtml, API_ORIGIN_IMAGE_URL_PATTERN);
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
