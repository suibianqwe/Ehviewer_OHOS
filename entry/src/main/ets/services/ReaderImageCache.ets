import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { ehCookieStore } from './EhCookieStore';
import {
  applyEhNetworkOptions,
  createEhRequestPlan,
  EhRequestPlan,
  ensureEhHostRules,
  recordEhRequestOutcome
} from './EhNetworkConfig';
import { ehSettingsStore } from './EhSettingsStore';

interface PendingImageDownload {
  url: string;
  promise: Promise<string>;
  listeners: ImageDownloadProgressCallback[];
  lastProgress: ImageDownloadProgress;
}

const PENDING_IMAGE_DOWNLOADS: PendingImageDownload[] = [];
const WAITING_IMAGE_SLOTS: (() => void)[] = [];
const MAX_ACTIVE_IMAGE_DOWNLOADS: number = 6;
const MAX_IMAGE_CACHE_BYTES: number = 320 * 1024 * 1024;
const IMAGE_RETRY_DELAYS_MS: number[] = [300, 900, 1800, 3200];
const IMAGE_CONNECT_TIMEOUT_MS: number = 4500;
let activeImageDownloads: number = 0;

interface CachedImageFile {
  path: string;
  size: number;
  modifiedAt: number;
}

export interface CacheClearResult {
  files: number;
  bytes: number;
}

export interface ImageDownloadProgress {
  receivedBytes: number;
  totalBytes: number;
}

export type ImageDownloadProgressCallback = (progress: ImageDownloadProgress) => void;

interface ImageRequestHeader {
  'Host'?: string;
  'User-Agent': string;
  'Accept': string;
  'Accept-Language': string;
  'Referer': string;
  'Connection': string;
  'Cookie'?: string;
}

export class ReaderImageCache {
  async ensureCached(context: common.UIAbilityContext, imageUrl: string, referer: string,
    priority: boolean = false, onProgress?: ImageDownloadProgressCallback): Promise<string> {
    if (imageUrl.length === 0) {
      return '';
    }

    const path = this.pathFor(context, imageUrl);
    if (exists(path)) {
      return path;
    }

    const pending = getPending(imageUrl);
    if (pending !== null) {
      if (onProgress !== undefined) {
        addPendingProgressListener(imageUrl, onProgress);
      }
      return pending.promise;
    }

    const listeners: ImageDownloadProgressCallback[] = [];
    if (onProgress !== undefined) {
      listeners.push(onProgress);
    }
    const progressCallback: ImageDownloadProgressCallback | undefined = onProgress !== undefined ?
      (progress: ImageDownloadProgress): void => {
        publishPendingProgress(imageUrl, progress);
      } : undefined;
    const promise = this.download(context, imageUrl, referer, path, priority, progressCallback);
    putPending(imageUrl, promise, listeners);
    try {
      return await promise;
    } finally {
      removePending(imageUrl);
    }
  }

  getCachedPath(context: common.UIAbilityContext, imageUrl: string): string {
    if (imageUrl.length === 0) {
      return '';
    }

    const path = this.pathFor(context, imageUrl);
    return exists(path) ? path : '';
  }

  cachedSize(context: common.UIAbilityContext, imageUrl: string): number {
    const path = this.getCachedPath(context, imageUrl);
    return path.length > 0 ? statFileSize(path) : 0;
  }

  removeCached(context: common.UIAbilityContext, imageUrl: string): string {
    if (imageUrl.length === 0) {
      return '';
    }

    const path = this.pathFor(context, imageUrl);
    if (!exists(path)) {
      return '';
    }
    return removeFile(path) ? path : '';
  }

  clear(context: common.UIAbilityContext): CacheClearResult {
    const directory = context.cacheDir + '/reader_images';
    let files = 0;
    let bytes = 0;
    try {
      const names = fs.listFileSync(directory);
      for (let i = 0; i < names.length; i++) {
        const path = directory + '/' + names[i];
        const size = statFileSize(path);
        if (removeFile(path)) {
          files++;
          bytes += size;
        }
      }
    } catch (error) {
    }
    return { files: files, bytes: bytes };
  }

  private async download(context: common.UIAbilityContext, imageUrl: string, referer: string, path: string,
    priority: boolean, onProgress?: ImageDownloadProgressCallback): Promise<string> {
    ensureDirectory(context.cacheDir + '/reader_images');
    await acquireImageSlot(priority);
    try {
      await this.downloadWithRetry(imageUrl, referer, path, onProgress);
      pruneImageCache(context.cacheDir + '/reader_images');
      return path;
    } finally {
      releaseImageSlot();
    }
  }

