import { TopListBucket, TopListDetail, TopListInfo, TopListItem, TopListKind } from '../model/GalleryModels';

export interface TopListParseResult {
  detail: TopListDetail | null;
  warning: string;
}

const TOP_LIST_TITLES: string[] = [
  'Gallery Toplists',
  'Uploader Toplists',
  'Tagging Toplists',
  'Hentai@Home Toplists',
  'EHTracker Toplists',
  'Cleanup Toplists',
  'Rating&Reviewing Toplists'
];

const TOP_LIST_FALLBACK_TITLES: string[] = [
  '画廊 排行榜',
  '上传 排行榜',
  '标签 排行榜',
  'Hentai@Home 排行榜',
  'EH订阅 排行榜',
  '整理 排行榜',
  '等级&审核 排行榜'
];

const SOURCE_PERIODS: string[] = ['All Time', 'Past Year', 'Past Month', 'Yesterday'];
const DISPLAY_PERIODS: string[] = ['Yesterday', 'Past Month', 'Past Year', 'All Time'];
const DISPLAY_FOLLOWS: string[] = ['tl=15', 'tl=13', 'tl=12', 'tl=11'];
const DETAIL_LINK_PATTERN: RegExp = /\/g\/(\d+)\/([A-Za-z0-9]+)\//;
const TAG_LINK_PATTERN: RegExp = /\/tag\/([^"'?#]+)/;

export function parseTopList(body: string): TopListParseResult {
  const warning = parseWarning(body);
  if (warning.length > 0) {
    return { detail: null, warning: warning };
  }

  const anchors: TopListItem[] = parseTunAnchors(body);
  if (anchors.length === 0) {
    return { detail: null, warning: 'No top-list rows parsed' };
  }

  const lists = buildLists(anchors);
  return {
    detail: {
      title: parseTitle(body),
      lists: lists
    },
    warning: lists.length === 0 ? 'Top-list rows were incomplete' : ''
  };
}

function buildLists(anchors: TopListItem[]): TopListInfo[] {
  const lists: TopListInfo[] = [];
  const itemsPerBucket = Math.max(1, Math.floor(anchors.length / (TOP_LIST_TITLES.length * SOURCE_PERIODS.length)));
  let cursor = 0;

  for (let listIndex = 0; listIndex < TOP_LIST_TITLES.length; listIndex++) {
    const sourceBuckets: TopListBucket[] = [];
    for (let sourcePeriod = 0; sourcePeriod < SOURCE_PERIODS.length; sourcePeriod++) {
      const items = anchors.slice(cursor, cursor + itemsPerBucket);
      cursor += itemsPerBucket;
      sourceBuckets.push({
        title: SOURCE_PERIODS[sourcePeriod],
        follow: '',
        items: items
      });
    }

    const displayBuckets: TopListBucket[] = [];
    for (let displayIndex = 0; displayIndex < DISPLAY_PERIODS.length; displayIndex++) {
      const sourceIndex = DISPLAY_PERIODS.length - displayIndex - 1;
      displayBuckets.push({
        title: DISPLAY_PERIODS[displayIndex],
        follow: DISPLAY_FOLLOWS[displayIndex],
        items: sourceBuckets[sourceIndex].items
      });
    }

    lists.push({
      kind: listIndex as TopListKind,
      title: TOP_LIST_TITLES[listIndex],
      buckets: displayBuckets
    });
  }

  return lists;
}

function parseTunAnchors(body: string): TopListItem[] {
  const items: TopListItem[] = [];
  const pattern = /<[^>]+class=["'][^"']*\btun\b[^"']*["'][^>]*>[\s\S]*?<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>[\s\S]*?<\/[^>]+>/gi;
  let match: RegExpExecArray | null = pattern.exec(body);
  while (match !== null) {
    const item = createTopListItem(decodeHtml(match[1]), cleanText(match[2]));
    if (item.value.length > 0) {
      items.push(item);
    }
    match = pattern.exec(body);
  }
  return items;
}

function createTopListItem(href: string, value: string): TopListItem {
  const detail = DETAIL_LINK_PATTERN.exec(href);
  const tag = TAG_LINK_PATTERN.exec(href);
  return {
    href: href,
    gid: detail === null ? '' : detail[1],
    token: detail === null ? '' : detail[2],
    tag: tag === null ? '' : safeDecode(tag[1]),
    value: value
  };
}

function parseTitle(body: string): string {
  const title = /<h1[^>]*>([\s\S]*?)<\/h1>/i.exec(body);
  if (title !== null) {
    return cleanText(title[1]);
  }

  const text = cleanText(body);
  for (let i = 0; i < TOP_LIST_TITLES.length; i++) {
    if (text.indexOf(TOP_LIST_TITLES[i]) >= 0 || text.indexOf(TOP_LIST_FALLBACK_TITLES[i]) >= 0) {
      return 'Top Lists';
    }
  }
  return 'Top Lists';
}

function parseWarning(body: string): string {
  if (body.indexOf('(And if you choose to ignore this warning') >= 0) {
    return 'Offensive content warning needs confirmation';
  }
  if (body.indexOf('This gallery is pining for the fjords') >= 0) {
    return 'Gallery is unavailable';
  }

  const error = /<div class=["']d["']>\s*<p>([^<]+)<\/p>/i.exec(body);
  if (error !== null) {
    return cleanText(error[1]);
  }
  if (body.indexOf('ipb_member_id') >= 0 && body.indexOf('Login') >= 0) {
    return 'Login or Cookie required';
  }
  return '';
}

function cleanText(value: string): string {
  return decodeHtml(value.replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
}

function decodeHtml(value: string): string {
  return value
    .replace(/&amp;/g, '&')
    .replace(/&#038;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, '\'')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

function safeDecode(value: string): string {
  try {
    return decodeURIComponent(value.replace(/\+/g, '%20'));
  } catch (error) {
    return value;
  }
}
