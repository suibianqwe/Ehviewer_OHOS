export const RESPONSE_BLOCK_PATTERN: RegExp =
  /<(?:[A-Za-z0-9_-]+:)?response[\s>][\s\S]*?<\/(?:[A-Za-z0-9_-]+:)?response>/gi;
const HREF_PATTERN: RegExp =
  /<(?:[A-Za-z0-9_-]+:)?href[^>]*>([\s\S]*?)<\/(?:[A-Za-z0-9_-]+:)?href>/i;
const COLLECTION_PATTERN: RegExp = /<(?:[A-Za-z0-9_-]+:)?collection[\s/>]/i;
const CONTENT_LENGTH_PATTERN: RegExp =
  /<(?:[A-Za-z0-9_-]+:)?getcontentlength[^>]*>([\s\S]*?)<\/(?:[A-Za-z0-9_-]+:)?getcontentlength>/i;
const ETAG_PATTERN: RegExp =
  /<(?:[A-Za-z0-9_-]+:)?getetag[^>]*>([\s\S]*?)<\/(?:[A-Za-z0-9_-]+:)?getetag>/i;
const LAST_MODIFIED_PATTERN: RegExp =
  /<(?:[A-Za-z0-9_-]+:)?getlastmodified[^>]*>([\s\S]*?)<\/(?:[A-Za-z0-9_-]+:)?getlastmodified>/i;
const ABSOLUTE_HREF_PATTERN: RegExp = /^https?:\/\/[^/]+(\/.*)$/i;
const URL_AUTHORITY_PATTERN: RegExp = /^(https?:\/\/)([^/:]+|\[[^\]]+\])(?::(\d+))?([\s\S]*)$/i;
const PORT_ONLY_PATTERN: RegExp = /^\d+$/;
const URL_SCHEME_PATTERN: RegExp = /^https?:\/\//i;
const VALID_URL_PATTERN: RegExp = /^https?:\/\/[^/\s]+(?:\/[^\s]*)?$/i;
const HOST_PATTERN: RegExp = /^https?:\/\/([^/]+)/i;

export interface RemoteStorageListEntry {
  name: string;
  path: string;
  isDirectory: boolean;
  size: number;
  modifiedAt: number;
  etag?: string;
}

export function normalizeRemoteStorageUrl(value: string): string {
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return '';
  }
  let url = trimmed;
  if (!URL_SCHEME_PATTERN.test(url)) {
    url = 'http://' + url;
  }
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

export function normalizeRemoteStorageBasePath(value: string): string {
  const parts = value.trim().replace(/\\/g, '/').split('/');
  const normalized: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i].trim();
    if (part.length > 0 && part !== '.' && part !== '..') {
      normalized.push(part);
    }
  }
  return normalized.join('/');
}

export function remoteStorageHost(url: string): string {
  const match = HOST_PATTERN.exec(url.trim());
  return match === null ? '' : match[1];
}

export function normalizeRemoteStoragePort(value: string): string {
  const trimmed = value.trim();
  if (trimmed.length === 0 || !PORT_ONLY_PATTERN.test(trimmed)) {
    return '';
  }
  const port = Number.parseInt(trimmed);
  return port >= 1 && port <= 65535 ? port.toString() : '';
}

export function remoteStoragePortFromUrl(url: string): string {
  const match = URL_AUTHORITY_PATTERN.exec(url.trim());
  if (match === null || match[3] === undefined) {
    return '';
  }
  return normalizeRemoteStoragePort(match[3]);
}

export function remoteStorageUrlWithoutPort(url: string): string {
  const match = URL_AUTHORITY_PATTERN.exec(url.trim());
  if (match === null) {
    return url.trim();
  }
  const rest = match[4] === undefined ? '' : match[4];
  return match[1] + match[2] + rest;
}

export function remoteStorageApplyPort(url: string, port: string): string {
  const normalizedPort = normalizeRemoteStoragePort(port);
  const normalizedUrl = url.trim();
  if (normalizedPort.length === 0) {
    return normalizedUrl;
  }
  const match = URL_AUTHORITY_PATTERN.exec(normalizedUrl);
  if (match === null) {
    return normalizedUrl;
  }
  const rest = match[4] === undefined ? '' : match[4];
  return match[1] + match[2] + ':' + normalizedPort + rest;
}

