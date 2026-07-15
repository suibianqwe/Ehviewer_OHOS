import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { ehCookieStore } from './EhCookieStore';
import { ehAppLog } from './EhAppLog';
import {
  applyEhNetworkOptions,
  createEhRequestPlan,
  EhRequestPlan,
  ensureEhHostRules,
  recordEhRequestOutcome
} from './EhNetworkConfig';
import { ehSettingsStore } from './EhSettingsStore';
import { hathQualityStore } from './HathQualityStore';
import { retireHttpRequest, trackHttpRequest } from './HttpRequestLifecycle';

interface PendingImageDownload {
  url: string;
  promise: Promise<string>;
  listeners: ImageDownloadProgressCallback[];
  lastProgress: ImageDownloadProgress;
}

const PENDING_IMAGE_DOWNLOADS: PendingImageDownload[] = [];
const WAITING_IMAGE_SLOTS: (() => void)[] = [];
const ACTIVE_IMAGE_TEMP_PATHS: string[] = [];
const MAX_ACTIVE_IMAGE_DOWNLOADS: number = 6;
const DEFAULT_IMAGE_CACHE_BYTES: number = 160 * 1024 * 1024;
const IMAGE_RETRY_DELAYS_MS: number[] = [300, 900, 1800, 3200];
const IMAGE_CONNECT_TIMEOUT_MS: number = 4500;
const DEFAULT_IMAGE_RETRY_LIMIT: number = 5;
const IMAGE_ACTIVE_IDLE_TIMEOUT_MIN_MS: number = 30000;
const IMAGE_ACTIVE_IDLE_TIMEOUT_MAX_MS: number = 60000;
const IMAGE_TOTAL_TIMEOUT_MARGIN_MS: number = 30000;
const IMAGE_MIN_EXPECTED_SPEED_BYTES_PER_SECOND: number = 64 * 1024;
const IMAGE_UNKNOWN_TOTAL_TIMEOUT_MS: number = 5 * 60 * 1000;
const IMAGE_MAX_TOTAL_TIMEOUT_MS: number = 10 * 60 * 1000;
let activeImageDownloads: number = 0;
let imageTempFileSequence: number = 0;

interface CachedImageFile {
  path: string;
  size: number;
  modifiedAt: number;
}

interface ImageStreamResult {
  statusCode: number;
  path: string;
}

export interface CacheClearResult {
  files: number;
  bytes: number;
}

export interface CachePruneResult {
  files: number;
  bytes: number;
  remainingBytes: number;
}

export interface ImageDownloadProgress {
  receivedBytes: number;
  totalBytes: number;
}

export type ImageDownloadProgressCallback = (progress: ImageDownloadProgress) => void;

