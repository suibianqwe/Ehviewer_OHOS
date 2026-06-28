import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ehSettingsStore } from './EhSettingsStore';

const HATH_QUALITY_FILE_NAME: string = 'hath_quality.json';
const HATH_QUALITY_VERSION: number = 1;
const HATH_QUALITY_MAX_ITEMS: number = 200;
const HATH_QUALITY_SAVE_THROTTLE_MS: number = 30000;
const HATH_BAD_FAILURE_THRESHOLD: number = 2;
const HATH_BAD_LATENCY_MS: number = 12000;
const HATH_FAST_LATENCY_MS: number = 5000;

interface HathQualityFile {
  version?: number;
  updatedAt?: number;
  hosts?: HathQualityEntry[];
}

interface HathQualityEntry {
  host: string;
  successCount: number;
  failureCount: number;
  averageMs: number;
  bytes: number;
  lastSuccessAt: number;
  lastFailureAt: number;
}

export class HathQualityStore {
  private entries: HathQualityEntry[] = [];
  private cachePath: string = '';
  private loaded: boolean = false;
  private lastSaveAt: number = 0;

  recordSuccess(context: common.UIAbilityContext | undefined, url: string, elapsedMs: number, bytes: number): void {
    const host = hathHostFromUrl(url);
    if (!hathQualityEnabled() || context === undefined || host.length === 0) {
      return;
    }
    this.ensureLoaded(context);
    const entry = this.entryForHost(host);
    entry.successCount++;
    entry.failureCount = Math.max(0, entry.failureCount - 1);
    const measured = Math.max(1, elapsedMs);
    entry.averageMs = entry.averageMs <= 0 ? measured : Math.round((entry.averageMs * 3 + measured) / 4);
    entry.bytes += Math.max(0, bytes);
    entry.lastSuccessAt = Date.now();
    this.saveThrottled(context);
  }

  recordFailure(context: common.UIAbilityContext | undefined, url: string): void {
    const host = hathHostFromUrl(url);
    if (!hathQualityEnabled() || context === undefined || host.length === 0) {
      return;
    }
    this.ensureLoaded(context);
    const entry = this.entryForHost(host);
    entry.failureCount++;
    if (entry.averageMs <= 0) {
      entry.averageMs = HATH_BAD_LATENCY_MS;
    } else {
      entry.averageMs = Math.max(entry.averageMs, HATH_BAD_LATENCY_MS);
    }
    entry.lastFailureAt = Date.now();
    this.save(context);
  }

  shouldSkip(context: common.UIAbilityContext | undefined, url: string): boolean {
    const host = hathHostFromUrl(url);
    if (!hathQualityEnabled() || context === undefined || host.length === 0) {
      return false;
    }
    this.ensureLoaded(context);
    const entry = this.findEntry(host);
    if (entry === null) {
      return false;
    }
    if (entry.successCount > 0 && entry.failureCount <= entry.successCount) {
      return false;
    }
    return entry.failureCount >= HATH_BAD_FAILURE_THRESHOLD || entry.averageMs >= HATH_BAD_LATENCY_MS;
  }

  hostSummary(context: common.UIAbilityContext | undefined, url: string): string {
    const host = hathHostFromUrl(url);
    if (!hathQualityEnabled() || context === undefined || host.length === 0) {
      return '';
    }
    this.ensureLoaded(context);
    const entry = this.findEntry(host);
    if (entry === null) {
      return host + ' new';
    }
    return host + ' ok=' + entry.successCount.toString() + ', fail=' + entry.failureCount.toString() +
      ', avg=' + entry.averageMs.toString() + 'ms';
  }

  private ensureLoaded(context: common.UIAbilityContext): void {
    const path = context.filesDir + '/' + HATH_QUALITY_FILE_NAME;
    if (this.loaded && this.cachePath === path) {
      return;
    }
    this.cachePath = path;
    this.loaded = true;
    this.entries = [];
    try {
      const parsed = JSON.parse(fs.readTextSync(path)) as HathQualityFile;
      const hosts = parsed.hosts;
      if (parsed.version !== HATH_QUALITY_VERSION || hosts === undefined) {
        return;
      }
      for (let i = 0; i < hosts.length; i++) {
        const item = normalizeEntry(hosts[i]);
        if (item !== null) {
          this.entries.push(item);
        }
      }
      this.prune();
    } catch (error) {
    }
  }

