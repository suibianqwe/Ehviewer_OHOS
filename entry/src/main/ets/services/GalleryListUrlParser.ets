import { GalleryCategory } from '../model/GalleryModels';
import { EhUrl, ListMode, ListUrlBuilder } from './EhUrl';

const VALID_HOSTS: string[] = [
  EhUrl.DOMAIN_EX,
  EhUrl.DOMAIN_E,
  EhUrl.DOMAIN_LOFI
];

export function parseGalleryListUrl(url: string): ListUrlBuilder | null {
  const parsed = splitUrl(url);
  if (parsed === null || !containsHost(parsed.host)) {
    return null;
  }

  if (parsed.path === '/' || parsed.path.length === 0) {
    const builder = new ListUrlBuilder();
    builder.setQuery(parsed.query);
    return builder;
  }

  if (parsed.path.startsWith('/uploader/')) {
    return parseKeywordPath(parsed.path, '/uploader/', ListMode.Uploader);
  }

  if (parsed.path.startsWith('/tag/')) {
    return parseKeywordPath(parsed.path, '/tag/', ListMode.Tag);
  }

  const category = Number.parseInt(parsed.path.substring(1));
  if (Number.isNaN(category)) {
    return null;
  }

  const builder = new ListUrlBuilder();
  builder.setQuery(parsed.query);
  builder.category = category === 0 ? GalleryCategory.None : category;
  return builder;
}

interface ParsedUrl {
  host: string;
  path: string;
  query: string;
}

function parseKeywordPath(path: string, prefix: string, mode: ListMode): ListUrlBuilder | null {
  const rest = path.substring(prefix.length);
  const slash = rest.indexOf('/');
  const rawKeyword = slash < 0 ? rest : rest.substring(0, slash);
  const keyword = safeDecode(rawKeyword);
  if (keyword.length === 0) {
    return null;
  }

  const builder = new ListUrlBuilder();
  builder.mode = mode;
  builder.keyword = keyword;
  if (slash >= 0) {
    builder.pageIndex = parsePageIndex(rest.substring(slash + 1));
  }
  return builder;
}

function splitUrl(url: string): ParsedUrl | null {
  const match = /^(https?):\/\/([^\/?#]+)([^?#]*)(?:\?([^#]*))?/i.exec(url);
  if (match === null) {
    return null;
  }

  return {
    host: match[2].toLowerCase(),
    path: match[3].length === 0 ? '/' : match[3],
    query: match[4] === undefined ? '' : match[4]
  };
}

function containsHost(host: string): boolean {
  for (let i = 0; i < VALID_HOSTS.length; i++) {
    if (VALID_HOSTS[i] === host) {
      return true;
    }
  }
  return false;
}

function parsePageIndex(segment: string): number {
  const parsed = Number.parseInt(segment);
  return Number.isNaN(parsed) ? 0 : parsed;
}

function safeDecode(value: string): string {
  try {
    return decodeURIComponent(value.replace(/\+/g, '%20'));
  } catch (error) {
    return '';
  }
}