  private async downloadWithRetry(imageUrl: string, referer: string, path: string,
    onProgress?: ImageDownloadProgressCallback): Promise<void> {
    let lastError = '';
    for (let attempt = 0; attempt < 5; attempt++) {
      try {
        await this.downloadOnce(imageUrl, referer, path, attempt, onProgress);
        return;
      } catch (error) {
        removeFileQuietly(path);
        lastError = imageNetworkErrorMessage(error);
        if (attempt >= 4 || !isTransientImageError(lastError)) {
          throw new Error(lastError);
        }
        await sleepImageRetry(attempt);
      }
    }
    throw new Error(lastError.length > 0 ? lastError : 'Image download failed');
  }

  private async downloadOnce(imageUrl: string, referer: string, path: string,
    attempt: number, onProgress?: ImageDownloadProgressCallback): Promise<void> {
    const request = http.createHttp();
    let plan: EhRequestPlan | null = null;
    const startedAt = Date.now();
    let outcomeRecorded = false;
    try {
      plan = createEhRequestPlan(imageUrl);
      const header = buildImageRequestHeader(plan, referer, ehCookieStore.getCookieHeaderForUrl(imageUrl));
      const timeout = imageRequestTimeoutMs();
      await ensureEhHostRules();
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: plan.fronted ? IMAGE_CONNECT_TIMEOUT_MS : Math.min(timeout, 10000),
        readTimeout: timeout
      };
      applyEhNetworkOptions(options, plan);
      const statusCode = await streamImageToFile(request, plan.url, options, path,
        imageRequestDeadlineMs(plan, attempt), onProgress);

      if (statusCode < 200 || statusCode >= 300) {
        recordEhRequestOutcome(plan, false, Date.now() - startedAt);
        outcomeRecorded = true;
        throw new Error(imageStatusMessage(statusCode));
      }

      const size = statFileSize(path);
      if (size <= 0) {
        recordEhRequestOutcome(plan, false, Date.now() - startedAt);
        outcomeRecorded = true;
        throw new Error('Empty image response');
      }
      recordEhRequestOutcome(plan, true, Date.now() - startedAt);
      outcomeRecorded = true;
      if (onProgress !== undefined) {
        onProgress({ receivedBytes: size, totalBytes: size });
      }
    } catch (error) {
      if (plan !== null && !outcomeRecorded) {
        recordEhRequestOutcome(plan, false, Date.now() - startedAt);
      }
      throw new Error(imageNetworkErrorMessage(error));
    } finally {
      try {
        request.destroy();
      } catch (error) {
      }
    }
  }

  private pathFor(context: common.UIAbilityContext, imageUrl: string): string {
    return context.cacheDir + '/reader_images/' + stableImageKey(imageUrl) + imageExtension(imageUrl);
  }
}

function buildImageRequestHeader(plan: EhRequestPlan, referer: string, cookieHeader: string): ImageRequestHeader {
  const header: ImageRequestHeader = {
    'Host': plan.host,
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36 EhViewerHarmony/0.1',
    'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Referer': referer,
    'Connection': plan.fronted ? 'close' : 'keep-alive'
  };
  if (cookieHeader.length > 0) {
    header.Cookie = cookieHeader;
  }
  return header;
}

function imageRequestTimeoutMs(): number {
  const value = ehSettingsStore.getValue('download_timeout', 'Default');
  if (value === '15s') {
    return 15000;
  }
  if (value === '30s') {
    return 30000;
  }
  if (value === '60s') {
    return 60000;
  }
  return 30000;
}

function imageRequestDeadlineMs(plan: EhRequestPlan, attempt: number): number {
  const timeout = imageRequestTimeoutMs();
  if (!plan.fronted || attempt >= 2) {
    return timeout;
  }
  return Math.min(timeout, 15000);
}

