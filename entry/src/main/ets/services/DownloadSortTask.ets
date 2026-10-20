import { DownloadSortKey, sortDownloadKeys } from './DownloadSortKeys';

@Concurrent
export function sortDownloadKeysTask(keys: DownloadSortKey[], mode: string): number[] {
  return sortDownloadKeys(keys, mode);
}
