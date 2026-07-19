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
  isEhRouteReachableStatus,
  recordEhRequestOutcome
} from './EhNetworkConfig';
import { ehSettingsStore } from './EhSettingsStore';
import { hathQualityStore } from './HathQualityStore';
import { cancelHttpRequest, retireHttpRequest, trackHttpRequest } from './HttpRequestLifecycle';

interface PendingImageDownload {
  url: string;
  promise: Promise<string>;
  listeners: ImageDownloadProgressCallback[];
  lastProgress: ImageDownloadProgress;
  priority: number;
}

interface WaitingImageSlot {
  key: string;
  priority: number;
  sequence: number;
  background: boolean;
  serializedHath: boolean;
  resolve: (slot: AcquiredImageSlot) => void;
  reject: (error: Error) => void;
}

interface AcquiredImageSlot {
  background: boolean;
  serializedHath: boolean;
}

interface ActiveImageRequest {
  request: http.HttpRequest;
  priority: number;
  cancelRequested: boolean;
}

const PENDING_IMAGE_DOWNLOADS: PendingImageDownload[] = [];
const WAITING_IMAGE_SLOTS: WaitingImageSlot[] = [];
const ACTIVE_IMAGE_REQUESTS: ActiveImageRequest[] = [];
const ACTIVE_IMAGE_TEMP_PATHS: string[] = [];
const DEFAULT_IMAGE_CACHE_BYTES: number = 160 * 1024 * 1024;
const IMAGE_RETRY_DELAYS_MS: number[] = [300, 900, 1800, 3200];
const IMAGE_CONNECT_TIMEOUT_MS: number = 4500;
const IMAGE_RESPONSE_MAX_BYTES: number = 128 * 1024 * 1024;
const DEFAULT_IMAGE_RETRY_LIMIT: number = 5;
const MAX_BACKGROUND_IMAGE_DOWNLOADS: number = 4;
const BACKGROUND_IMAGE_RESUME_DELAY_MS: number = 750;
let activeImageDownloads: number = 0;
let activeBackgroundImageDownloads: number = 0;
let activeSerializedHathDownloads: number = 0;
let imageTempFileSequence: number = 0;
let imageSlotSequence: number = 0;
let backgroundImageDispatchPaused: boolean = false;
let backgroundImageResumeTimer: number = -1;

export const IMAGE_DOWNLOAD_PRIORITY_BACKGROUND: number = 0;
export const IMAGE_DOWNLOAD_PRIORITY_DOWNLOAD: number = 10;
export const IMAGE_DOWNLOAD_PRIORITY_INTERACTIVE: number = 50;
export const IMAGE_DOWNLOAD_PRIORITY_READER: number = 100;

interface CachedImageFile {
  path: string;
  size: number;
  modifiedAt: number;
}

