import { DownloadInfo } from './EhDownloadStore';
import { DownloadSortKey } from './DownloadSortKeys';

export const DOWNLOAD_SORT_SETTING_KEY: string = 'download_sort_mode';
export const DOWNLOAD_SORT_OPTIONS: string[] = [
  'Default', 'GID asc', 'GID desc', 'Time asc', 'Time desc', 'Author asc', 'Author desc',
  'Name asc', 'Name desc', 'Rating asc', 'Rating desc', 'Size asc', 'Size desc'
];

export function normalizeDownloadSortMode(value: string): string {
  return DOWNLOAD_SORT_OPTIONS.indexOf(value) >= 0 ? value : 'Default';
}

function downloadAuthor(item: DownloadInfo): string {
  const authors: string[] = [];
  if (item.detailTags !== undefined) {
    for (const group of item.detailTags) {
      if (group.namespace.toLowerCase() === 'artist') {
        for (const tag of group.tags) {
          const author = tag.replace(/^artist:/i, '').trim().toLowerCase();
          if (author.length > 0 && authors.indexOf(author) < 0) {
            authors.push(author);
          }
        }
      }
    }
  }
  for (const tag of (item.tagList ?? []).concat(item.simpleTags ?? [])) {
    if (/^artist:/i.test(tag)) {
      const author = tag.substring(tag.indexOf(':') + 1).trim().toLowerCase();
      if (author.length > 0 && authors.indexOf(author) < 0) {
        authors.push(author);
      }
    }
  }
  // Uploader is not the artist. Keep unknown authors last in either direction.
  return authors.sort().join('\u0000');
}

export function downloadSortKey(item: DownloadInfo, mode: string): DownloadSortKey {
  let value = item.time;
  let text = '';
  if (mode.startsWith('Author')) {
    text = downloadAuthor(item);
  } else if (mode.startsWith('Name')) {
    text = item.title;
  } else if (mode.startsWith('GID')) {
    value = item.gid;
  } else if (mode.startsWith('Rating')) {
    value = item.rating;
  } else if (mode.startsWith('Size')) {
    value = item.fileSize;
  }
  return { gid: item.gid, value: value, text: text };
}

export function sortDownloadItems(items: DownloadInfo[], sortMode: string): void {
  const authors: Map<number, string> = new Map();
  if (sortMode === 'Author asc' || sortMode === 'Author desc') {
    for (const item of items) {
      authors.set(item.gid, downloadAuthor(item));
    }
  }
  items.sort((left: DownloadInfo, right: DownloadInfo): number => {
    let result = 0;
    if (sortMode === 'Author asc' || sortMode === 'Author desc') {
      const leftAuthor = authors.get(left.gid) ?? '';
      const rightAuthor = authors.get(right.gid) ?? '';
      if (leftAuthor.length === 0 || rightAuthor.length === 0) {
        result = leftAuthor.length === 0 ? (rightAuthor.length === 0 ? 0 : 1) : -1;
      } else {
        result = leftAuthor.localeCompare(rightAuthor) * (sortMode === 'Author desc' ? -1 : 1);
      }
    } else if (sortMode === 'GID asc') {
      result = left.gid - right.gid;
    } else if (sortMode === 'GID desc') {
      result = right.gid - left.gid;
    } else if (sortMode === 'Rating desc') {
      result = right.rating - left.rating;
    } else if (sortMode === 'Rating asc') {
      result = left.rating - right.rating;
    } else if (sortMode === 'Name asc') {
      result = left.title.localeCompare(right.title);
    } else if (sortMode === 'Name desc') {
      result = right.title.localeCompare(left.title);
    } else if (sortMode === 'Size asc') {
      result = left.fileSize - right.fileSize;
    } else if (sortMode === 'Size desc') {
      result = right.fileSize - left.fileSize;
    } else if (sortMode === 'Time asc') {
      result = left.time - right.time;
    } else {
      result = right.time - left.time;
    }
    return result !== 0 ? result : right.gid - left.gid;
  });
}
