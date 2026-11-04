// Keep ordering independent of download timestamps, progress and queue priority.
export interface DownloadManualOrderBackup {
  updatedAt: number;
  gids: number[];
}

export function normalizeDownloadOrderBackup(value: DownloadManualOrderBackup): DownloadManualOrderBackup | null {
  if (value === null || typeof value !== 'object' || !Number.isSafeInteger(value.updatedAt) ||
    value.updatedAt <= 0 || !Array.isArray(value.gids)) {
    return null;
  }
  const seen = new Set<number>();
  const gids: number[] = [];
  for (const gid of value.gids) {
    if (Number.isSafeInteger(gid) && gid > 0 && !seen.has(gid)) {
      seen.add(gid);
      gids.push(gid);
    }
  }
  return { updatedAt: value.updatedAt, gids: gids };
}

export function newerDownloadOrder(local: DownloadManualOrderBackup, remote: DownloadManualOrderBackup): boolean {
  if (remote.updatedAt !== local.updatedAt) {
    return remote.updatedAt > local.updatedAt;
  }
  // Resolve concurrent equal-clock edits consistently on every device.
  return remote.gids.join(',') > local.gids.join(',');
}

export function completeDownloadManualOrder(saved: number[], available: number[]): number[] {
  const live = new Set<number>(available);
  const seen = new Set<number>();
  const result: number[] = [];
  for (const gid of saved.concat(available)) {
    if (live.has(gid) && !seen.has(gid)) {
      seen.add(gid);
      result.push(gid);
    }
  }
  return result;
}

export function moveDownloadInOrder(order: number[], sourceGid: number, targetGid: number): boolean {
  const from = order.indexOf(sourceGid);
  const to = order.indexOf(targetGid);
  if (from < 0 || to < 0 || from === to) {
    return false;
  }
  order.splice(from, 1);
  order.splice(to, 0, sourceGid);
  return true;
}
