// Thread-safe sorting data: no UI, store singleton, tags, or image resources.
export interface DownloadSortKey {
  gid: number;
  value: number;
  text: string;
}

export function compareDownloadSortKeys(left: DownloadSortKey, right: DownloadSortKey, mode: string): number {
  let result = 0;
  const descending = mode === 'Default' || mode.endsWith(' desc');
  if (mode.startsWith('Author') && (left.text.length === 0 || right.text.length === 0)) {
    result = left.text.length === 0 ? (right.text.length === 0 ? 0 : 1) : -1;
  } else {
    result = mode.startsWith('Author') || mode.startsWith('Name') ?
      left.text.localeCompare(right.text) : left.value - right.value;
    if (descending) {
      result = -result;
    }
  }
  return result !== 0 ? result : right.gid - left.gid;
}

export function sortDownloadKeys(keys: DownloadSortKey[], mode: string): number[] {
  keys.sort((left: DownloadSortKey, right: DownloadSortKey): number => compareDownloadSortKeys(left, right, mode));
  return keys.map((key: DownloadSortKey): number => key.gid);
}