  private entryForHost(host: string): HathQualityEntry {
    const existing = this.findEntry(host);
    if (existing !== null) {
      return existing;
    }
    const entry: HathQualityEntry = {
      host: host,
      successCount: 0,
      failureCount: 0,
      averageMs: 0,
      bytes: 0,
      lastSuccessAt: 0,
      lastFailureAt: 0
    };
    this.entries.push(entry);
    return entry;
  }

  private findEntry(host: string): HathQualityEntry | null {
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].host === host) {
        return this.entries[i];
      }
    }
    return null;
  }

  private saveThrottled(context: common.UIAbilityContext): void {
    const now = Date.now();
    if (now - this.lastSaveAt < HATH_QUALITY_SAVE_THROTTLE_MS) {
      return;
    }
    this.save(context);
  }

  private save(context: common.UIAbilityContext): void {
    this.ensureLoaded(context);
    this.prune();
    const data: HathQualityFile = {
      version: HATH_QUALITY_VERSION,
      updatedAt: Date.now(),
      hosts: this.entries
    };
    try {
      let fd = -1;
      try {
        const file = fs.openSync(this.cachePath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
        fd = file.fd;
        fs.writeSync(fd, JSON.stringify(data));
      } finally {
        if (fd >= 0) {
          fs.closeSync(fd);
        }
      }
      this.lastSaveAt = Date.now();
    } catch (error) {
    }
  }

  private prune(): void {
    this.entries.sort((left: HathQualityEntry, right: HathQualityEntry) => {
      const leftScore = hathEntryScore(left);
      const rightScore = hathEntryScore(right);
      if (leftScore !== rightScore) {
        return rightScore - leftScore;
      }
      return Math.max(right.lastSuccessAt, right.lastFailureAt) - Math.max(left.lastSuccessAt, left.lastFailureAt);
    });
    if (this.entries.length > HATH_QUALITY_MAX_ITEMS) {
      this.entries.splice(HATH_QUALITY_MAX_ITEMS);
    }
  }
}

function normalizeEntry(value: HathQualityEntry): HathQualityEntry | null {
  if (typeof value.host !== 'string' || value.host.length === 0 || !isHathHost(value.host)) {
    return null;
  }
  return {
    host: value.host,
    successCount: safeNumber(value.successCount),
    failureCount: safeNumber(value.failureCount),
    averageMs: safeNumber(value.averageMs),
    bytes: safeNumber(value.bytes),
    lastSuccessAt: safeNumber(value.lastSuccessAt),
    lastFailureAt: safeNumber(value.lastFailureAt)
  };
}

function hathEntryScore(entry: HathQualityEntry): number {
  const successScore = entry.successCount * 20;
  const failurePenalty = entry.failureCount * 35;
  const latencyScore = entry.averageMs > 0 ? Math.max(0, HATH_FAST_LATENCY_MS - entry.averageMs) / 100 : 0;
  return successScore + latencyScore - failurePenalty;
}

function hathHostFromUrl(url: string): string {
  const match = /^https?:\/\/([^\/?#]+)/i.exec(url);
  if (match === null) {
    return '';
  }
  const host = match[1].toLowerCase();
  return isHathHost(host) ? host : '';
}

function isHathHost(host: string): boolean {
  return host === 's.exhentai.org' || host.indexOf('.hath.network') > 0 || host.endsWith('.hath.network');
}

function safeNumber(value: number): number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0 ? Math.round(value) : 0;
}

function hathQualityEnabled(): boolean {
  return ehSettingsStore.getValue('auto_direct_connection', 'On') === 'On';
}

export const hathQualityStore: HathQualityStore = new HathQualityStore();