interface ImageTransferResult {
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
    priority: number = IMAGE_DOWNLOAD_PRIORITY_BACKGROUND, onProgress?: ImageDownloadProgressCallback,
    cacheKey: string = '',
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
      if (priority > pending.priority) {
        pending.priority = priority;
        promoteImageSlot(pendingKey, priority);
      }
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
    const promise = this.download(context, imageUrl, referer, path, pendingKey, priority, progressCallback, options);
    putPending(pendingKey, promise, listeners, priority);
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
    pendingKey: string, priority: number, onProgress?: ImageDownloadProgressCallback,
    options?: ImageDownloadOptions): Promise<string> {
    ensureDirectory(readerImageCacheDirectory(context));
    const slot = await acquireImageSlot(pendingKey, imageUrl, priority);
    try {
      return await this.downloadWithRetry(context, imageUrl, referer, path, priority, onProgress, options);
    } finally {
      releaseImageSlot(slot);
    }
  }

  private async downloadWithRetry(context: common.UIAbilityContext, imageUrl: string, referer: string, path: string,
    priority: number, onProgress?: ImageDownloadProgressCallback, options?: ImageDownloadOptions): Promise<string> {
    let lastError = '';
    const retryLimit = normalizedRetryLimit(options);
    for (let attempt = 0; attempt < retryLimit; attempt++) {
      try {
        return await this.downloadOnce(context, imageUrl, referer, path, attempt, priority, onProgress);
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
    attempt: number, priority: number, onProgress?: ImageDownloadProgressCallback): Promise<string> {
    const request = http.createHttp();
    trackHttpRequest(request);
    let plan: EhRequestPlan | null = null;
    let activeRequest: ActiveImageRequest | null = null;
    let tempPath = '';
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
        maxLimit: IMAGE_RESPONSE_MAX_BYTES,
        connectTimeout: imageConnectTimeoutMs(plan, imageUrl, timeout),
        readTimeout: imageRequestDeadlineMs(plan, attempt)
      };
      applyEhNetworkOptions(options, plan);
      request.on('dataReceiveProgress', (progress: http.DataReceiveProgressInfo): void => {
        if (onProgress !== undefined) {
          onProgress({
            receivedBytes: Math.max(0, progress.receiveSize),
            totalBytes: Math.max(0, progress.totalSize)
          });
        }
      });
      activeRequest = registerActiveImageRequest(request, priority);
      const response = await request.request(plan.url, options);
      if (activeRequest.cancelRequested) {
        throw new Error('Reader image request cancelled');
      }
      tempPath = nextImageTempPath(path);
      removeFileQuietly(tempPath);
      markImageTempPathActive(tempPath);
      const result = finishImageBufferTransfer(response, tempPath, path);
      const statusCode = result.statusCode;
      const savedPath = result.path;

      if (statusCode < 200 || statusCode >= 300) {
        const routeOk = isEhRouteReachableStatus(statusCode);
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
      if (activeRequest !== null && activeRequest.cancelRequested) {
        outcomeRecorded = true;
        throw new Error('Reader image request cancelled');
      }
      if (plan !== null && !outcomeRecorded) {
        recordEhRequestOutcome(plan, false, Date.now() - startedAt);
        hathQualityStore.recordFailure(context, imageUrl);
      }
      throw new Error(imageNetworkErrorMessage(error));
    } finally {
      try {
        request.off('dataReceiveProgress');
      } catch (_error) {
      }
      if (activeRequest !== null) {
        unregisterActiveImageRequest(activeRequest);
      }
      retireHttpRequest(request);
      if (tempPath.length > 0) {
        removeFileQuietly(tempPath);
        unmarkImageTempPathActive(tempPath);
      }
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

function imageConnectTimeoutMs(plan: EhRequestPlan, imageUrl: string, timeoutMs: number): number {
  if (plan.fronted) {
    return IMAGE_CONNECT_TIMEOUT_MS;
  }
  if (shouldSerializeHathImage(imageUrl)) {
    return Math.min(timeoutMs, 8000);
  }
  return Math.min(timeoutMs, 30000);
}

function finishImageBufferTransfer(response: http.HttpResponse, tempPath: string, path: string): ImageTransferResult {
  const statusCode = Number(response.responseCode);
  const finalPath = responseImagePath(path, headerImageExtension(response.header));
  if (statusCode >= 200 && statusCode < 300) {
    if (!(response.result instanceof ArrayBuffer) || response.result.byteLength <= 0) {
      throw new Error('Empty image response');
    }
    let fd = -1;
    try {
      const file = fs.openSync(tempPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
      fd = file.fd;
      fs.writeSync(fd, response.result);
      fs.closeSync(fd);
      fd = -1;
      removeFileQuietly(finalPath);
      fs.moveFileSync(tempPath, finalPath);
    } catch (error) {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (_closeError) {
        }
      }
      removeFileQuietly(tempPath);
      throw new Error(String(error));
    }
  } else {
    removeFileQuietly(tempPath);
  }
  return {
    statusCode: statusCode,
    path: finalPath
  };
}

function registerActiveImageRequest(request: http.HttpRequest, priority: number): ActiveImageRequest {
  const active: ActiveImageRequest = {
    request: request,
    priority: priority,
    cancelRequested: false
  };
  ACTIVE_IMAGE_REQUESTS.push(active);
  return active;
}

function unregisterActiveImageRequest(active: ActiveImageRequest): void {
  const index = ACTIVE_IMAGE_REQUESTS.indexOf(active);
  if (index >= 0) {
    ACTIVE_IMAGE_REQUESTS.splice(index, 1);
  }
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
    lower.indexOf('socket') >= 0 || lower.indexOf('network') >= 0 || lower.indexOf('incomplete') >= 0 ||
    lower.indexOf('partial') >= 0 || lower.indexOf('transfer closed') >= 0 || lower.indexOf('recv') >= 0 ||
    lower.indexOf('receive') >= 0 || lower.indexOf('503') >= 0 ||
    lower.indexOf('504') >= 0 || lower.indexOf('522') >= 0 || lower.indexOf('524') >= 0 ||
    lower.indexOf('500') >= 0 || lower.indexOf('502') >= 0 || lower.indexOf('520') >= 0 ||
    lower.indexOf('521') >= 0 || lower.indexOf('523') >= 0 || lower.indexOf('525') >= 0 ||
    lower.indexOf('526') >= 0 ||
    lower.indexOf('ssl') >= 0 || lower.indexOf('tls') >= 0 || lower.indexOf('certificate') >= 0 ||
    lower.indexOf('curlcode result 35') >= 0 || lower.indexOf('curl code 35') >= 0 ||
    lower.indexOf('curl_code') >= 0 && lower.indexOf('35') >= 0 ||
    lower.indexOf('http2') >= 0 || lower.indexOf('2300016') >= 0 || lower.indexOf('2300018') >= 0 ||
    lower.indexOf('2300028') >= 0 || lower.indexOf('2300056') >= 0 || lower.indexOf('2300999') >= 0 ||
    lower.indexOf('curl 18') >= 0 || lower.indexOf('curl 28') >= 0 || lower.indexOf('curl 56') >= 0 ||
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
  if (lower.indexOf('2300028') >= 0 || lower.indexOf('curlcode result 28') >= 0 ||
    lower.indexOf('curl code 28') >= 0) {
    return 'Image network timeout';
  }
  if (lower.indexOf('2300018') >= 0 || lower.indexOf('curlcode result 18') >= 0 ||
    lower.indexOf('curl code 18') >= 0 || lower.indexOf('partial') >= 0 ||
    lower.indexOf('transfer closed') >= 0) {
    return 'Image transfer incomplete';
  }
  if (lower.indexOf('2300056') >= 0 || lower.indexOf('curlcode result 56') >= 0 ||
    lower.indexOf('curl code 56') >= 0 || lower.indexOf('recv') >= 0 || lower.indexOf('receive') >= 0) {
    return 'Image network connection interrupted';
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

function putPending(url: string, promise: Promise<string>, listeners: ImageDownloadProgressCallback[],
  priority: number): void {
  removePending(url);
  PENDING_IMAGE_DOWNLOADS.push({
    url: url,
    promise: promise,
    listeners: listeners,
    lastProgress: { receivedBytes: 0, totalBytes: 0 },
    priority: priority
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

function configuredImageDownloadLimit(): number {
  const value = Number.parseInt(ehSettingsStore.getValue('download_thread', '3'));
  if (Number.isNaN(value) || value <= 0) {
    return 1;
  }
  return Math.max(1, Math.min(value, 10));
}

function acquireImageSlot(key: string, imageUrl: string, priority: number): Promise<AcquiredImageSlot> {
  return new Promise<AcquiredImageSlot>((resolve: (value: AcquiredImageSlot | PromiseLike<AcquiredImageSlot>) => void,
    reject: (reason?: Object) => void) => {
    WAITING_IMAGE_SLOTS.push({
      key: key,
      priority: priority,
      sequence: imageSlotSequence++,
      background: isBackgroundImagePriority(priority),
      serializedHath: shouldSerializeHathImage(imageUrl),
      resolve: resolve,
      reject: (error: Error) => {
        reject(error);
      }
    });
    dispatchWaitingImageSlots();
  });
}

function releaseImageSlot(slot: AcquiredImageSlot): void {
  activeImageDownloads = Math.max(0, activeImageDownloads - 1);
  if (slot.background) {
    activeBackgroundImageDownloads = Math.max(0, activeBackgroundImageDownloads - 1);
  }
  if (slot.serializedHath) {
    activeSerializedHathDownloads = Math.max(0, activeSerializedHathDownloads - 1);
  }
  dispatchWaitingImageSlots();
}

function promoteImageSlot(key: string, priority: number): void {
  for (let i = 0; i < WAITING_IMAGE_SLOTS.length; i++) {
    if (WAITING_IMAGE_SLOTS[i].key === key && priority > WAITING_IMAGE_SLOTS[i].priority) {
      WAITING_IMAGE_SLOTS[i].priority = priority;
    }
  }
  dispatchWaitingImageSlots();
}

function dispatchWaitingImageSlots(): void {
  const limit = configuredImageDownloadLimit();
  while (activeImageDownloads < limit && WAITING_IMAGE_SLOTS.length > 0) {
    let bestIndex = -1;
    for (let i = 0; i < WAITING_IMAGE_SLOTS.length; i++) {
      const candidate = WAITING_IMAGE_SLOTS[i];
      if (!canDispatchImageSlot(candidate, limit)) {
        continue;
      }
      if (bestIndex < 0) {
        bestIndex = i;
        continue;
      }
      const best = WAITING_IMAGE_SLOTS[bestIndex];
      if (candidate.priority > best.priority ||
        (candidate.priority === best.priority && candidate.sequence < best.sequence)) {
        bestIndex = i;
      }
    }
    if (bestIndex < 0) {
      return;
    }
    const next = WAITING_IMAGE_SLOTS.splice(bestIndex, 1)[0];
    activeImageDownloads++;
    if (next.background) {
      activeBackgroundImageDownloads++;
    }
    if (next.serializedHath) {
      activeSerializedHathDownloads++;
    }
    next.resolve({
      background: next.background,
      serializedHath: next.serializedHath
    });
  }
}

function canDispatchImageSlot(slot: WaitingImageSlot, totalLimit: number): boolean {
  if (slot.serializedHath && activeSerializedHathDownloads > 0) {
    return false;
  }
  if (!slot.background) {
    return true;
  }
  if (backgroundImageDispatchPaused) {
    return false;
  }
  return activeBackgroundImageDownloads < Math.min(totalLimit, MAX_BACKGROUND_IMAGE_DOWNLOADS);
}

function isBackgroundImagePriority(priority: number): boolean {
  return priority <= IMAGE_DOWNLOAD_PRIORITY_BACKGROUND;
}

function shouldSerializeHathImage(imageUrl: string): boolean {
  if (ehSettingsStore.getValue('domain_fronting', 'Off') !== 'On') {
    return false;
  }
  const match = /^https?:\/\/([^\/?#]+)/i.exec(imageUrl);
  if (match === null) {
    return false;
  }
  let host = match[1].toLowerCase();
  if (host.startsWith('[')) {
    const closingBracket = host.indexOf(']');
    host = closingBracket > 0 ? host.substring(1, closingBracket) : host;
  } else {
    const portSeparator = host.lastIndexOf(':');
    if (portSeparator > 0) {
      host = host.substring(0, portSeparator);
    }
  }
  return host === 's.exhentai.org' || host.endsWith('.hath.network');
}

export function cancelQueuedReaderImageRequests(): number {
  let cancelled = 0;
  for (let i = WAITING_IMAGE_SLOTS.length - 1; i >= 0; i--) {
    if (WAITING_IMAGE_SLOTS[i].priority < IMAGE_DOWNLOAD_PRIORITY_READER) {
      continue;
    }
    const waiting = WAITING_IMAGE_SLOTS.splice(i, 1)[0];
    waiting.reject(new Error('Reader image request cancelled'));
    cancelled++;
  }
  for (let i = 0; i < ACTIVE_IMAGE_REQUESTS.length; i++) {
    const active = ACTIVE_IMAGE_REQUESTS[i];
    if (active.priority < IMAGE_DOWNLOAD_PRIORITY_READER || active.cancelRequested) {
      continue;
    }
    active.cancelRequested = true;
    cancelHttpRequest(active.request);
    cancelled++;
  }
  return cancelled;
}

export function pauseBackgroundImageRequests(): void {
  backgroundImageDispatchPaused = true;
  if (backgroundImageResumeTimer >= 0) {
    clearTimeout(backgroundImageResumeTimer);
    backgroundImageResumeTimer = -1;
  }
}

export function resumeBackgroundImageRequests(): void {
  pauseBackgroundImageRequests();
  backgroundImageResumeTimer = setTimeout(() => {
    backgroundImageResumeTimer = -1;
    backgroundImageDispatchPaused = false;
    dispatchWaitingImageSlots();
  }, BACKGROUND_IMAGE_RESUME_DELAY_MS);
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