export interface ImageDownloadOptions {
  retryLimit?: number;
}

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
    priority: boolean = false, onProgress?: ImageDownloadProgressCallback, cacheKey: string = '',
    options?: ImageDownloadOptions): Promise<string> {
    if (imageUrl.length === 0) {
      return '';
    }

    const path = this.pathFor(context, imageUrl, cacheKey);
    if (isUsableCachedImage(path)) {
      return path;
    }
    const cached = this.migrateExistingCache(context, imageUrl, path);
    if (cached.length > 0) {
      return cached;
    }

    const pendingKey = imageDownloadPendingKey(imageUrl, cacheKey);
    const pending = getPending(pendingKey);
    if (pending !== null) {
      if (onProgress !== undefined) {
        addPendingProgressListener(pendingKey, onProgress);
      }
      return pending.promise;
    }

    const listeners: ImageDownloadProgressCallback[] = [];
    if (onProgress !== undefined) {
      listeners.push(onProgress);
    }
    const progressCallback: ImageDownloadProgressCallback = (progress: ImageDownloadProgress): void => {
      publishPendingProgress(pendingKey, progress);
    };
    const promise = this.download(context, imageUrl, referer, path, priority, progressCallback, options);
    putPending(pendingKey, promise, listeners);
    try {
      return await promise;
    } finally {
      removePending(pendingKey);
    }
  }

  getCachedPath(context: common.UIAbilityContext, imageUrl: string, cacheKey: string = ''): string {
    if (imageUrl.length === 0) {
      return '';
    }

    const path = this.pathFor(context, imageUrl, cacheKey);
    if (isUsableCachedImage(path)) {
      return path;
    }
    const candidates = this.pathCandidates(context, imageUrl, cacheKey);
    for (let i = 0; i < candidates.length; i++) {
      if (candidates[i] !== path && isUsableCachedImage(candidates[i])) {
        return candidates[i];
      }
    }
    return this.migrateExistingCache(context, imageUrl, path);
  }

  cachedSize(context: common.UIAbilityContext, imageUrl: string, cacheKey: string = ''): number {
    const path = this.getCachedPath(context, imageUrl, cacheKey);
    return path.length > 0 ? statFileSize(path) : 0;
  }

  removeCached(context: common.UIAbilityContext, imageUrl: string, cacheKey: string = ''): string {
    if (imageUrl.length === 0) {
      return '';
    }

    const path = this.pathFor(context, imageUrl, cacheKey);
    const legacyPath = this.legacyPathFor(context, imageUrl, cacheKey);
    const aliasPath = this.pathFor(context, imageUrl);
    const legacyAliasPath = this.legacyPathFor(context, imageUrl);
    let removed = '';
    if (exists(path) && removeFile(path)) {
      removed = path;
    }
    if (exists(legacyPath) && removeFile(legacyPath) && removed.length === 0) {
      removed = legacyPath;
    }
    if (aliasPath !== path && exists(aliasPath) && removeFile(aliasPath) && removed.length === 0) {
      removed = aliasPath;
    }
    if (legacyAliasPath !== legacyPath && exists(legacyAliasPath) && removeFile(legacyAliasPath) &&
      removed.length === 0) {
      removed = legacyAliasPath;
    }
    const candidates = this.pathCandidates(context, imageUrl, cacheKey)
      .concat(this.pathCandidates(context, imageUrl));
    for (let i = 0; i < candidates.length; i++) {
      if (exists(candidates[i]) && removeFile(candidates[i]) && removed.length === 0) {
        removed = candidates[i];
      }
    }
    return removed;
  }

  clear(context: common.UIAbilityContext): CacheClearResult {
    const result = clearImageCacheDirectory(readerImageCacheDirectory(context));
    const legacy = clearImageCacheDirectory(legacyReaderImageCacheDirectory(context));
    return { files: result.files + legacy.files, bytes: result.bytes + legacy.bytes };
  }

  size(context: common.UIAbilityContext): CacheClearResult {
    return scanImageCacheSize([readerImageCacheDirectory(context), legacyReaderImageCacheDirectory(context)]);
  }

  prune(context: common.UIAbilityContext, protectedPath: string = ''): CachePruneResult {
    return pruneImageCache([
      readerImageCacheDirectory(context),
      legacyReaderImageCacheDirectory(context)
    ], readerImageCacheLimitBytes(), protectedPath);
  }

  private async download(context: common.UIAbilityContext, imageUrl: string, referer: string, path: string,
    priority: boolean, onProgress?: ImageDownloadProgressCallback, options?: ImageDownloadOptions): Promise<string> {
    ensureDirectory(readerImageCacheDirectory(context));
    await acquireImageSlot(priority);
    try {
      return await this.downloadWithRetry(context, imageUrl, referer, path, onProgress, options);
    } finally {
      releaseImageSlot();
    }
  }

  private async downloadWithRetry(context: common.UIAbilityContext, imageUrl: string, referer: string, path: string,
    onProgress?: ImageDownloadProgressCallback, options?: ImageDownloadOptions): Promise<string> {
    let lastError = '';
    const retryLimit = normalizedRetryLimit(options);
    for (let attempt = 0; attempt < retryLimit; attempt++) {
      try {
        return await this.downloadOnce(context, imageUrl, referer, path, attempt, onProgress);
      } catch (error) {
        removeFileQuietly(path);
        lastError = imageNetworkErrorMessage(error);
        ehAppLog.warn(context, 'ReaderImageCache', 'Image attempt failed attempt=' + (attempt + 1).toString() +
          '/' + retryLimit.toString() + ', url=' + trimLogUrl(imageUrl) + ': ' + lastError);
        if (attempt >= retryLimit - 1 || !isTransientImageError(lastError)) {
          throw new Error(lastError);
        }
        await sleepImageRetry(attempt);
      }
    }
    throw new Error(lastError.length > 0 ? lastError : 'Image download failed');
  }

  private async downloadOnce(context: common.UIAbilityContext, imageUrl: string, referer: string, path: string,
    attempt: number, onProgress?: ImageDownloadProgressCallback): Promise<string> {
    const request = http.createHttp();
    trackHttpRequest(request);
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
        connectTimeout: plan.fronted ? IMAGE_CONNECT_TIMEOUT_MS : Math.min(timeout, 30000),
        readTimeout: imageHttpReadTimeoutMs(timeout)
      };
      applyEhNetworkOptions(options, plan);
      const result = await streamImageToFile(request, plan.url, options, path,
        imageRequestDeadlineMs(plan, attempt), onProgress);
      const statusCode = result.statusCode;
      const savedPath = result.path;

      if (statusCode < 200 || statusCode >= 300) {
        const routeOk = statusCode > 0 && statusCode < 500;
        recordEhRequestOutcome(plan, routeOk, Date.now() - startedAt);
        if (!routeOk) {
          hathQualityStore.recordFailure(context, imageUrl);
        }
        outcomeRecorded = true;
        throw new Error(imageStatusMessage(statusCode));
      }

      const size = statFileSize(savedPath);
      if (size <= 0) {
        recordEhRequestOutcome(plan, false, Date.now() - startedAt);
        hathQualityStore.recordFailure(context, imageUrl);
        outcomeRecorded = true;
        throw new Error('Empty image response');
      }
      const elapsedMs = Date.now() - startedAt;
      recordEhRequestOutcome(plan, true, elapsedMs);
      hathQualityStore.recordSuccess(context, imageUrl, elapsedMs, size);
      outcomeRecorded = true;
      if (onProgress !== undefined) {
        onProgress({ receivedBytes: size, totalBytes: size });
      }
      return savedPath;
    } catch (error) {
      if (plan !== null && !outcomeRecorded) {
        recordEhRequestOutcome(plan, false, Date.now() - startedAt);
        hathQualityStore.recordFailure(context, imageUrl);
      }
      throw new Error(imageNetworkErrorMessage(error));
    } finally {
      retireHttpRequest(request);
    }
  }

  private pathFor(context: common.UIAbilityContext, imageUrl: string, cacheKey: string = ''): string {
    return this.pathForExtension(context, imageUrl, imageExtension(imageUrl), cacheKey);
  }

  private legacyPathFor(context: common.UIAbilityContext, imageUrl: string, cacheKey: string = ''): string {
    return legacyReaderImageCacheDirectory(context) + '/' + stableImageKey(normalizeImageCacheKey(imageUrl, cacheKey)) +
      imageExtension(imageUrl);
  }

  private pathForExtension(context: common.UIAbilityContext, imageUrl: string, extension: string,
    cacheKey: string = ''): string {
    return readerImageCacheDirectory(context) + '/' + stableImageKey(normalizeImageCacheKey(imageUrl, cacheKey)) +
      extension;
  }

  private pathCandidates(context: common.UIAbilityContext, imageUrl: string, cacheKey: string = ''): string[] {
    if (explicitImageExtension(imageUrl).length > 0) {
      return [this.pathFor(context, imageUrl, cacheKey)];
    }
    const extensions: string[] = ['.webp', '.jpg', '.jpeg', '.png', '.gif'];
    const paths: string[] = [];
    for (let i = 0; i < extensions.length; i++) {
      paths.push(this.pathForExtension(context, imageUrl, extensions[i], cacheKey));
    }
    return paths;
  }

  private migrateExistingCache(context: common.UIAbilityContext, imageUrl: string, path: string): string {
    const candidates: string[] = [
      this.legacyPathFor(context, imageUrl),
      this.pathFor(context, imageUrl),
      this.legacyPathFor(context, imageUrl, '')
    ];
    for (let i = 0; i < candidates.length; i++) {
      const candidate = candidates[i];
      if (candidate === path || !isUsableCachedImage(candidate)) {
        continue;
      }
      if (migrateLegacyImageCacheFile(candidate, path)) {
        return path;
      }
      return candidate;
    }
    return '';
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
  const value = ehSettingsStore.getValue('download_timeout', '30s');
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

function imageHttpReadTimeoutMs(_baseTimeoutMs: number): number {
  return IMAGE_MAX_TOTAL_TIMEOUT_MS;
}

function imageActiveIdleTimeoutMs(baseTimeoutMs: number): number {
  return Math.max(IMAGE_ACTIVE_IDLE_TIMEOUT_MIN_MS,
    Math.min(IMAGE_ACTIVE_IDLE_TIMEOUT_MAX_MS, Math.max(1, baseTimeoutMs)));
}

function imageUnknownTotalTimeoutMs(baseTimeoutMs: number): number {
  return Math.max(IMAGE_UNKNOWN_TOTAL_TIMEOUT_MS, baseTimeoutMs * 4);
}

function imageDynamicTotalTimeoutMs(baseTimeoutMs: number, totalBytes: number): number {
  if (totalBytes <= 0) {
    return imageUnknownTotalTimeoutMs(baseTimeoutMs);
  }
  const bySize = Math.ceil(totalBytes * 1000 / IMAGE_MIN_EXPECTED_SPEED_BYTES_PER_SECOND) +
    IMAGE_TOTAL_TIMEOUT_MARGIN_MS;
  return Math.max(baseTimeoutMs * 2, bySize);
}

function clampImageTotalTimeout(timeoutMs: number): number {
  return Math.max(IMAGE_ACTIVE_IDLE_TIMEOUT_MIN_MS, Math.min(IMAGE_MAX_TOTAL_TIMEOUT_MS, timeoutMs));
}

function streamImageToFile(request: http.HttpRequest, url: string, options: http.HttpRequestOptions, path: string,
  timeoutMs: number, onProgress?: ImageDownloadProgressCallback): Promise<ImageStreamResult> {
  return new Promise<ImageStreamResult>((resolve: (value: ImageStreamResult) => void,
    reject: (reason: Error) => void) => {
    let finished = false;
    let fd = -1;
    let writtenBytes = 0;
    let receivedBytes = 0;
    let totalBytes = 0;
    let lastProgressBytes = 0;
    let idleTimer = -1;
    let totalTimer = -1;
    let responseExtension = '';
    let pendingFailureMessage = '';
    const tempPath = nextImageTempPath(path);
    removeFileQuietly(tempPath);
    markImageTempPathActive(tempPath);
    try {
      const file = fs.openSync(tempPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
      fd = file.fd;
    } catch (error) {
      unmarkImageTempPathActive(tempPath);
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
        request.off('headersReceive');
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

    const clearTimers = (): void => {
      if (idleTimer >= 0) {
        clearTimeout(idleTimer);
        idleTimer = -1;
      }
      if (totalTimer >= 0) {
        clearTimeout(totalTimer);
        totalTimer = -1;
      }
    };

    const failRequest = (message: string): void => {
      if (finished || pendingFailureMessage.length > 0) {
        return;
      }
      pendingFailureMessage = message;
      clearTimers();
    };

    const armIdleTimer = (delayMs: number): void => {
      if (idleTimer >= 0) {
        clearTimeout(idleTimer);
      }
      idleTimer = setTimeout(() => {
        const seconds = Math.floor(delayMs / 1000);
        failRequest('Image request stalled for ' + seconds.toString() + 's');
      }, delayMs);
    };

    const armTotalTimer = (delayMs: number): void => {
      if (totalTimer >= 0) {
        clearTimeout(totalTimer);
      }
      const safeDelay = clampImageTotalTimeout(delayMs);
      totalTimer = setTimeout(() => {
        failRequest('Image request timed out after ' + Math.floor(safeDelay / 1000).toString() + 's');
      }, safeDelay);
    };

    const updateKnownTotalBytes = (value: number): void => {
      if (value <= totalBytes) {
        return;
      }
      totalBytes = value;
      armTotalTimer(imageDynamicTotalTimeoutMs(timeoutMs, totalBytes));
    };

    const recordReceivedBytes = (value: number): void => {
      if (value <= receivedBytes) {
        return;
      }
      receivedBytes = value;
      if (receivedBytes > lastProgressBytes) {
        lastProgressBytes = receivedBytes;
        armIdleTimer(imageActiveIdleTimeoutMs(timeoutMs));
      }
    };

    armIdleTimer(timeoutMs);
    armTotalTimer(imageUnknownTotalTimeoutMs(timeoutMs));

    request.on('dataReceive', (data: ArrayBuffer) => {
      if (finished || pendingFailureMessage.length > 0) {
        return;
      }
      try {
        fs.writeSync(fd, data);
        writtenBytes += data.byteLength;
        recordReceivedBytes(Math.max(receivedBytes, writtenBytes));
        if (onProgress !== undefined) {
          onProgress({ receivedBytes: receivedBytes, totalBytes: totalBytes });
        }
      } catch (error) {
        failRequest(String(error));
      }
    });
    request.on('headersReceive', (header: Object) => {
      if (finished || pendingFailureMessage.length > 0) {
        return;
      }
      const contentLength = headerContentLength(header);
      responseExtension = headerImageExtension(header);
      if (contentLength > 0) {
        updateKnownTotalBytes(contentLength);
        if (onProgress !== undefined) {
          onProgress({ receivedBytes: receivedBytes, totalBytes: totalBytes });
        }
      }
    });
    request.on('dataReceiveProgress', (progress: http.DataReceiveProgressInfo) => {
      if (finished || pendingFailureMessage.length > 0) {
        return;
      }
      updateKnownTotalBytes(progress.totalSize);
      recordReceivedBytes(Math.max(receivedBytes, progress.receiveSize));
      if (onProgress !== undefined) {
        onProgress({ receivedBytes: receivedBytes, totalBytes: totalBytes });
      }
    });

    request.requestInStream(url, options).then((statusCode: number) => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimers();
      cleanup();
      if (pendingFailureMessage.length > 0) {
        removeFileQuietly(tempPath);
        unmarkImageTempPathActive(tempPath);
        reject(new Error(pendingFailureMessage));
        return;
      }
      const finalPath = responseImagePath(path, responseExtension);
      if (statusCode >= 200 && statusCode < 300 && receivedBytes > 0) {
        try {
          removeFileQuietly(finalPath);
          fs.moveFileSync(tempPath, finalPath);
        } catch (error) {
          removeFileQuietly(tempPath);
          unmarkImageTempPathActive(tempPath);
          reject(new Error(String(error)));
          return;
        }
      } else {
        removeFileQuietly(tempPath);
      }
      unmarkImageTempPathActive(tempPath);
      resolve({ statusCode: Number(statusCode), path: finalPath });
    }).catch((error: Error) => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimers();
      cleanup();
      removeFileQuietly(tempPath);
      unmarkImageTempPathActive(tempPath);
      reject(pendingFailureMessage.length > 0 ? new Error(pendingFailureMessage) : error);
    });
  });
}

function headerContentLength(header: Object): number {
  const headers = header as Record<string, Object>;
  const keys = Object.keys(headers);
  for (let i = 0; i < keys.length; i++) {
    if (keys[i].toLowerCase() !== 'content-length') {
      continue;
    }
    const value = headers[keys[i]];
    if (typeof value === 'number') {
      return value > 0 ? value : 0;
    }
    if (typeof value === 'string') {
      const parsed = Number.parseInt(value, 10);
      return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
    }
    if (Array.isArray(value) && value.length > 0) {
      const first = value[0] as Object;
      if (typeof first === 'string') {
        const parsed = Number.parseInt(first, 10);
        return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
      }
    }
  }
  return 0;
}

function headerImageExtension(header: Object): string {
  const headers = header as Record<string, Object>;
  const keys = Object.keys(headers);
  for (let i = 0; i < keys.length; i++) {
    if (keys[i].toLowerCase() !== 'content-type') {
      continue;
    }
    return contentTypeImageExtension(headers[keys[i]]);
  }
  return '';
}

function contentTypeImageExtension(value: Object): string {
  if (typeof value === 'string') {
    return imageExtensionFromContentType(value);
  }
  if (Array.isArray(value) && value.length > 0) {
    const first = value[0] as Object;
    if (typeof first === 'string') {
      return imageExtensionFromContentType(first);
    }
  }
  return '';
}

function imageExtensionFromContentType(value: string): string {
  const type = value.split(';')[0].trim().toLowerCase();
  if (type === 'image/webp') {
    return '.webp';
  }
  if (type === 'image/png') {
    return '.png';
  }
  if (type === 'image/gif') {
    return '.gif';
  }
  if (type === 'image/jpeg' || type === 'image/jpg') {
    return '.jpg';
  }
  return '';
}

function responseImagePath(path: string, responseExtension: string): string {
  if (responseExtension.length === 0) {
    return path;
  }
  const currentExtension = pathImageExtension(path);
  if (currentExtension.length > 0 && currentExtension !== '.jpg') {
    return path;
  }
  if (currentExtension === responseExtension) {
    return path;
  }
  if (currentExtension.length === 0) {
    return path + responseExtension;
  }
  return path.substring(0, path.length - currentExtension.length) + responseExtension;
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

function normalizedRetryLimit(options?: ImageDownloadOptions): number {
  if (options === undefined || options.retryLimit === undefined) {
    return DEFAULT_IMAGE_RETRY_LIMIT;
  }
  return Math.max(1, Math.min(DEFAULT_IMAGE_RETRY_LIMIT, Math.round(options.retryLimit)));
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
    lower.indexOf('curlcode result 35') >= 0 || lower.indexOf('curl code 35') >= 0 ||
    lower.indexOf('curl_code') >= 0 && lower.indexOf('35') >= 0 ||
    lower.indexOf('http2') >= 0 || lower.indexOf('2300016') >= 0 || lower.indexOf('2300999') >= 0 ||
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

function trimLogUrl(url: string): string {
  if (url.length <= 180) {
    return url;
  }
  return url.substring(0, 177) + '...';
}

function imageNetworkErrorMessage(error: Object): string {
  let message = readableImageErrorMessage(error);
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
  if (lower.indexOf('curlcode result 35') >= 0 || lower.indexOf('curl code 35') >= 0 ||
    lower.indexOf('curl_code') >= 0 && lower.indexOf('35') >= 0 || lower.indexOf('2300999') >= 0) {
    return 'Image TLS connection failed';
  }
  if (lower.indexOf('dns') >= 0 || lower.indexOf('unknownhost') >= 0) {
    return 'Image DNS lookup failed';
  }
  return message.length > 0 ? message : 'Image download failed';
}

function readableImageErrorMessage(error: Object): string {
  if (error instanceof Error && error.message.length > 0) {
    return error.message;
  }
  const record = error as Record<string, Object>;
  const message = record['message'];
  const code = record['code'];
  if (typeof message === 'string' && message.length > 0) {
    if (typeof code === 'number' || typeof code === 'string') {
      return 'code ' + String(code) + ': ' + message;
    }
    return message;
  }
  try {
    const json = JSON.stringify(error);
    if (json.length > 0 && json !== '{}') {
      return json;
    }
  } catch (jsonError) {
  }
  return String(error);
}

function removeFileQuietly(path: string): void {
  try {
    if (exists(path)) {
      fs.unlinkSync(path);
    }
  } catch (error) {
  }
}

function nextImageTempPath(path: string): string {
  imageTempFileSequence++;
  return path + '.' + Date.now().toString() + '_' + imageTempFileSequence.toString() + '.part';
}

function markImageTempPathActive(path: string): void {
  if (ACTIVE_IMAGE_TEMP_PATHS.indexOf(path) < 0) {
    ACTIVE_IMAGE_TEMP_PATHS.push(path);
  }
}

function unmarkImageTempPathActive(path: string): void {
  const index = ACTIVE_IMAGE_TEMP_PATHS.indexOf(path);
  if (index >= 0) {
    ACTIVE_IMAGE_TEMP_PATHS.splice(index, 1);
  }
}

function isImageTempPathActive(path: string): boolean {
  return ACTIVE_IMAGE_TEMP_PATHS.indexOf(path) >= 0;
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

function clearImageCacheDirectory(directory: string): CacheClearResult {
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

function isUsableCachedImage(path: string): boolean {
  if (path.length === 0 || path.endsWith('.part')) {
    return false;
  }
  return statFileSize(path) > 0;
}

function statFileSize(path: string): number {
  try {
    return fs.statSync(path).size;
  } catch (error) {
    return 0;
  }
}

function migrateLegacyImageCacheFile(legacyPath: string, path: string): boolean {
  ensureDirectory(parentDirectory(path));
  try {
    fs.moveFileSync(legacyPath, path);
    return true;
  } catch (error) {
  }
  try {
    fs.copyFileSync(legacyPath, path);
    removeFileQuietly(legacyPath);
    return exists(path);
  } catch (error) {
    removeFileQuietly(path);
  }
  return false;
}

function parentDirectory(path: string): string {
  const index = path.lastIndexOf('/');
  return index > 0 ? path.substring(0, index) : path;
}

export function readerImageCacheDirectory(context: common.UIAbilityContext): string {
  return context.filesDir + '/reader_images';
}

function legacyReaderImageCacheDirectory(context: common.UIAbilityContext): string {
  return context.cacheDir + '/reader_images';
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

export function readerImageCacheLimitBytes(): number {
  return parseCacheSizeBytes(ehSettingsStore.getValue('read_cache_size', '160 MB'));
}

function parseCacheSizeBytes(value: string): number {
  const normalized = value.trim().toUpperCase();
  if (normalized === '40 MB' || normalized === '80 MB') {
    return DEFAULT_IMAGE_CACHE_BYTES;
  }
  if (normalized.endsWith('MB')) {
    const numberPart = normalized.substring(0, normalized.length - 2).trim();
    const mb = Number.parseInt(numberPart, 10);
    if (Number.isFinite(mb) && mb > 0) {
      return Math.max(160, Math.min(2048, mb)) * 1024 * 1024;
    }
  }
  if (normalized.endsWith('GB')) {
    const numberPart = normalized.substring(0, normalized.length - 2).trim();
    const gb = Number.parseInt(numberPart, 10);
    if (Number.isFinite(gb) && gb > 0) {
      return Math.max(1, Math.min(2, gb)) * 1024 * 1024 * 1024;
    }
  }
  return DEFAULT_IMAGE_CACHE_BYTES;
}

function scanImageCacheSize(directories: string[]): CacheClearResult {
  let files = 0;
  let bytes = 0;
  const entries = scanImageCacheFiles(directories);
  for (let i = 0; i < entries.length; i++) {
    files++;
    bytes += entries[i].size;
  }
  return { files: files, bytes: bytes };
}

function pruneImageCache(directories: string[], maxBytes: number, protectedPath: string = ''): CachePruneResult {
  let files: CachedImageFile[] = [];
  let total = 0;
  let removedFiles = 0;
  let removedBytes = 0;
  files = scanImageCacheFiles(directories);
  for (let i = 0; i < files.length; i++) {
    total += files[i].size;
  }

  if (total <= maxBytes) {
    return { files: 0, bytes: 0, remainingBytes: total };
  }

  files = files.sort((left: CachedImageFile, right: CachedImageFile) => left.modifiedAt - right.modifiedAt);
  for (let i = 0; i < files.length && total > maxBytes; i++) {
    if (protectedPath.length > 0 && files[i].path === protectedPath) {
      continue;
    }
    if (removeFile(files[i].path)) {
      removedFiles++;
      removedBytes += files[i].size;
      total -= files[i].size;
    }
  }
  return { files: removedFiles, bytes: removedBytes, remainingBytes: total };
}

function scanImageCacheFiles(directories: string[]): CachedImageFile[] {
  const files: CachedImageFile[] = [];
  for (let i = 0; i < directories.length; i++) {
    files.push(...scanImageCacheDirectory(directories[i]));
  }
  return files;
}

function scanImageCacheDirectory(directory: string): CachedImageFile[] {
  const files: CachedImageFile[] = [];
  try {
    const names = fs.listFileSync(directory);
    for (let i = 0; i < names.length; i++) {
      const path = directory + '/' + names[i];
      try {
        const stat = fs.statSync(path);
        if (stat.isDirectory()) {
          continue;
        }
        if (path.endsWith('.part')) {
          if (!isImageTempPathActive(path)) {
            removeFileQuietly(path);
          }
          continue;
        }
        files.push({
          path: path,
          size: stat.size,
          modifiedAt: stat.mtime
        });
      } catch (error) {
      }
    }
  } catch (error) {
  }
  return files;
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

function normalizeImageCacheKey(imageUrl: string, cacheKey: string): string {
  return cacheKey.length > 0 ? cacheKey : imageUrl;
}

function imageDownloadPendingKey(imageUrl: string, cacheKey: string): string {
  return normalizeImageCacheKey(imageUrl, cacheKey) + '|' + imageUrl;
}

function explicitImageExtension(url: string): string {
  const clean = url.split('?')[0].toLowerCase();
  const dot = clean.lastIndexOf('.');
  if (dot >= 0) {
    const extension = clean.substring(dot);
    if (extension === '.jpg' || extension === '.jpeg' || extension === '.png' || extension === '.webp' ||
      extension === '.gif') {
      return extension;
    }
  }
  return '';
}

function pathImageExtension(path: string): string {
  const dot = path.lastIndexOf('.');
  if (dot < 0) {
    return '';
  }
  const extension = path.substring(dot).toLowerCase();
  if (extension === '.jpg' || extension === '.jpeg' || extension === '.png' || extension === '.webp' ||
    extension === '.gif') {
    return extension;
  }
  return '';
}

function imageExtension(url: string): string {
  const explicit = explicitImageExtension(url);
  if (explicit.length > 0) {
    return explicit;
  }
  return '.jpg';
}

export const readerImageCache: ReaderImageCache = new ReaderImageCache();
