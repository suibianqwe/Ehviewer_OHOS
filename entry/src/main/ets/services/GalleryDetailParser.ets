import { GalleryCategory, GalleryComment, GalleryDetail, GalleryPreview, GalleryTagGroup, GalleryTagInfo } from '../model/GalleryModels';

const DETAIL_PATTERN: RegExp =
  /var\s+gid\s*=\s*(\d+);[\s\S]*?var\s+token\s*=\s*["']([a-f0-9]+)["'];[\s\S]*?var\s+apiuid\s*=\s*([-\d]+);[\s\S]*?var\s+apikey\s*=\s*["']([a-f0-9]+)["'];/i;
const TORRENT_PATTERN: RegExp = /onclick=["']return popUp\(['"]([^'"]+)['"][^)]*\)["'][^>]*>\s*Torrent Download\s*\((\d+)\)\s*<\/a>/i;
const ARCHIVE_PATTERN: RegExp = /onclick=["']return popUp\(['"]([^'"]+)['"][^)]*\)["'][^>]*>\s*Archive Download\s*<\/a>/i;
const COVER_PATTERN: RegExp = /id=["']gd1["'][\s\S]*?style=["']([^"']*url\([^)]+\)[^"']*)["']/i;
const COVER_URL_PATTERN: RegExp = /url\(([^)]+)\)/i;
const PREVIEW_PATTERN: RegExp =
  /<a[^>]+href=["']([^"']+)["'][^>]*>(?:(?!<\/a>)[\s\S])*?<div[^>]+title=["']Page\s+(\d+):[^"']*["'][^>]+style=["']([^"']*width:\s*(\d+)px;?\s*height:\s*(\d+)px;?[^"']*url\([^)]+\)[^"']*)["'][^>]*>/gi;
const NORMAL_PREVIEW_PATTERN: RegExp =
  /<div[^>]+class=["'][^"']*\bgdtm\b[^"']*["'][^>]*>[\s\S]*?<div[^>]+style=["']([^"']*width:\s*(\d+)px[^"']*height:\s*(\d+)px[^"']*url\([^)]+\)[^"']*)["'][^>]*>[\s\S]*?<a[^>]+href=["']([^"']+)["'][^>]*>[\s\S]*?<img[^>]+alt=["']([\d,]+)["']/gi;
const LARGE_PREVIEW_PATTERN: RegExp =
  /<div[^>]+class=["'][^"']*\bgdtl\b[^"']*["'][\s\S]*?<a[^>]+href=["']([^"']+)["'][^>]*>\s*<img[^>]+alt=["']([\d,]+)["'][^>]+src=["']([^"']+)["']/gi;
const LARGE_PREVIEW_NEW_PATTERN: RegExp =
  /<a[^>]+href=["']([^"']+)["'][^>]*>(?:(?!<\/a>)[\s\S])*?<div[^>]+title=["']Page\s+(\d+):[^"']*["'][^>]+style=["']([^"']*url\([^)]+\)[^"']*0\s+0[^"']*)["'][^>]*>/gi;

export interface GalleryDetailParseResult {
  detail: GalleryDetail | null;
  warning: string;
}

interface StyleOffset {
  x: number;
  y: number;
}

interface CommentAnchor {
  id: string;
  start: number;
  end: number;
}

export function parseGalleryDetail(body: string): GalleryDetailParseResult {
  if (body.indexOf('This gallery is unavailable') >= 0) {
    return { detail: null, warning: 'Gallery unavailable' };
  }
  if (body.indexOf('This gallery is pining') >= 0) {
    return { detail: null, warning: 'Gallery removed' };
  }

  const identity = DETAIL_PATTERN.exec(body);
  if (identity === null) {
    return { detail: null, warning: 'No gallery identity parsed' };
  }

  const gid = parseIntSafe(identity[1], 0);
  if (gid === 0) {
    return { detail: null, warning: 'Invalid gallery gid' };
  }

  const detail: GalleryDetail = {
    gid: gid,
    token: identity[2],
    apiUid: parseIntSafe(identity[3], -1),
    apiKey: identity[4],
    title: parseById(body, 'gn'),
    titleJpn: parseById(body, 'gj'),
    thumb: parseCover(body),
    category: parseCategory(body),
    posted: '',
    uploader: parseUploader(body),
    rating: parseRating(body),
    rated: false,
    pages: 0,
    thumbWidth: 0,
    thumbHeight: 0,
    favoriteSlot: -2,
    favoriteName: parseFavoriteName(body),
    tags: parseTagGroups(body),
    comments: parseComments(body),
    torrentCount: parseTorrentCount(body),
    torrentUrl: parseTorrentUrl(body),
    archiveUrl: parseArchiveUrl(body),
    parent: '',
    visible: '',
    language: '',
    size: '',
    favoriteCount: 0,
    isFavorited: parseIsFavorited(body),
    ratingCount: parseRatingCount(body),
    previewPages: parsePreviewPages(body),
    previewSet: parsePreviewSet(body)
  };

  parseDetailInfo(detail, body);
  return { detail: detail, warning: '' };
}

function parseCover(body: string): string {
  const match = COVER_PATTERN.exec(body);
  return match === null ? '' : normalizeThumbUrl(extractStyleUrl(match[1]));
}

function parseUploader(body: string): string {
  const match = /id=["']gdn["'][^>]*>\s*<a[^>]*>([\s\S]*?)<\/a>/i.exec(body);
  return match === null ? '' : cleanText(match[1]);
}

function parseCategory(body: string): number {
  const match = /id=["']gdc["'][\s\S]*?class=["'][^"']*(?:\bcn\b|\bcs\b)[^"']*["'][^>]*>([\s\S]*?)<\/div>/i.exec(body);
  if (match === null) {
    return GalleryCategory.Unknown;
  }
  return categoryNameToValue(cleanText(match[1]));
}

function parseRating(body: string): number {
  const label = parseById(body, 'rating_label');
  if (label.length === 0 || label === 'Not Yet Rated') {
    return -1;
  }
  const match = /([0-5](?:\.\d+)?)/.exec(label);
  return match === null ? -1 : parseFloatSafe(match[1], -1);
}

function parseRatingCount(body: string): number {
  return parseIntSafe(parseById(body, 'rating_count'), 0);
}

function parseFavoriteName(body: string): string | undefined {
  const match = /id=["']favoritelink["'][^>]*>([\s\S]*?)<\/a>/i.exec(body);
  if (match === null) {
    return undefined;
  }
  const name = cleanText(match[1]);
  return name === 'Add to Favorites' ? undefined : name;
}

function parseIsFavorited(body: string): boolean {
  const favoriteName = parseFavoriteName(body);
  return favoriteName !== undefined && favoriteName.length > 0;
}

function parseTorrentCount(body: string): number {
  const match = TORRENT_PATTERN.exec(body);
  return match === null ? 0 : parseIntSafe(match[2], 0);
}

function parseTorrentUrl(body: string): string {
  const match = TORRENT_PATTERN.exec(body);
  return match === null ? '' : decodeHtml(match[1]);
}

function parseArchiveUrl(body: string): string {
  const match = ARCHIVE_PATTERN.exec(body);
  return match === null ? '' : decodeHtml(match[1]);
}

function parseDetailInfo(detail: GalleryDetail, body: string): void {
  const pattern = /<tr>\s*<td[^>]*>([\s\S]*?)<\/td>\s*<td[^>]*>([\s\S]*?)<\/td>\s*<\/tr>/gi;
  let match: RegExpExecArray | null = pattern.exec(body);
  while (match !== null) {
    const key = cleanText(match[1]);
    const valueHtml = match[2];
    const value = cleanText(valueHtml);
    if (key.startsWith('Posted')) {
      detail.posted = value;
    } else if (key.startsWith('Parent')) {
      detail.parent = parseFirstHref(valueHtml);
    } else if (key.startsWith('Visible')) {
      detail.visible = value;
    } else if (key.startsWith('Language')) {
      detail.language = value;
    } else if (key.startsWith('File Size')) {
      detail.size = value;
    } else if (key.startsWith('Length')) {
      detail.pages = parseLeadingInt(value, 0);
    } else if (key.startsWith('Favorited')) {
      detail.favoriteCount = parseFavoriteCount(value);
    }
    match = pattern.exec(body);
  }
}

function parseTagGroups(body: string): GalleryTagGroup[] {
  const tagBlock = sliceBetween(body, /<div[^>]+id=["']taglist["'][^>]*>/i, /<div[^>]+id=["']tagmenu_act["'][^>]*>/i);
  if (tagBlock.length === 0) {
    return [];
  }

  const groups: GalleryTagGroup[] = [];
  const rowPattern = /<tr[\s\S]*?<\/tr>/gi;
  let row: RegExpExecArray | null = rowPattern.exec(tagBlock);
  while (row !== null) {
    const namespace = /<td[^>]+class=["']tc["'][^>]*>([\s\S]*?):<\/td>/i.exec(row[0]);
    if (namespace !== null) {
      const namespaceText = cleanText(namespace[1]);
      const tags: string[] = [];
      const tagInfos: GalleryTagInfo[] = [];
      const tagPattern = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
      let tag: RegExpExecArray | null = tagPattern.exec(row[0]);
      while (tag !== null) {
        const attrs = tag[1];
        if (attrs.indexOf('ta_') < 0) {
          tag = tagPattern.exec(row[0]);
          continue;
        }
        const text = trimTranslatedTag(cleanText(tag[2]));
        if (text.length > 0) {
          tags.push(text);
          const info = parseTagInfo(namespaceText, text, attrs);
          if (info !== null) {
            tagInfos.push(info);
          }
        }
        tag = tagPattern.exec(row[0]);
      }
      if (tags.length > 0) {
        groups.push({ namespace: namespaceText, tags: tags, tagInfos: tagInfos.length > 0 ? tagInfos : undefined });
      }
    }
    row = rowPattern.exec(tagBlock);
  }
  return groups;
}

function parseTagInfo(namespace: string, tag: string, attrs: string): GalleryTagInfo | null {
  const vote = /toggle_tagmenu\((\d+),\s*['"]([^'"]+)['"]/i.exec(attrs);
  if (vote === null) {
    return null;
  }
  const className = matchAttribute(attrs, 'class');
  return {
    id: parseIntSafe(vote[1], 0),
    namespace: namespace,
    tag: tag,
    fullTag: decodeHtml(vote[2]).trim(),
    voteUpEd: className.indexOf('tup') >= 0,
    voteDownEd: className.indexOf('tdn') >= 0
  };
}

function matchAttribute(attrs: string, name: string): string {
  const pattern = new RegExp("(?:^|\\s)" + name + "=[\"']([^\"']*)[\"']", 'i');
  const match = pattern.exec(attrs);
  return match === null ? '' : decodeHtml(match[1]);
}

function parseComments(body: string): GalleryComment[] {
  const comments: GalleryComment[] = [];
  const anchorPattern = /<a\s+name=["']c([^"']+)["']><\/a>/gi;
  const anchors: CommentAnchor[] = [];
  let anchor: RegExpExecArray | null = anchorPattern.exec(body);
  while (anchor !== null) {
    anchors.push({
      id: anchor[1],
      start: anchor.index,
      end: anchor.index + anchor[0].length
    });
    anchor = anchorPattern.exec(body);
  }

  for (let i = 0; i < anchors.length; i++) {
    const start = anchors[i].end;
    const end = i + 1 < anchors.length ? anchors[i + 1].start : body.length;
    const block = body.substring(start, end);
    const c1 = findClassBlock(block, 'c1');
    const comment = parseCommentBlock(anchors[i].id, c1.length > 0 ? c1 : block);
    if (comment !== null) {
      comments.push(comment);
    }
  }
  return comments;
}

function parseCommentBlock(id: string, block: string): GalleryComment | null {
  const c3 = findClassBlock(block, 'c3');
  const c4 = findClassBlock(block, 'c4');
  const c5 = findClassBlock(block, 'c5');
  const c6 = findClassBlock(block, 'c6');
  if (c3.length === 0 || c6.length === 0) {
    return null;
  }
  const posted = parseCommentPosted(c3);
  const user = parseCommentUser(c3, c4);
  return {
    id: id,
    posted: posted,
    user: user,
    content: c6,
    score: parseCommentScore(c5),
    voteUpAble: /(?:^|>)\s*Vote\+\s*(?:<|$)/i.test(c4),
    voteUpEd: parseCommentVoteActive(c4, 'Vote+'),
    voteDownAble: /(?:^|>)\s*Vote-\s*(?:<|$)/i.test(c4),
    voteDownEd: parseCommentVoteActive(c4, 'Vote-'),
    voteState: cleanText(findClassBlock(block, 'c7'))
  };
}

function parseCommentPosted(c3: string): string {
  const text = cleanText(c3);
  const prefix = 'Posted on ';
  const withoutPrefix = text.indexOf(prefix) === 0 ? text.substring(prefix.length) : text;
  const byIndex = withoutPrefix.indexOf(' by:');
  return (byIndex >= 0 ? withoutPrefix.substring(0, byIndex) : withoutPrefix).trim();
}

function parseCommentUser(c3: string, c4: string): string {
  const link = /<a[^>]*>([\s\S]*?)<\/a>/i.exec(c3);
  if (link !== null) {
    return cleanText(link[1]);
  }
  const text = cleanText(c4);
  return text.replace(/\bVote[+-]\b/gi, '').replace(/\bEdit\b/gi, '').replace(/\s+/g, ' ').trim();
}

function parseCommentScore(c5: string): number {
  const score = /<span[^>]*>([-+]?\d+)<\/span>/i.exec(c5);
  if (score !== null) {
    return parseIntSafe(score[1], 0);
  }
  return parseIntSafe(cleanText(c5), 0);
}

function parseCommentVoteActive(c4: string, label: string): boolean {
  const escaped = escapeRegExp(label);
  const pattern = new RegExp('<[^>]+style=["\']([^"\']+)["\'][^>]*>\\s*' + escaped + '\\s*<', 'i');
  const active = pattern.exec(c4);
  return active !== null && cleanText(active[1]).length > 0;
}

function parsePreviewPages(body: string): number {
  const pattern = /[?&]p=(\d+)/gi;
  let maxIndex = 0;
  let match: RegExpExecArray | null = pattern.exec(body);
  while (match !== null) {
    const index = parseIntSafe(match[1], 0);
    maxIndex = Math.max(maxIndex, index);
    match = pattern.exec(body);
  }
  return maxIndex + 1;
}

function parsePreviewSet(body: string): GalleryPreview[] {
  const previews: GalleryPreview[] = [];
  const seen: Set<number> = new Set();
  let match: RegExpExecArray | null = PREVIEW_PATTERN.exec(body);
  while (match !== null) {
    const index = parseIntSafe(match[2], 1) - 1;
    if (index >= 0 && !seen.has(index)) {
      seen.add(index);
      const offset = parseStyleOffset(match[3]);
      previews.push({
        index: index,
        pageUrl: decodeHtml(match[1]),
        imageUrl: normalizeThumbUrl(extractStyleUrl(match[3])),
        width: parseIntSafe(match[4], 0),
        height: parseIntSafe(match[5], 0),
        xOffset: offset.x,
        yOffset: offset.y
      });
    }
    match = PREVIEW_PATTERN.exec(body);
  }

  match = NORMAL_PREVIEW_PATTERN.exec(body);
  while (match !== null) {
    const index = parseIntSafe(match[5], 1) - 1;
    if (index >= 0 && !seen.has(index)) {
      seen.add(index);
      const offset = parseStyleOffset(match[1]);
      previews.push({
        index: index,
        pageUrl: decodeHtml(match[4]),
        imageUrl: normalizeThumbUrl(extractStyleUrl(match[1])),
        width: parseIntSafe(match[2], 0),
        height: parseIntSafe(match[3], 0),
        xOffset: offset.x,
        yOffset: offset.y
      });
    }
    match = NORMAL_PREVIEW_PATTERN.exec(body);
  }

  match = LARGE_PREVIEW_NEW_PATTERN.exec(body);
  while (match !== null) {
    const index = parseIntSafe(match[2], 1) - 1;
    if (index >= 0 && !seen.has(index)) {
      seen.add(index);
      previews.push({
        index: index,
        pageUrl: decodeHtml(match[1]),
        imageUrl: normalizeThumbUrl(extractStyleUrl(match[3])),
        width: 200,
        height: 0,
        xOffset: 0,
        yOffset: 0
      });
    }
    match = LARGE_PREVIEW_NEW_PATTERN.exec(body);
  }

  match = LARGE_PREVIEW_PATTERN.exec(body);
  while (match !== null) {
    const index = parseIntSafe(match[2], 1) - 1;
    if (index >= 0 && !seen.has(index)) {
      seen.add(index);
      previews.push({
        index: index,
        pageUrl: decodeHtml(match[1]),
        imageUrl: normalizeThumbUrl(match[3]),
        width: 200,
        height: 0,
        xOffset: 0,
        yOffset: 0
      });
    }
    match = LARGE_PREVIEW_PATTERN.exec(body);
  }

  previews.sort((left: GalleryPreview, right: GalleryPreview) => left.index - right.index);
  return previews;
}

function extractStyleUrl(style: string): string {
  const match = COVER_URL_PATTERN.exec(style);
  if (match === null) {
    return '';
  }
  return decodeHtml(match[1]).replace(/^["']|["']$/g, '').trim();
}

function parseStyleOffset(style: string): StyleOffset {
  const position = /background-position\s*:\s*(-?\d+)px\s+(-?\d+)px/i.exec(style);
  if (position !== null) {
    return {
      x: Math.abs(parseIntSafe(position[1], 0)),
      y: Math.abs(parseIntSafe(position[2], 0))
    };
  }

  const numbers: number[] = [];
  const pattern = /(-?\d+)px/gi;
  let match: RegExpExecArray | null = pattern.exec(style);
  while (match !== null) {
    numbers.push(parseIntSafe(match[1], 0));
    match = pattern.exec(style);
  }
  for (let i = numbers.length - 1; i >= 0; i--) {
    if (numbers[i] < 0) {
      return { x: Math.abs(numbers[i]), y: 0 };
    }
  }
  return { x: 0, y: 0 };
}

function normalizeThumbUrl(url: string): string {
  const decoded = decodeHtml(url).replace(/^["']|["']$/g, '').trim();
  if (decoded.length === 0) {
    return '';
  }
  const match = /^https?:\/\/[^/]+\/t\/([^/]+)\/([^/]+)\/([^?#]+)(?:[?#].*)?$/i.exec(decoded);
  if (match === null) {
    return decoded;
  }
  const first = match[1];
  const second = match[2];
  const file = match[3];
  if (file.indexOf(first + second) !== 0) {
    return decoded;
  }
  return 'https://ehgt.org/' + first + '/' + second + '/' + file;
}

function parseById(body: string, id: string): string {
  const pattern = new RegExp("id=[\"']" + escapeRegExp(id) + "[\"'][^>]*>([\\s\\S]*?)(?:<\\/[^>]+>|<h1|<div|$)", 'i');
  const match = pattern.exec(body);
  return match === null ? '' : cleanText(match[1]);
}

function parseFirstHref(value: string): string {
  const match = /href=["']([^"']+)["']/i.exec(value);
  return match === null ? '' : decodeHtml(match[1]);
}

function parseLeadingInt(value: string, fallback: number): number {
  const match = /([\d,]+)/.exec(value);
  return match === null ? fallback : parseIntSafe(match[1].replace(/,/g, ''), fallback);
}

function parseFavoriteCount(value: string): number {
  if (value === 'Never') {
    return 0;
  }
  if (value === 'Once') {
    return 1;
  }
  return parseLeadingInt(value, 0);
}

function sliceBetween(body: string, startPattern: RegExp, endPattern: RegExp): string {
  const start = startPattern.exec(body);
  if (start === null) {
    return '';
  }
  endPattern.lastIndex = 0;
  const source = body.substring(start.index);
  const end = endPattern.exec(source);
  return end === null ? source : source.substring(0, end.index);
}

function trimTranslatedTag(value: string): string {
  const index = value.indexOf('|');
  return index >= 0 ? value.substring(0, index).trim() : value;
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

function isVoidTag(tag: string): boolean {
  return tag === 'br' || tag === 'img' || tag === 'input' || tag === 'meta' || tag === 'link' || tag === 'hr';
}

function decodeHtml(value: string): string {
  return value
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, '\'')
    .replace(/&nbsp;/g, ' ')
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