function streamImageToFile(request: http.HttpRequest, url: string, options: http.HttpRequestOptions, path: string,
  timeoutMs: number, onProgress?: ImageDownloadProgressCallback): Promise<number> {
  return new Promise<number>((resolve: (value: number) => void, reject: (reason: Error) => void) => {
    let finished = false;
    let fd = -1;
    let receivedBytes = 0;
    let totalBytes = 0;
    const tempPath = path + '.part';
    removeFileQuietly(tempPath);
    try {
      const file = fs.openSync(tempPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
      fd = file.fd;
    } catch (error) {
      reject(new Error(String(error)));
      return;
    }

    const cleanup = (): void => {
      try {
        request.off('dataReceive');
      } catch (error) {
      }
      try {
        request.off('dataReceiveProgress');
      } catch (error) {
      }
      try {
        request.off('dataEnd');
      } catch (error) {
      }
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (error) {
        }
        fd = -1;
      }
    };

    const timer = setTimeout(() => {
      if (finished) {
        return;
      }
      finished = true;
      cleanup();
      try {
        request.destroy();
      } catch (error) {
      }
      removeFileQuietly(tempPath);
      reject(new Error('Image request timed out after ' + Math.floor(timeoutMs / 1000).toString() + 's'));
    }, timeoutMs);

    request.on('dataReceive', (data: ArrayBuffer) => {
      if (finished) {
        return;
      }
      try {
        fs.writeSync(fd, data);
        receivedBytes += data.byteLength;
        if (onProgress !== undefined) {
          onProgress({ receivedBytes: receivedBytes, totalBytes: totalBytes });
        }
      } catch (error) {
        finished = true;
        clearTimeout(timer);
        cleanup();
        try {
          request.destroy();
        } catch (destroyError) {
        }
        removeFileQuietly(tempPath);
        reject(new Error(String(error)));
      }
    });
    request.on('dataReceiveProgress', (progress: http.DataReceiveProgressInfo) => {
      if (finished) {
        return;
      }
      totalBytes = Math.max(0, progress.totalSize);
      receivedBytes = Math.max(receivedBytes, progress.receiveSize);
      if (onProgress !== undefined) {
        onProgress({ receivedBytes: receivedBytes, totalBytes: totalBytes });
      }
    });

    request.requestInStream(url, options).then((statusCode: number) => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimeout(timer);
      cleanup();
      if (statusCode >= 200 && statusCode < 300 && receivedBytes > 0) {
        try {
          removeFileQuietly(path);
          fs.moveFileSync(tempPath, path);
        } catch (error) {
          removeFileQuietly(tempPath);
          reject(new Error(String(error)));
          return;
        }
      } else {
        removeFileQuietly(tempPath);
      }
      resolve(Number(statusCode));
    }).catch((error: Error) => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimeout(timer);
      cleanup();
      removeFileQuietly(tempPath);
      reject(error);
    });
  });
}

function sleepImageRetry(attempt: number): Promise<void> {
  const index = Math.min(attempt, IMAGE_RETRY_DELAYS_MS.length - 1);
  const delay = IMAGE_RETRY_DELAYS_MS[index];
  return new Promise<void>((resolve: (value: void | PromiseLike<void>) => void) => {
    setTimeout(() => {
      resolve();
    }, delay);
  });
}

function isTransientImageError(message: string): boolean {
  const lower = message.toLowerCase();
  return lower.indexOf('timeout') >= 0 || lower.indexOf('temporary') >= 0 || lower.indexOf('reset') >= 0 ||
    lower.indexOf('socket') >= 0 || lower.indexOf('network') >= 0 || lower.indexOf('503') >= 0 ||
    lower.indexOf('504') >= 0 || lower.indexOf('522') >= 0 || lower.indexOf('524') >= 0 ||
    lower.indexOf('500') >= 0 || lower.indexOf('502') >= 0 || lower.indexOf('520') >= 0 ||
    lower.indexOf('521') >= 0 || lower.indexOf('523') >= 0 || lower.indexOf('525') >= 0 ||
    lower.indexOf('526') >= 0 ||
    lower.indexOf('ssl') >= 0 || lower.indexOf('tls') >= 0 || lower.indexOf('certificate') >= 0 ||
    lower.indexOf('http2') >= 0 || lower.indexOf('2300016') >= 0 ||
    lower.indexOf('2300007') >= 0 || lower.indexOf('230350') >= 0;
}

function imageStatusMessage(statusCode: number): string {
  if (statusCode === 403) {
    return 'Image access denied: check login cookies';
  }
  if (statusCode === 404) {
    return 'Image not found';
  }
  if (statusCode === 429) {
    return 'Too many image requests: slow down and retry later';
  }
  if (statusCode === 509) {
    return 'Image limit reached';
  }
  if (statusCode === 408 || statusCode === 500 || statusCode === 502 || statusCode === 503 ||
    statusCode === 504 || statusCode === 522 || statusCode === 524) {
    return 'Temporary image network error: HTTP ' + statusCode.toString();
  }
  return 'HTTP ' + statusCode.toString();
}

function imageNetworkErrorMessage(error: Object): string {
  let message = String(error);
  if (message.indexOf('Error: ') === 0) {
    message = message.substring(7);
  }
  const lower = message.toLowerCase();
  if (lower.indexOf('timeout') >= 0 || lower.indexOf('timed out') >= 0) {
    return 'Image network timeout';
  }
  if (lower.indexOf('ssl') >= 0 || lower.indexOf('tls') >= 0 || lower.indexOf('certificate') >= 0) {
    return 'Image TLS connection failed';
  }
  if (lower.indexOf('dns') >= 0 || lower.indexOf('unknownhost') >= 0) {
    return 'Image DNS lookup failed';
  }
  return message.length > 0 ? message : 'Image download failed';
}

