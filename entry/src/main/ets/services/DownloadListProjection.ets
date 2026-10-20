import { taskpool } from '@kit.ArkTS';
import { compareDownloadSortKeys, DownloadSortKey, sortDownloadKeys } from './DownloadSortKeys';
import { sortDownloadKeysTask } from './DownloadSortTask';
import { DownloadInfo, DownloadProgress } from './EhDownloadStore';
import { downloadSortKey } from './DownloadSortSupport';

type DownloadChunkFilter = (items: DownloadInfo[]) => DownloadInfo[];
type DownloadProgressUpdater = (item: DownloadInfo, sizeChanged: boolean) => void;

export function applyDownloadProgressUpdates(updates: DownloadProgress[], byGid: Map<number, DownloadInfo>,
  onItem: DownloadProgressUpdater): boolean {
  let sizeChanged = false;
  for (const update of updates) {
    const item = byGid.get(update.gid);
    if (item === undefined) {
      continue;
    }
    const changed = item.fileSize !== update.fileSize;
    sizeChanged = sizeChanged || changed;
    item.finished = update.finished;
    item.downloaded = update.downloaded;
    item.total = update.total;
    item.speed = update.speed;
    item.remaining = update.remaining;
    item.fileSize = update.fileSize;
    item.archiveUri = update.archiveUri;
    onItem(item, changed);
  }
  return sizeChanged;
}

export function yieldDownloadListWork(): Promise<void> {
  return new Promise<void>((resolve: () => void) => { setTimeout(resolve, 0); });
}

// Owns one request, not one cache per sort mode. Old work cannot publish after
// a new query, a new store snapshot, or the scene disappearing.
export class DownloadListProjection {
  private revision: number = 0;
  private task: taskpool.Task | undefined = undefined;
  private keys: Map<number, DownloadSortKey> = new Map();
  private mode: string = '';
  private refreshTimer: number = -1;
  private workingRevision: number = -1;

  cancelScheduledRefresh(): void {
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  dispose(): void {
    this.cancelScheduledRefresh();
    this.invalidate();
    this.clearKeys();
  }

  scheduleRefresh(refresh: () => void): void {
    if (this.refreshTimer < 0) {
      this.refreshTimer = setTimeout(() => { this.runScheduledRefresh(refresh); }, 300);
    }
  }

  private runScheduledRefresh(refresh: () => void): void {
    this.refreshTimer = -1;
    if (this.workingRevision >= 0 || this.task !== undefined) {
      this.scheduleRefresh(refresh);
      return;
    }
    refresh();
  }

  clearKeys(): void {
    this.keys.clear();
  }

  dropKey(gid: number): void {
    this.keys.delete(gid);
  }

  project(items: DownloadInfo[], mode: string, revision: number,
    filterChunk: DownloadChunkFilter): Promise<DownloadInfo[] | undefined> {
    if (!this.isCurrent(revision)) {
      return Promise.resolve(undefined);
    }
    this.workingRevision = revision;
    return this.projectCurrent(items, mode, revision, filterChunk).finally(() => {
      if (this.workingRevision === revision) {
        this.workingRevision = -1;
      }
    });
  }

  private async projectCurrent(items: DownloadInfo[], mode: string, revision: number,
    filterChunk: DownloadChunkFilter): Promise<DownloadInfo[] | undefined> {
    if (this.mode !== mode) {
      this.clearKeys();
      this.mode = mode;
    }
    const keys: DownloadSortKey[] = [];
    const byGid: Map<number, DownloadInfo> = new Map();
    for (let start = 0; start < items.length; start += 256) {
      await yieldDownloadListWork();
      if (!this.isCurrent(revision)) {
        return undefined;
      }
      for (const item of filterChunk(items.slice(start, start + 256))) {
        let key = this.keys.get(item.gid);
        if (key === undefined) {
          key = downloadSortKey(item, mode);
          this.keys.set(item.gid, key);
        }
        keys.push(key);
        byGid.set(item.gid, item);
      }
    }
    const gids = await this.sort(keys, mode, revision);
    if (gids === undefined) {
      return undefined;
    }
    const result: DownloadInfo[] = [];
    for (let index = 0; index < gids.length; index++) {
      const item = byGid.get(gids[index]);
      if (item !== undefined) {
        result.push(item);
      }
      if (index > 0 && index % 512 === 0) {
        await yieldDownloadListWork();
        if (!this.isCurrent(revision)) {
          return undefined;
        }
      }
    }
    return result;
  }

  invalidate(): number {
    this.revision++;
    if (this.task !== undefined) {
      try {
        taskpool.cancel(this.task);
      } catch (_error) {
        // Already running/completed on systems that cannot cancel this task.
      }
      this.task = undefined;
    }
    return this.revision;
  }

  isCurrent(revision: number): boolean {
    return revision === this.revision;
  }

  async sort(keys: DownloadSortKey[], mode: string, revision: number): Promise<number[] | undefined> {
    if (!this.isCurrent(revision)) {
      return undefined;
    }
    if (keys.length < 512) {
      return sortDownloadKeys(keys, mode);
    }
    let task: taskpool.Task | undefined = undefined;
    try {
      task = new taskpool.Task(sortDownloadKeysTask, keys, mode);
      this.task = task;
      const result = await taskpool.execute(task, taskpool.Priority.LOW) as number[];
      return this.isCurrent(revision) ? result : undefined;
    } catch (_error) {
      if (!this.isCurrent(revision)) {
        return undefined;
      }
      // A worker failure must not fall back to a large synchronous UI sort.
      return await this.sortCooperatively(keys, mode, revision);
    } finally {
      if (this.task === task) {
        this.task = undefined;
      }
    }
  }

  private async sortCooperatively(keys: DownloadSortKey[], mode: string,
    revision: number): Promise<number[] | undefined> {
    let source = keys;
    let target = new Array<DownloadSortKey>(keys.length);
    let work = 0;
    for (let width = 1; width < keys.length; width *= 2) {
      for (let start = 0; start < keys.length; start += width * 2) {
        const middle = Math.min(start + width, keys.length);
        const end = Math.min(start + width * 2, keys.length);
        let left = start;
        let right = middle;
        for (let index = start; index < end; index++) {
          if (left < middle && (right >= end || compareDownloadSortKeys(source[left], source[right], mode) <= 0)) {
            target[index] = source[left++];
          } else {
            target[index] = source[right++];
          }
          if (++work % 2048 === 0) {
            await yieldDownloadListWork();
            if (!this.isCurrent(revision)) {
              return undefined;
            }
          }
        }
      }
      const swap = source;
      source = target;
      target = swap;
    }
    return source.map((key: DownloadSortKey): number => key.gid);
  }
}
