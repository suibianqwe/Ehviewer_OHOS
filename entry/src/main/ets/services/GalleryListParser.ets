import { GalleryCategory, GalleryInfo } from '../model/GalleryModels';

export enum GalleryListDisplayMode {
  Unknown = 'unknown',
  Minimal = 'minimal',
  MinimalPlus = 'minimal+',
  Compact = 'compact',
  Extended = 'extended',
  Thumbnail = 'thumbnail'
}

export interface GalleryListParseResult {
  displayMode: GalleryListDisplayMode;
  pages: number;
  nextPage: number;
  nextUrl: string;
  resultCount: string;
  galleries: GalleryInfo[];
  warning: string;
}

const DETAIL_LINK_PATTERN: RegExp = /(?:https?:\/\/(?:e-hentai\.org|exhentai\.org))?\/g\/(\d+)\/([A-Za-z0-9]+)\//;
const PAGE_COUNT_PATTERN: RegExp = /(\d+)\s+pages?/i;
const RATING_TEXT_PATTERN: RegExp = /(?:title|alt)=["'](?:Average:|Rating:)?\s*([0-5](?:\.\d+)?)["']/i;
const RATING_STYLE_PATTERN: RegExp = /-?(\d+)px/g;
const FAVORITE_SLOT_PATTERN: RegExp = /background-color:\s*rgba\((\d+),\s*(\d+),\s*(\d+),/i;
const RESULT_COUNT_PATTERN: RegExp = /(?:Found|Showing)\s+([^<]+?)\s+results/i;
const NEXT_PAGE_PATTERN: RegExp = /[?&](?:page|next)=(\d+)/;
const FAVORITE_SLOT_RGB: string[][] = [
  ['0', '0', '0'],
  ['240', '0', '0'],
  ['240', '160', '0'],
  ['208', '208', '0'],
  ['0', '128', '0'],
  ['144', '240', '64'],
  ['64', '176', '240'],
  ['0', '0', '240'],
  ['80', '0', '128'],
  ['224', '128', '224']
];

export function parseGalleryList(body: string): GalleryListParseResult {
  const galleries: GalleryInfo[] = [];
  const displayMode = detectDisplayMode(body);
  const rows: string[] = splitGalleryRows(body, displayMode);
  for (let i = 0; i < rows.length; i++) {
    const gallery = parseGalleryInfo(rows[i], displayMode);
    if (gallery !== null) {
      galleries.push(gallery);
    }
  }

  return {
    displayMode: displayMode,
    pages: parsePages(body),
    nextPage: parseNextPage(body),
    nextUrl: parseNextUrl(body),
    resultCount: parseResultCount(body),
    galleries: galleries,
    warning: galleries.length === 0 ? parseWarning(body) : ''
  };
}

function detectDisplayMode(body: string): GalleryListDisplayMode {
  const selected = /<option\b[^>]+value=["']([^"']+)["'][^>]*selected=["']selected["'][^>]*>/i.exec(body);
  if (selected !== null) {
    const selectedValue = selected[1].toLowerCase();
    if (selectedValue === 'm') {
      return GalleryListDisplayMode.Minimal;
    }
    if (selectedValue === 'p') {
      return GalleryListDisplayMode.MinimalPlus;
    }
    if (selectedValue === 'l') {
      return GalleryListDisplayMode.Compact;
    }
    if (selectedValue === 'e') {
      return GalleryListDisplayMode.Extended;
    }
    if (selectedValue === 't') {
      return GalleryListDisplayMode.Thumbnail;
    }
  }

  const itgClass = parseItgClass(body);
  if (hasClass(itgClass, 'gltm')) {
    return GalleryListDisplayMode.Minimal;
  }
  if (hasClass(itgClass, 'gltc')) {
    return GalleryListDisplayMode.Compact;
  }
  if (hasClass(itgClass, 'glte')) {
    return GalleryListDisplayMode.Extended;
  }
  if (hasClass(itgClass, 'gld')) {
    return GalleryListDisplayMode.Thumbnail;
  }

  if (/<div[^>]+class=["'][^"']*\bgl1t\b[^"']*["'][^>]*>/i.test(body)) {
    return GalleryListDisplayMode.Thumbnail;
  }
  if (/<td[^>]+class=["'][^"']*\bgl1c\b[^"']*["'][^>]*>/i.test(body)) {
    return GalleryListDisplayMode.Compact;
  }
  if (/<td[^>]+class=["'][^"']*\bgl1e\b[^"']*["'][^>]*>/i.test(body)) {
    return GalleryListDisplayMode.Extended;
  }
  if (/<td[^>]+class=["'][^"']*\bgl1m\b[^"']*["'][^>]*>/i.test(body)) {
    return GalleryListDisplayMode.Minimal;
  }
  return GalleryListDisplayMode.Unknown;
}

function splitGalleryRows(body: string, displayMode: GalleryListDisplayMode): string[] {
  if (displayMode === GalleryListDisplayMode.Thumbnail) {
    return splitThumbnailRows(body);
  }

  const tableRows = splitTableRows(body, displayMode);
  if (tableRows.length > 0 || displayMode !== GalleryListDisplayMode.Unknown) {
    return tableRows;
  }
  return splitThumbnailRows(body);
}

function splitTableRows(body: string, displayMode: GalleryListDisplayMode): string[] {
  const rows: string[] = [];
  const tableStart = findItgTableStart(body, displayMode);
  const tableEnd = tableStart < 0 ? -1 : body.indexOf('</table>', tableStart);
  const source = tableStart >= 0 && tableEnd > tableStart ? body.substring(tableStart, tableEnd + 8) : body;
  let index = 0;
  while (index < source.length) {
    const start = source.substring(index).search(/<tr\b/i);
    if (start < 0) {
      break;
    }
    const absoluteStart = index + start;
    const row = findFirstTagBlock(source.substring(absoluteStart), 'tr');
    if (row.length === 0) {
      break;
    }
    if (row.indexOf('/g/') >= 0 && row.indexOf('<th') < 0) {
      rows.push(row);
    }
    index = absoluteStart + row.length;
  }
  return rows;
}

function splitThumbnailRows(body: string): string[] {
  const starts: number[] = [];
  const rows: string[] = [];
  const pattern = /<div[^>]+class=["'][^"']*\b(?:gl1t|gl1c|gl1e)\b[^"']*["'][^>]*>/gi;
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

function findItgTableStart(body: string, displayMode: GalleryListDisplayMode): number {
  const modeClass = tableClassForMode(displayMode);
  if (modeClass.length > 0) {
    const modePattern = new RegExp("<table[^>]+class=[\"'][^\"']*\\bitg\\b[^\"']*\\b" + modeClass + "\\b[^\"']*[\"'][^>]*>", 'i');
    const modeMatch = modePattern.exec(body);
    if (modeMatch !== null) {
      return modeMatch.index;
    }
  }

  const match = /<table[^>]+class=["'][^"']*\bitg\b[^"']*["'][^>]*>/i.exec(body);
  return match === null ? -1 : match.index;
}

function parseItgClass(body: string): string {
  const table = /<(?:table|div)[^>]+class=["']([^"']*\bitg\b[^"']*)["'][^>]*>/i.exec(body);
  return table === null ? '' : table[1];
}

function tableClassForMode(displayMode: GalleryListDisplayMode): string {
  if (displayMode === GalleryListDisplayMode.Minimal || displayMode === GalleryListDisplayMode.MinimalPlus) {
    return 'gltm';
  }
  if (displayMode === GalleryListDisplayMode.Compact) {
    return 'gltc';
  }
  if (displayMode === GalleryListDisplayMode.Extended) {
    return 'glte';
  }
  return '';
}

function findThumbnailEnd(body: string, start: number): number {
  const footer = body.indexOf('<table class="ptb"', start);
  return footer > start ? footer : body.length;
}

function parseGalleryInfo(row: string, displayMode: GalleryListDisplayMode): GalleryInfo | null {
  const link = DETAIL_LINK_PATTERN.exec(row);
  if (link === null) {
    return null;
  }

  const gid = parseIntSafe(link[1], 0);
  if (gid === 0) {
    return null;
  }

  const posted = parsePosted(row, gid);
  const title = parseTitle(row);
  const simpleTags = parseSimpleTags(row);
  return {
    gid: gid,
    token: link[2],
    title: title,
    thumb: parseThumb(row),
    category: parseCategory(row),
    posted: posted.text,
    uploader: parseUploader(row, displayMode),
    rating: parseRating(row),
    rated: parseRated(row),
    simpleLanguage: parseSimpleLanguage(simpleTags, title),
    simpleTags: simpleTags,
    pages: parseItemPages(row),
    thumbWidth: parseThumbWidth(row),
    thumbHeight: parseThumbHeight(row),
    favoriteSlot: posted.favoriteSlot,
    tagList: parseTagList(row)
  };
}

function parseTitle(row: string): string {
  const linkTitle = /<([a-z0-9]+)[^>]+class=["'][^"']*\bglink\b[^"']*["'][^>]*>([\s\S]*?)<\/\1>/i.exec(row);
  if (linkTitle !== null) {
    return cleanText(linkTitle[2]);
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
  if (category !== null) {
    return categoryNameToValue(cleanText(category[1]));
  }

  const minimalCategory = findClassBlock(row, 'gl1m');
  if (minimalCategory.length > 0) {
    const text = cleanText(minimalCategory);
    if (text.length > 0) {
      return categoryNameToValue(text);
    }
  }
  return GalleryCategory.Unknown;
}

function parseUploader(row: string, displayMode: GalleryListDisplayMode): string {
  const uploader = /\/uploader\/[^"']+["'][^>]*>([\s\S]*?)<\/a>/i.exec(row);
  if (uploader !== null) {
    return cleanText(uploader[1]);
  }

  const glhide = findClassBlock(row, 'glhide');
  const fromGlhide = parseFirstLinkText(glhide);
  if (fromGlhide.length > 0) {
    return fromGlhide;
  }

  const gl3e = findClassBlock(row, 'gl3e');
  const gl3eChildren = childDivs(gl3e);
  if (gl3eChildren.length > 3) {
    return parseFirstLinkText(gl3eChildren[3]);
  }

  const gl5m = findClassBlock(row, 'gl5m');
  const gl5mChildren = childDivs(gl5m);
  for (let i = 0; i < gl5mChildren.length; i++) {
    const fromGl5m = parseFirstLinkText(gl5mChildren[i]);
    if (fromGl5m.length > 0) {
      return fromGl5m;
    }
  }

  if (displayMode === GalleryListDisplayMode.Compact) {
    const gl4c = findClassBlock(row, 'gl4c');
    const fromGl4c = parseFirstLinkText(gl4c);
    if (fromGl4c.length > 0) {
      return fromGl4c;
    }
  }
  return '';
}

function parseRating(row: string): number {
  const ir = findClassBlock(row, 'ir');
  const source = ir.length > 0 ? ir : row;
  const rating = RATING_TEXT_PATTERN.exec(source);
  if (rating !== null) {
    return parseFloatSafe(rating[1], -1);
  }

  const style = parseAttribute(source, 'style');
  if (style.length === 0) {
    return -1;
  }
  const numbers: number[] = [];
  let match: RegExpExecArray | null = RATING_STYLE_PATTERN.exec(style);
  while (match !== null) {
    numbers.push(parseIntSafe(match[1], -1));
    match = RATING_STYLE_PATTERN.exec(style);
  }
  if (numbers.length < 2 || numbers[0] < 0 || numbers[1] < 0) {
    return -1;
  }

  let value = 5 - Math.floor(numbers[0] / 16);
  if (numbers[1] === 21) {
    value -= 0.5;
  }
  if (value < 0 || value > 5) {
    return -1;
  }
  return value;
}

function parseRated(row: string): boolean {
  const ir = findClassBlock(row, 'ir');
  return /\b(?:irr|irg|irb)\b/i.test(ir);
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

function parseSimpleLanguage(tags: string[], title: string): string | undefined {
  const knownLanguages: string[] = [
    'english',
    'chinese',
    'spanish',
    'korean',
    'russian',
    'french',
    'portuguese',
    'thai',
    'german',
    'italian',
    'vietnamese',
    'polish',
    'hungarian',
    'dutch'
  ];
  for (let i = 0; i < tags.length; i++) {
    const tag = tags[i].toLowerCase();
    if (tag.indexOf('language:') === 0) {
      return tags[i].substring(tags[i].indexOf(':') + 1);
    }
  }

  const titleText = title.toLowerCase();
  for (let i = 0; i < knownLanguages.length; i++) {
    if (titleText.indexOf(knownLanguages[i]) >= 0) {
      return knownLanguages[i];
    }
  }
  return undefined;
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
  const glhide = findClassBlock(row, 'glhide');
  const glhidePages = PAGE_COUNT_PATTERN.exec(glhide);
  if (glhidePages !== null) {
    return parseIntSafe(glhidePages[1], 0);
  }

  const gl3e = findClassBlock(row, 'gl3e');
  const gl3eChildren = childDivs(gl3e);
  if (gl3eChildren.length > 4) {
    const pages = PAGE_COUNT_PATTERN.exec(gl3eChildren[4]);
    if (pages !== null) {
      return parseIntSafe(pages[1], 0);
    }
  }

  const gl5t = findClassBlock(row, 'gl5t');
  const gl5tPages = PAGE_COUNT_PATTERN.exec(gl5t);
  if (gl5tPages !== null) {
    return parseIntSafe(gl5tPages[1], 0);
  }

  const gl5m = findClassBlock(row, 'gl5m');
  const gl5mPages = PAGE_COUNT_PATTERN.exec(gl5m);
  if (gl5mPages !== null) {
    return parseIntSafe(gl5mPages[1], 0);
  }

  const gl4c = findClassBlock(row, 'gl4c');
  const gl4cPages = PAGE_COUNT_PATTERN.exec(gl4c);
  if (gl4cPages !== null) {
    return parseIntSafe(gl4cPages[1], 0);
  }

  const glthumb = findClassBlock(row, 'glthumb');
  const glthumbPages = PAGE_COUNT_PATTERN.exec(glthumb);
  if (glthumbPages !== null) {
    return parseIntSafe(glthumbPages[1], 0);
  }

  const pages = PAGE_COUNT_PATTERN.exec(row);
  return pages === null ? 0 : parseIntSafe(pages[1], 0);
}

function parseThumbWidth(row: string): number {
  const size = parseThumbSize(row);
  return size === null ? 0 : parseIntSafe(size[2], 0);
}

function parseThumbHeight(row: string): number {
  const size = parseThumbSize(row);
  return size === null ? 0 : parseIntSafe(size[1], 0);
}

function parseThumbSize(row: string): RegExpExecArray | null {
  const img = /<img[^>]+style=["']([^"']+)["']/i.exec(row);
  if (img !== null) {
    const imgSize = /height:\s*(\d+)px;\s*width:\s*(\d+)px/i.exec(img[1]);
    if (imgSize !== null) {
      return imgSize;
    }
  }
  return /height:\s*(\d+)px;\s*width:\s*(\d+)px/i.exec(row);
}

interface PostedInfo {
  text: string;
  favoriteSlot: number;
}

function parsePosted(row: string, gid: number): PostedInfo {
  const id = 'posted_' + gid.toString();
  const blockPattern = new RegExp("<[^>]+id=[\"']" + escapeRegExp(id) + "[\"'][^>]*>[\\s\\S]*?<\\/[^>]+>", 'i');
  const block = blockPattern.exec(row);
  if (block === null) {
    return { text: '', favoriteSlot: -2 };
  }

  return {
    text: cleanText(block[0]),
    favoriteSlot: parseFavoriteSlot(parseAttribute(block[0], 'style'))
  };
}

function hasClass(classValue: string, className: string): boolean {
  return new RegExp("(^|\\s)" + escapeRegExp(className) + "(\\s|$)", 'i').test(classValue);
}

function parseFavoriteSlot(style: string): number {
  const match = FAVORITE_SLOT_PATTERN.exec(style);
  if (match === null) {
    return -2;
  }

  for (let i = 0; i < FAVORITE_SLOT_RGB.length; i++) {
    const rgb = FAVORITE_SLOT_RGB[i];
    if (match[1] === rgb[0] && match[2] === rgb[1] && match[3] === rgb[2]) {
      return i;
    }
  }
  return -2;
}

function parseById(row: string, id: string): string {
  const pattern = new RegExp("<[^>]+id=[\"']" + escapeRegExp(id) + "[\"'][^>]*>([\\s\\S]*?)<\\/[^>]+>", 'i');
  const match = pattern.exec(row);
  return match === null ? '' : cleanText(match[1]);
}

function findClassBlock(source: string, className: string): string {
  const startPattern = new RegExp("<[^>]+class=[\"'][^\"']*\\b" + escapeRegExp(className) + "\\b[^\"']*[\"'][^>]*>", 'i');
  const start = startPattern.exec(source);
  if (start === null) {
    return '';
  }

  const openTag = start[0];
  const tagMatch = /^<([a-z0-9]+)/i.exec(openTag);
  if (tagMatch === null) {
    return openTag;
  }

  const tag = tagMatch[1].toLowerCase();
  if (isVoidTag(tag)) {
    return openTag;
  }

  const startIndex = start.index;
  const afterStart = start.index + openTag.length;
  const tagPattern = new RegExp("<\\/?" + tag + "\\b[^>]*>", 'gi');
  tagPattern.lastIndex = afterStart;
  let depth = 1;
  let match: RegExpExecArray | null = tagPattern.exec(source);
  while (match !== null) {
    if (match[0].indexOf('</') === 0) {
      depth--;
      if (depth === 0) {
        return source.substring(startIndex, match.index + match[0].length);
      }
    } else if (!/\/>$/.test(match[0])) {
      depth++;
    }
    match = tagPattern.exec(source);
  }
  return source.substring(startIndex);
}

function childDivs(source: string): string[] {
  const result: string[] = [];
  if (source.length === 0) {
    return result;
  }

  const outerStart = source.indexOf('>');
  const outerEnd = source.lastIndexOf('</');
  const inner = outerStart >= 0 && outerEnd > outerStart ? source.substring(outerStart + 1, outerEnd) : source;
  let index = 0;
  while (index < inner.length) {
    const start = inner.substring(index).search(/<div\b/i);
    if (start < 0) {
      break;
    }
    const absoluteStart = index + start;
    const block = findFirstTagBlock(inner.substring(absoluteStart), 'div');
    if (block.length === 0) {
      break;
    }
    result.push(block);
    index = absoluteStart + block.length;
  }
  return result;
}

function findFirstTagBlock(source: string, tag: string): string {
  const start = new RegExp("<" + tag + "\\b[^>]*>", 'i').exec(source);
  if (start === null) {
    return '';
  }

  const tagPattern = new RegExp("<\\/" + tag + "\\b[^>]*>|<" + tag + "\\b[^>]*>", 'gi');
  tagPattern.lastIndex = start.index + start[0].length;
  let depth = 1;
  let match: RegExpExecArray | null = tagPattern.exec(source);
  while (match !== null) {
    if (match[0].indexOf('</') === 0) {
      depth--;
      if (depth === 0) {
        return source.substring(start.index, match.index + match[0].length);
      }
    } else if (!/\/>$/.test(match[0])) {
      depth++;
    }
    match = tagPattern.exec(source);
  }
  return source.substring(start.index);
}

function parseFirstLinkText(source: string): string {
  const link = /<a\b[^>]*>([\s\S]*?)<\/a>/i.exec(source);
  return link === null ? '' : cleanText(link[1]);
}

function parseAttribute(source: string, name: string): string {
  const pattern = new RegExp("\\b" + escapeRegExp(name) + "=[\"']([^\"']*)[\"']", 'i');
  const match = pattern.exec(source);
  return match === null ? '' : decodeHtml(match[1]);
}

function isVoidTag(tag: string): boolean {
  return tag === 'img' || tag === 'br' || tag === 'hr' || tag === 'input' || tag === 'meta' || tag === 'link';
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
  const nextUrl = parseNextUrl(body);
  const match = NEXT_PAGE_PATTERN.exec(nextUrl.length > 0 ? nextUrl : body);
  return match === null ? -1 : parseIntSafe(match[1], -1);
}

function parseNextUrl(body: string): string {
  const anchorPattern = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
  let match: RegExpExecArray | null = anchorPattern.exec(body);
  while (match !== null) {
    const anchor = match[0];
    const id = parseAttribute(anchor, 'id').toLowerCase();
    const href = parseAttribute(anchor, 'href');
    const text = cleanText(match[2]).toLowerCase();
    if (href.length > 0 && href !== '#' && href.indexOf('javascript:') !== 0 &&
      (id === 'unext' || text === '>' || text === 'next')) {
      return href;
    }
    match = anchorPattern.exec(body);
  }
  return '';
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