function removeFileQuietly(path: string): void {
  try {
    if (exists(path)) {
      fs.unlinkSync(path);
    }
  } catch (error) {
  }
}

function removeFile(path: string): boolean {
  try {
    if (exists(path)) {
      fs.unlinkSync(path);
      return true;
    }
  } catch (error) {
  }
  return false;
}

function statFileSize(path: string): number {
  try {
    return fs.statSync(path).size;
  } catch (error) {
    return 0;
  }
}

function ensureDirectory(path: string): void {
  if (exists(path)) {
    return;
  }
  try {
    fs.mkdirSync(path);
  } catch (error) {
  }
}

function pruneImageCache(directory: string): void {
  let files: CachedImageFile[] = [];
  let total = 0;
  try {
    const names = fs.listFileSync(directory);
    for (let i = 0; i < names.length; i++) {
      const path = directory + '/' + names[i];
      try {
        const stat = fs.statSync(path);
        files.push({
          path: path,
          size: stat.size,
          modifiedAt: stat.mtime
        });
        total += stat.size;
      } catch (error) {
      }
    }
  } catch (error) {
    return;
  }

  if (total <= MAX_IMAGE_CACHE_BYTES) {
    return;
  }

  files = files.sort((left: CachedImageFile, right: CachedImageFile) => left.modifiedAt - right.modifiedAt);
  for (let i = 0; i < files.length && total > MAX_IMAGE_CACHE_BYTES; i++) {
    removeFileQuietly(files[i].path);
    total -= files[i].size;
  }
}

function exists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (error) {
    return false;
  }
}

function getPending(url: string): PendingImageDownload | null {
  for (let i = 0; i < PENDING_IMAGE_DOWNLOADS.length; i++) {
    if (PENDING_IMAGE_DOWNLOADS[i].url === url) {
      return PENDING_IMAGE_DOWNLOADS[i];
    }
  }
  return null;
}

function putPending(url: string, promise: Promise<string>, listeners: ImageDownloadProgressCallback[]): void {
  removePending(url);
  PENDING_IMAGE_DOWNLOADS.push({
    url: url,
    promise: promise,
    listeners: listeners,
    lastProgress: { receivedBytes: 0, totalBytes: 0 }
  });
}

function removePending(url: string): void {
  for (let i = PENDING_IMAGE_DOWNLOADS.length - 1; i >= 0; i--) {
    if (PENDING_IMAGE_DOWNLOADS[i].url === url) {
      PENDING_IMAGE_DOWNLOADS.splice(i, 1);
    }
  }
}

function addPendingProgressListener(url: string, listener: ImageDownloadProgressCallback): void {
  const pending = getPending(url);
  if (pending === null) {
    return;
  }
  pending.listeners.push(listener);
  if (pending.lastProgress.receivedBytes > 0 || pending.lastProgress.totalBytes > 0) {
    listener(pending.lastProgress);
  }
}

function publishPendingProgress(url: string, progress: ImageDownloadProgress): void {
  const pending = getPending(url);
  if (pending === null) {
    return;
  }
  pending.lastProgress = {
    receivedBytes: Math.max(0, progress.receivedBytes),
    totalBytes: Math.max(0, progress.totalBytes)
  };
  const listeners = pending.listeners.slice();
  for (let i = 0; i < listeners.length; i++) {
    try {
      listeners[i](pending.lastProgress);
    } catch (error) {
    }
  }
}

function acquireImageSlot(priority: boolean): Promise<void> {
  if (activeImageDownloads < MAX_ACTIVE_IMAGE_DOWNLOADS) {
    activeImageDownloads++;
    return Promise.resolve();
  }

  return new Promise<void>((resolve: (value: void | PromiseLike<void>) => void) => {
    const resume = () => {
      activeImageDownloads++;
      resolve();
    };
    if (priority) {
      WAITING_IMAGE_SLOTS.unshift(resume);
    } else {
      WAITING_IMAGE_SLOTS.push(resume);
    }
  });
}

function releaseImageSlot(): void {
  activeImageDownloads = Math.max(0, activeImageDownloads - 1);
  const next = WAITING_IMAGE_SLOTS.shift();
  if (next !== undefined) {
    next();
  }
}

function stableImageKey(value: string): string {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16);
}

function imageExtension(url: string): string {
  const clean = url.split('?')[0].toLowerCase();
  const dot = clean.lastIndexOf('.');
  if (dot >= 0) {
    const extension = clean.substring(dot);
    if (extension === '.jpg' || extension === '.jpeg' || extension === '.png' || extension === '.webp' ||
      extension === '.gif') {
      return extension;
    }
  }
  return '.jpg';
}

export const readerImageCache: ReaderImageCache = new ReaderImageCache();
