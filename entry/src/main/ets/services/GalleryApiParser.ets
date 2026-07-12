import { GalleryCategory, GalleryInfo } from '../model/GalleryModels';
import { galleryLanguageCodeToName, normalizeGalleryLanguageCode } from './GalleryLanguageSupport';

interface GalleryApiItem {
  gid?: string;
  token?: string;
  title?: string;
  title_jpn?: string;
  category?: string;
  thumb?: string;
  uploader?: string;
  posted?: string;
  rating?: string;
  tags?: string[];
  filecount?: string;
}

interface GalleryApiResponse {
  gmetadata?: GalleryApiItem[];
}

export function mergeGalleryApiMetadata(body: string, galleries: GalleryInfo[]): void {
  let parsed: GalleryApiResponse;
  try {
    parsed = JSON.parse(body) as GalleryApiResponse;
  } catch (error) {
    return;
  }
  if (!Array.isArray(parsed.gmetadata)) {
    return;
  }
  for (let i = 0; i < parsed.gmetadata.length; i++) {
    const item = parsed.gmetadata[i];
    const gid = parseIntSafe(item.gid, 0);
    if (gid <= 0) {
      continue;
    }
    const gallery = findGallery(galleries, gid);
    if (gallery === null) {
      continue;
    }
    mergeGalleryApiItem(gallery, item);
  }
}

function findGallery(galleries: GalleryInfo[], gid: number): GalleryInfo | null {
  for (let i = 0; i < galleries.length; i++) {
    if (galleries[i].gid === gid) {
      return galleries[i];
    }
  }
  return null;
}

function mergeGalleryApiItem(gallery: GalleryInfo, item: GalleryApiItem): void {
  gallery.title = normalizeString(item.title, gallery.title);
  gallery.titleJpn = normalizeString(item.title_jpn, gallery.titleJpn);
  gallery.category = categoryNameToValue(normalizeString(item.category, '')) || gallery.category;
  gallery.thumb = normalizeString(item.thumb, gallery.thumb);
  gallery.uploader = normalizeString(item.uploader, gallery.uploader);
  const posted = parsePosted(item.posted);
  if (posted.length > 0) {
    gallery.posted = posted;
  }
  const rating = parseFloatSafe(item.rating, -1);
  if (rating >= 0) {
    gallery.rating = rating;
  }
  if (Array.isArray(item.tags)) {
    gallery.simpleTags = item.tags.slice();
    gallery.tagList = item.tags.slice();
  }
  const pages = parseIntSafe(item.filecount, 0);
  if (pages > 0) {
    gallery.pages = pages;
  }
  gallery.simpleLanguage = inferSimpleLanguage(gallery.simpleTags, gallery.title);
}

export function inferSimpleLanguage(tags: string[] | undefined, title: string): string | undefined {
  if (tags !== undefined) {
    for (let i = 0; i < tags.length; i++) {
      const tag = tags[i].toLowerCase();
      if (tag.indexOf('language:') === 0) {
        return normalizeGalleryLanguageCode(tag.substring(tag.indexOf(':') + 1));
      }
    }
  }
  const fromTitle = languageFromTitle(title);
  if (fromTitle.length > 0) {
    return fromTitle;
  }
  return 'JA';
}

export function languageTagFromText(text: string): string {
  const code = normalizeGalleryLanguageCode(text);
  return code.length === 0 ? '' : 'language:' + galleryLanguageCodeToName(code);
}

function languageFromTitle(title: string): string {
  const text = title.toLowerCase();
  const patterns: string[][] = [
    ['EN', 'eng', 'english'],
    ['ZH', 'ch', 'chs', 'cht', 'chinese', '中文', '汉化', '漢化', '中国翻訳', '中国翻译'],
    ['ES', 'spanish', 'español'],
    ['KO', 'korean'],
    ['RU', 'rus', 'russian'],
    ['FR', 'fr', 'french'],
    ['PT', 'portuguese'],
    ['TH', 'thai'],
    ['DE', 'german'],
    ['IT', 'italian', 'italiano'],
    ['VI', 'vietnamese'],
    ['PL', 'polish'],
    ['HU', 'hun', 'hungarian'],
    ['NL', 'dutch'],
    ['JA', 'japanese', 'jpn']
  ];
  for (let i = 0; i < patterns.length; i++) {
    for (let j = 1; j < patterns[i].length; j++) {
      const label = patterns[i][j];
      if (new RegExp('(?:^|[\\[\\(\\{\\s_\\-])' + escapeRegExp(label) + '(?:$|[\\]\\)\\}\\s_\\-])', 'i').test(text)) {
        return patterns[i][0];
      }
    }
  }
  return '';
}

function categoryNameToValue(category: string): number {
  switch (category.toLowerCase().trim()) {
    case 'doujinshi': return GalleryCategory.Doujinshi;
    case 'manga': return GalleryCategory.Manga;
    case 'artist cg': return GalleryCategory.ArtistCg;
    case 'game cg': return GalleryCategory.GameCg;
    case 'western': return GalleryCategory.Western;
    case 'non-h': return GalleryCategory.NonH;
    case 'image set': return GalleryCategory.ImageSet;
    case 'cosplay': return GalleryCategory.Cosplay;
    case 'asian porn': return GalleryCategory.AsianPorn;
    case 'misc': return GalleryCategory.Misc;
    default: return GalleryCategory.Unknown;
  }
}

function parsePosted(value: string | undefined): string {
  const seconds = parseIntSafe(value, 0);
  if (seconds <= 0) {
    return '';
  }
  const date = new Date(seconds * 1000);
  return date.getFullYear().toString() + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate()) + ' ' +
    pad2(date.getHours()) + ':' + pad2(date.getMinutes());
}

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

function normalizeString(value: string | undefined, fallback: string | undefined): string {
  if (value !== undefined && value.trim().length > 0) {
    return value.trim();
  }
  return fallback === undefined ? '' : fallback;
}

function parseIntSafe(value: string | undefined, fallback: number): number {
  if (value === undefined) {
    return fallback;
  }
  const parsed = Number.parseInt(value);
  return Number.isNaN(parsed) ? fallback : parsed;
}

function parseFloatSafe(value: string | undefined, fallback: number): number {
  if (value === undefined) {
    return fallback;
  }
  const parsed = Number.parseFloat(value);
  return Number.isNaN(parsed) ? fallback : parsed;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