export function isValidRemoteStorageUrl(url: string): boolean {
  return VALID_URL_PATTERN.test(normalizeRemoteStorageUrl(url));
}

export function createRemoteStorageProfileId(): string {
  return 'remote_' + Date.now().toString() + '_' + Math.floor(Math.random() * 100000).toString();
}

export function remoteStorageJoinPath(base: string, child: string): string {
  const parts: string[] = [];
  pushPathSegments(parts, base);
  pushPathSegments(parts, child);
  return parts.join('/');
}

export function remoteStorageUrlForPath(baseUrl: string, path: string): string {
  const base = baseUrl.replace(/\/+$/, '');
  const relative = remoteStorageJoinPath('', path);
  if (relative.length === 0) {
    return base;
  }
  const segments = relative.split('/');
  const encoded: string[] = [];
  for (let i = 0; i < segments.length; i++) {
    encoded.push(encodeURIComponent(segments[i]));
  }
  return base + '/' + encoded.join('/');
}

export function remoteStorageRelativePathFromHref(href: string, basePath: string): string {
  let path = href.trim();
  const absolute = ABSOLUTE_HREF_PATTERN.exec(path);
  if (absolute !== null) {
    path = absolute[1];
  }
  const queryIndex = path.indexOf('?');
  if (queryIndex >= 0) {
    path = path.substring(0, queryIndex);
  }
  const fragmentIndex = path.indexOf('#');
  if (fragmentIndex >= 0) {
    path = path.substring(0, fragmentIndex);
  }
  try {
    path = decodeURIComponent(path);
  } catch (error) {
  }
  const segments: string[] = [];
  pushPathSegments(segments, path);
  const normalizedBase = normalizeRemoteStorageBasePath(basePath);
  if (normalizedBase.length === 0) {
    return segments.join('/');
  }
  const baseSegments = normalizedBase.split('/');
  for (let i = 0; i + baseSegments.length <= segments.length; i++) {
    let matched = true;
    for (let j = 0; j < baseSegments.length; j++) {
      if (segments[i + j] !== baseSegments[j]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      const rest: string[] = [];
      for (let k = i + baseSegments.length; k < segments.length; k++) {
        rest.push(segments[k]);
      }
      return rest.join('/');
    }
  }
  return '';
}

export function decodeWebDavXmlEntities(value: string): string {
  return value.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
    .replace(/&apos;/g, '\'').replace(/&#39;/g, '\'').replace(/&amp;/g, '&');
}

export function webDavStatusMessage(statusCode: number): string {
  if (statusCode === 207) {
    return 'Multi-Status';
  }
  if (statusCode === 401) {
    return 'Authentication failed';
  }
  if (statusCode === 403) {
    return 'Access denied';
  }
  if (statusCode === 404) {
    return 'Remote path not found';
  }
  if (statusCode === 405 || statusCode === 501) {
    return 'WebDAV is not supported by this server';
  }
  if (statusCode === 409) {
    return 'Parent folder is missing';
  }
  if (statusCode === 423) {
    return 'Remote resource is locked';
  }
  if (statusCode === 507) {
    return 'Remote storage is full';
  }
  if (statusCode >= 500) {
    return 'Server error ' + statusCode.toString();
  }
  if (statusCode >= 400) {
    return 'Request failed ' + statusCode.toString();
  }
  return '';
}

export function parseWebDavMultiStatus(xml: string, basePath: string): RemoteStorageListEntry[] {
  const entries: RemoteStorageListEntry[] = [];
  RESPONSE_BLOCK_PATTERN.lastIndex = 0;
  let block: RegExpExecArray | null = RESPONSE_BLOCK_PATTERN.exec(xml);
  while (block !== null) {
    const entry = parseWebDavResponseBlock(block[0], basePath);
    if (entry !== null) {
      entries.push(entry);
    }
    block = RESPONSE_BLOCK_PATTERN.exec(xml);
  }
  RESPONSE_BLOCK_PATTERN.lastIndex = 0;
  return entries;
}

function parseWebDavResponseBlock(block: string, basePath: string): RemoteStorageListEntry | null {
  const hrefMatch = HREF_PATTERN.exec(block);
  if (hrefMatch === null) {
    return null;
  }
  const href = decodeWebDavXmlEntities(hrefMatch[1]).trim();
  const path = remoteStorageRelativePathFromHref(href, basePath);
  if (path.length === 0) {
    return null;
  }
  const segments = path.split('/');
  const name = segments[segments.length - 1];
  if (name.length === 0) {
    return null;
  }
  let size = 0;
  const lengthMatch = CONTENT_LENGTH_PATTERN.exec(block);
  if (lengthMatch !== null) {
    const parsed = Number.parseInt(decodeWebDavXmlEntities(lengthMatch[1]).trim());
    if (!Number.isNaN(parsed) && parsed > 0) {
      size = parsed;
    }
  }
  let modifiedAt = 0;
  const modifiedMatch = LAST_MODIFIED_PATTERN.exec(block);
  if (modifiedMatch !== null) {
    const parsed = Date.parse(decodeWebDavXmlEntities(modifiedMatch[1]).trim());
    if (!Number.isNaN(parsed)) {
      modifiedAt = parsed;
    }
  }
  let etag = '';
  const etagMatch = ETAG_PATTERN.exec(block);
  if (etagMatch !== null) {
    etag = decodeWebDavXmlEntities(etagMatch[1]).trim();
  }
  return {
    name: name,
    path: path,
    isDirectory: COLLECTION_PATTERN.test(block),
    size: size,
    modifiedAt: modifiedAt,
    etag: etag.length > 0 ? etag : undefined
  };
}

function pushPathSegments(target: string[], value: string): void {
  const segments = value.trim().replace(/\\/g, '/').split('/');
  for (let i = 0; i < segments.length; i++) {
    const segment = segments[i].trim();
    if (segment.length > 0 && segment !== '.') {
      target.push(segment);
    }
  }
}

export interface SyncTombstoneLike {
  key: string;
  deletedAt: number;
  cleared?: boolean;
}

export interface SyncTombstoneSectionLike {
  name: string;
  records: SyncTombstoneLike[];
}

// Merges local and remote tombstone lists: the newest operation per key wins, so a later
// re-add (cleared record) cancels an older deletion and vice versa.
export function mergeSyncTombstoneLists(local: SyncTombstoneLike[],
  remote: SyncTombstoneLike[]): SyncTombstoneLike[] {
  const byKey: Map<string, SyncTombstoneLike> = new Map<string, SyncTombstoneLike>();
  for (let i = 0; i < local.length; i++) {
    byKey.set(local[i].key, local[i]);
  }
  for (let i = 0; i < remote.length; i++) {
    const incoming = remote[i];
    if (typeof incoming.key !== 'string' || incoming.key.length === 0 ||
      typeof incoming.deletedAt !== 'number') {
      continue;
    }
    const existing = byKey.get(incoming.key);
    if (existing === undefined || incoming.deletedAt > existing.deletedAt) {
      byKey.set(incoming.key, incoming);
    }
  }
  const merged: SyncTombstoneLike[] = [];
  byKey.forEach((record: SyncTombstoneLike): void => {
    merged.push(record);
  });
  merged.sort((left: SyncTombstoneLike, right: SyncTombstoneLike): number => {
    if (left.deletedAt !== right.deletedAt) {
      return left.deletedAt - right.deletedAt;
    }
    return left.key < right.key ? -1 : (left.key > right.key ? 1 : 0);
  });
  return merged;
}

export function syncTombstoneShouldDelete(record: SyncTombstoneLike, itemTime: number): boolean {
  if (record.cleared === true) {
    return false;
  }
  const time = typeof itemTime === 'number' && itemTime > 0 ? itemTime : 0;
  return record.deletedAt >= time;
}

export function pruneSyncTombstoneList(list: SyncTombstoneLike[], now: number,
  maxAgeMs: number): SyncTombstoneLike[] {
  const kept: SyncTombstoneLike[] = [];
  for (let i = 0; i < list.length; i++) {
    if (now - list[i].deletedAt <= maxAgeMs) {
      kept.push(list[i]);
    }
  }
  return kept;
}

export function filterTombstoneKey(mode: number, text: string): string {
  return mode.toString() + '|' + text.trim().toLowerCase();
}

export function keywordTombstoneKey(keyword: string): string {
  return keyword.trim().toLowerCase();
}
