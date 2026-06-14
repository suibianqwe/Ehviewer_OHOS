import { GalleryCategory, GalleryInfo } from '../model/GalleryModels';

export interface GalleryListParseResult {
  pages: number;
  nextPage: number;
  resultCount: string;
  galleries: GalleryInfo[];
  warning: string;
}

const DETAIL_LINK_PATTERN: RegExp = /(?:https?:\/\/(?:e-hentai\.org|exhentai\.org))?\/g\/(\d+)\/([A-Za-z0-9]+)\//;
const PAGE_COUNT_PATTERN: RegExp = /(\d+)\s+pages?/i;
const RATING_PATTERN: RegExp = /(?:title|alt)=["'](?:Average:|Rating:)?\s*([0-5](?:\.\d+)?)["']/i;
const RESULT_COUNT_PATTERN: RegExp = /(?:Found|Showing)\s+([^<]+?)\s+results/i;
const NEXT_PAGE_PATTERN: RegExp = /[?&](?:page|next)=(\d+)/;

export function parseGalleryList(body: string): GalleryListParseResult {
  const galleries: GalleryInfo[] = [];
  const rows: string[] = splitGalleryRows(body);
  for (let i = 0; i < rows.length; i++) {
    const gallery = parseGalleryInfo(rows[i]);
    if (gallery !== null) {
      galleries.push(gallery);
    }
  }

  return {
    pages: parsePages(body),
    nextPage: parseNextPage(body),
    resultCount: parseResultCount(body),
    galleries: galleries,
    warning: galleries.length === 0 ? parseWarning(body) : ''
  };
}

function splitGalleryRows(body: string): string[] {
  const tableRows = splitTableRows(body);
  if (tableRows.length > 0) {
    return tableRows;
  }
  return splitThumbnailRows(body);
}

function splitTableRows(body: string): string[] {
  const rows: string[] = [];
  const tableStart = findItgTableStart(body);
  const tableEnd = tableStart < 0 ? -1 : body.indexOf('</table>', tableStart);
  const source = tableStart >= 0 && tableEnd > tableStart ? body.substring(tableStart, tableEnd + 8) : body;
  const pattern = /<tr[\s\S]*?<\/tr>/gi;
  let match: RegExpExecArray | null = pattern.exec(source);
  while (match !== null) {
    const row = match[0];
    if (row.indexOf('/g/') >= 0 && row.indexOf('<th') < 0) {
      rows.push(row);
    }
    match = pattern.exec(source);
  }
  return rows;
}

function splitThumbnailRows(body: string): string[] {
  const starts: number[] = [];
  const rows: string[] = [];
  const pattern = /<div[^>]+class=["'][^"']*\b(?:gl1t|gl1c|gl1e|gl3t)\b[^"']*["'][^>]*>/gi;
  let match: RegExpExecArray | null = pattern.exec(body);
  while (match !== null) {
    starts.push(match.index);
    match = pattern.exec(body);
  }

  for (let i = 0; i < starts.length; i++) {
    const start = starts[i];
    const end = i + 1 < starts.length ? starts[i + 1] : findThumbnailEnd(body, start);
    const row = body.substring(start, end);
    if (row.indexOf('/g/') >= 0) {
      rows.push(row);
    }
  }
  return rows;
}

function findItgTableStart(body: string): number {
  const match = /<table[^>]+class=["'][^"']*\bitg\b[^"']*["'][^>]*>/i.exec(body);
  return match === null ? -1 : match.index;
}

function findThumbnailEnd(body: string, start: number): number {
  const footer = body.indexOf('<table class="ptb"', start);
  return footer > start ? footer : body.length;
}

function parseGalleryInfo(row: string): GalleryInfo | null {
  const link = DETAIL_LINK_PATTERN.exec(row);
  if (link === null) {
    return null;
  }

  const gid = parseIntSafe(link[1], 0);
  if (gid === 0) {
    return null;
  }

  return {
    gid: gid,
    token: link[2],
    title: parseTitle(row),
    thumb: parseThumb(row),
    category: parseCategory(row),
    posted: parseById(row, 'posted_' + gid.toString()),
    uploader: parseUploader(row),
    rating: parseRating(row),
    rated: false,
    simpleTags: parseSimpleTags(row),
    pages: parseItemPages(row),
    thumbWidth: parseThumbWidth(row),
    thumbHeight: parseThumbHeight(row),
    favoriteSlot: -2,
    tagList: parseTagList(row)
  };
}

function parseTitle(row: string): string {
  const linkTitle = /<div[^>]+class=["'][^"']*\bglink\b[^"']*["'][^>]*>([\s\S]*?)<\/div>/i.exec(row);
  if (linkTitle !== null) {
    return cleanText(linkTitle[1]);
  }

  const thumbnailTitle = /<div[^>]+class=["'][^"']*\bgl4t\b[^"']*\bglname\b[^"']*["'][^>]*>([\s\S]*?)<\/div>/i.exec(row);
  if (thumbnailTitle !== null) {
    return cleanText(thumbnailTitle[1]);
  }

  const nameTitle = /<div[^>]+class=["'][^"']*\bglname\b[^"']*["'][^>]*>([\s\S]*?)<\/div>/i.exec(row);
  if (nameTitle !== null) {
    return cleanText(nameTitle[1]);
  }

  const titleAttr = /title=["']([^"']+)["']/i.exec(row);
  if (titleAttr !== null) {
    return decodeHtml(titleAttr[1]).trim();
  }
  return 'Untitled';
}

function parseThumb(row: string): string {
  const dataSrc = /data-src=["']([^"']+)["']/i.exec(row);
  if (dataSrc !== null) {
    return decodeHtml(dataSrc[1]);
  }

  const src = /<img[^>]+src=["']([^"']+)["']/i.exec(row);
  return src === null ? '' : decodeHtml(src[1]);
}

function parseCategory(row: string): number {
  const category = /class=["'][^"']*(?:\bcn\b|\bcs\b)[^"']*["'][^>]*>([^<]+)</i.exec(row);
  if (category === null) {
    return GalleryCategory.Unknown;
  }
  return categoryNameToValue(cleanText(category[1]));
}

function parseUploader(row: string): string {
  const uploader = /\/uploader\/[^"']+["'][^>]*>([\s\S]*?)<\/a>/i.exec(row);
  return uploader === null ? '' : cleanText(uploader[1]);
}

function parseRating(row: string): number {
  const rating = RATING_PATTERN.exec(row);
  return rating === null ? -1 : parseFloatSafe(rating[1], -1);
}

function parseSimpleTags(row: string): string[] {
  const tags: string[] = [];
  const pattern = /title=["']([^"']+:[^"']+)["']/gi;
  let match: RegExpExecArray | null = pattern.exec(row);
  while (match !== null) {
    tags.push(decodeHtml(match[1]));
    match = pattern.exec(row);
  }
  return tags;
}

function parseTagList(row: string): string[] {
  const tags: string[] = [];
  const pattern = /class=["'](?:gt|gtl)["'][^>]*title=["']([^"']+)["']/gi;
  let match: RegExpExecArray | null = pattern.exec(row);
  while (match !== null) {
    tags.push(decodeHtml(match[1]));
    match = pattern.exec(row);
  }
  return tags;
}

function parseItemPages(row: string): number {
  const pages = PAGE_COUNT_PATTERN.exec(row);
  return pages === null ? 0 : parseIntSafe(pages[1], 0);
}

function parseThumbWidth(row: string): number {
  const size = /height:(\d+)px;width:(\d+)px/i.exec(row);
  return size === null ? 0 : parseIntSafe(size[2], 0);
}

function parseThumbHeight(row: string): number {
  const size = /height:(\d+)px;width:(\d+)px/i.exec(row);
  return size === null ? 0 : parseIntSafe(size[1], 0);
}

function parseById(row: string, id: string): string {
  const pattern = new RegExp("<[^>]+id=[\"']" + escapeRegExp(id) + "[\"'][^>]*>([\\s\\S]*?)<\\/[^>]+>", 'i');
  const match = pattern.exec(row);
  return match === null ? '' : cleanText(match[1]);
}

function parsePages(body: string): number {
  const pager = /class=["']ptt["'][\s\S]*?<\/table>/i.exec(body);
  if (pager === null) {
    return body.indexOf('No hits found') >= 0 ? 0 : 1;
  }

  const numbers: number[] = [];
  const pattern = />(\d+)</g;
  let match: RegExpExecArray | null = pattern.exec(pager[0]);
  while (match !== null) {
    numbers.push(parseIntSafe(match[1], 0));
    match = pattern.exec(pager[0]);
  }
  return numbers.length === 0 ? 1 : numbers[numbers.length - 1];
}

function parseNextPage(body: string): number {
  const match = NEXT_PAGE_PATTERN.exec(body);
  return match === null ? -1 : parseIntSafe(match[1], -1);
}

function parseResultCount(body: string): string {
  const match = RESULT_COUNT_PATTERN.exec(cleanText(body));
  return match === null ? '' : match[1].trim();
}

function parseWarning(body: string): string {
  if (body.length > 0 && body.indexOf('<') < 0) {
    return 'Response is not HTML; check content encoding or network interception';
  }
  if (body.indexOf('No hits found') >= 0) {
    return 'No hits found';
  }
  if (body.indexOf('Your IP address has been temporarily banned') >= 0) {
    return 'IP temporarily banned';
  }
  if (body.indexOf('Your IP address has been banned') >= 0) {
    return 'IP banned';
  }
  if (body.indexOf('Please wait') >= 0 && body.indexOf('seconds') >= 0) {
    return 'Server asked to wait before retrying';
  }
  if (body.indexOf('cloudflare') >= 0 || body.indexOf('Cloudflare') >= 0) {
    return 'Blocked by Cloudflare or browser challenge';
  }
  if (body.indexOf('Content Warning') >= 0 || body.indexOf('content warning') >= 0 ||
    body.indexOf('nw=') >= 0) {
    return 'Content warning page returned; retry after Cookie refresh';
  }
  if (body.indexOf('login') >= 0 && body.indexOf('ipb_member_id') >= 0) {
    return 'Login or Cookie required';
  }
  if (body.indexOf('You do not have any watched tags') >= 0) {
    return 'No watched tags';
  }
  return 'No gallery rows parsed';
}

function categoryNameToValue(name: string): number {
  const normalized = name.toLowerCase().replace(/\s+/g, '');
  if (normalized === 'misc') {
    return GalleryCategory.Misc;
  }
  if (normalized === 'doujinshi') {
    return GalleryCategory.Doujinshi;
  }
  if (normalized === 'manga') {
    return GalleryCategory.Manga;
  }
  if (normalized === 'artistcg' || normalized === 'artistcgsets') {
    return GalleryCategory.ArtistCg;
  }
  if (normalized === 'gamecg' || normalized === 'gamecgsets') {
    return GalleryCategory.GameCg;
  }
  if (normalized === 'imageset' || normalized === 'imagesets') {
    return GalleryCategory.ImageSet;
  }
  if (normalized === 'cosplay') {
    return GalleryCategory.Cosplay;
  }
  if (normalized === 'asianporn') {
    return GalleryCategory.AsianPorn;
  }
  if (normalized === 'non-h') {
    return GalleryCategory.NonH;
  }
  if (normalized === 'western') {
    return GalleryCategory.Western;
  }
  return GalleryCategory.Unknown;
}

function cleanText(value: string): string {
  return decodeHtml(value.replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
}

function decodeHtml(value: string): string {
  return value
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, '\'')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

function parseIntSafe(value: string, fallback: number): number {
  const parsed = Number.parseInt(value);
  return Number.isNaN(parsed) ? fallback : parsed;
}

function parseFloatSafe(value: string, fallback: number): number {
  const parsed = Number.parseFloat(value);
  return Number.isNaN(parsed) ? fallback : parsed;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
