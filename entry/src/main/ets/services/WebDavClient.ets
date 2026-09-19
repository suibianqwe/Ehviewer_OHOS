import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { RemoteStorageProfile } from './RemoteStorageProfiles';
import { logRemoteStorageError, logRemoteStorageInfo, logRemoteStorageWarn } from './RemoteStorageLog';
import {
  RemoteStorageListEntry,
  isRedirectStatus,
  normalizeRemoteStorageBasePath,
  normalizeRemoteStorageUrl,
  parseWebDavMultiStatus,
  remoteStorageApplyPort,
  remoteStorageUrlForPath,
  resolveRedirectUrl,
  webDavStatusMessage
} from './RemoteStorageSupport';

const MAX_REDIRECT_HOPS: number = 4;
const REMOTE_STORAGE_CONNECT_TIMEOUT_MS: number = 10000;
const REMOTE_STORAGE_READ_TIMEOUT_MS: number = 30000;
const REMOTE_STORAGE_UPLOAD_TIMEOUT_MS: number = 60000;
const REMOTE_STORAGE_RESUMABLE_THRESHOLD: number = 1048576;
const REMOTE_STORAGE_CHUNK_BYTES: number = 1048576;

interface WebDavHeader {
  'Accept'?: string;
  'Authorization'?: string;
  'Depth'?: string;
  'Content-Type'?: string;
  'Content-Range'?: string;
}

interface DavHeaderShape {
  'DAV'?: string;
  'dav'?: string;
}
interface WebDavRawResponse {
  ok: boolean;
  statusCode: number;
  message: string;
  body: string;
  headers?: Object;
}
interface WebDavRedirectResult {
  response: http.HttpResponse;
  url: string;
}

let activeWebDavRequests: number = 0;
const WEBDAV_MAX_INFLIGHT: number = 3;

async function waitWebDavSlot(): Promise<void> {
  while (activeWebDavRequests >= WEBDAV_MAX_INFLIGHT) {
    await new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, 40);
    });
  }
  activeWebDavRequests++;
}

function releaseWebDavSlot(): void {
  if (activeWebDavRequests > 0) {
    activeWebDavRequests--;
  }
}

export interface RemoteStorageResult {
  ok: boolean;
  statusCode: number;
  message: string;
}

export interface RemoteStorageTextResult {
  ok: boolean;
  statusCode: number;
  message: string;
  text: string;
}

export interface RemoteStorageListResult {
  ok: boolean;
  statusCode: number;
  message: string;
  entries: RemoteStorageListEntry[];
}

function extractDavHeader(headers: Object | undefined): string {
  if (headers === undefined || headers === null) {
    return '';
  }
  const shape = headers as DavHeaderShape;
  if (typeof shape.DAV === 'string') {
    return shape.DAV;
  }
  if (typeof shape.dav === 'string') {
    return shape.dav;
  }
  return '';
}
 function responseHeaderValue(headers: Object | undefined, name: string): string {
  if (headers === undefined || headers === null) {
    return '';
  }
  const record = headers as Record<string, Object>;
  const keys = Object.keys(record);
  for (let i = 0; i < keys.length; i++) {
    if (keys[i].toLowerCase() === name.toLowerCase()) {
      const value = record[keys[i]];
      if (typeof value === 'string') {
        return value;
      }
    }
  }
  return '';
}

function webDavAuthorizationValue(username: string, password: string): string {
  const encoder = util.TextEncoder.create('utf-8');
  const bytes = encoder.encodeInto(username + ':' + password);
  const base64 = new util.Base64Helper().encodeToStringSync(bytes);
  return 'Basic ' + base64;
}

export class WebDavClient {
  private readonly profile: RemoteStorageProfile;
  private ensuredDirectories: string[] = [];
  private partialUpdateSupported: boolean = false;
  private partialUpdateChecked: boolean = false;

  constructor(profile: RemoteStorageProfile) {
    this.profile = profile;
  }

  baseUrl(): string {
    const url = remoteStorageApplyPort(normalizeRemoteStorageUrl(this.profile.url), this.profile.port);
    const base = normalizeRemoteStorageBasePath(this.profile.basePath);
    return base.length > 0 ? url + '/' + base : url;
  }

  async testConnection(): Promise<RemoteStorageResult> {
    logRemoteStorageInfo('test connection base=' + this.baseUrl() + ' user=' +
      (this.profile.username.length > 0 ? 'set' : 'anonymous'));
    const response = await this.send('PROPFIND', '', '0', '', '');
    if (response.ok) {
      logRemoteStorageInfo('test connection succeeded status=' + response.statusCode.toString());
      return { ok: true, statusCode: response.statusCode, message: '' };
    }
    logRemoteStorageWarn('test connection failed status=' + response.statusCode.toString() +
      ' message=' + response.message);
    return { ok: false, statusCode: response.statusCode, message: response.message };
  }

  async list(path: string): Promise<RemoteStorageListResult> {
    const response = await this.send('PROPFIND', path, '1', '', '');
    if (!response.ok) {
      return { ok: false, statusCode: response.statusCode, message: response.message, entries: [] };
    }
    return {
      ok: true,
      statusCode: response.statusCode,
      message: '',
      entries: parseWebDavMultiStatus(response.body, normalizeRemoteStorageBasePath(this.profile.basePath))
    };
  }

  async ensureDirectory(path: string): Promise<RemoteStorageResult> {
    const normalized = path.trim().replace(/^\/+|\/+$/g, '');
    if (normalized.length === 0) {
      return { ok: true, statusCode: 200, message: '' };
    }
    if (this.ensuredDirectories.indexOf(normalized) >= 0) {
      return { ok: true, statusCode: 200, message: '' };
    }
    const segments = normalized.split('/');
    let current = '';
    let lastStatus = 200;
    for (let i = 0; i < segments.length; i++) {
      const segment = segments[i].trim();
      if (segment.length === 0) {
        continue;
      }
      current = current.length > 0 ? current + '/' + segment : segment;
      const response = await this.send('MKCOL', current, '', '', '');
      lastStatus = response.statusCode;
      if (!response.ok && response.statusCode !== 405 && response.statusCode !== 301) {
        return { ok: false, statusCode: response.statusCode, message: response.message };
      }
    }
    this.ensuredDirectories.push(normalized);
    return { ok: true, statusCode: lastStatus, message: '' };
  }

  async putText(path: string, text: string): Promise<RemoteStorageResult> {
    const parent = parentRemotePath(path);
    if (parent.length > 0) {
      const directory = await this.ensureDirectory(parent);
      if (!directory.ok) {
        return directory;
      }
    }
    logRemoteStorageInfo('put text path=' + path + ' bytes=' + text.length.toString());
    const response = await this.send('PUT', path, '', text, 'application/json; charset=utf-8');
    return { ok: response.ok, statusCode: response.statusCode, message: response.message };
  }

  async getText(path: string): Promise<RemoteStorageTextResult> {
    const response = await this.send('GET', path, '', '', '');
    return {
      ok: response.ok,
      statusCode: response.statusCode,
      message: response.message,
      text: response.ok ? response.body : ''
    };
  }

  async putBinary(path: string, data: ArrayBuffer): Promise<RemoteStorageResult> {
    const parent = parentRemotePath(path);
    if (parent.length > 0) {
      const directory = await this.ensureDirectory(parent);
      if (!directory.ok) {
        return directory;
      }
    }
    const url = remoteStorageUrlForPath(this.baseUrl(), path);
    const hasCredentials = this.profile.username.length > 0 || this.profile.password.length > 0;
    const header: WebDavHeader = hasCredentials ? {
      'Accept': '*/*',
      'Authorization': webDavAuthorizationValue(this.profile.username, this.profile.password),
      'Depth': '',
      'Content-Type': 'application/octet-stream'
    } : {
      'Accept': '*/*',
      'Depth': '',
      'Content-Type': 'application/octet-stream'
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.PUT,
      customMethod: 'PUT',
      header: header,
      expectDataType: http.HttpDataType.STRING,
      extraData: data,
      connectTimeout: REMOTE_STORAGE_CONNECT_TIMEOUT_MS,
      readTimeout: REMOTE_STORAGE_UPLOAD_TIMEOUT_MS,
      usingCache: false,
      reuseConnections: false
    };
    const startedAt = Date.now();
    logRemoteStorageInfo('request PUT ' + url + ' bodyBytes=' + data.byteLength.toString());
    await waitWebDavSlot();
    try {
      const result = await this.requestWithRedirects(url, options);
      const statusCode = Number(result.response.responseCode);
      const ok = statusCode >= 200 && statusCode < 300;
      logRemoteStorageInfo('response PUT ' + url + ' -> ' + statusCode.toString() + ' in ' +
        (Date.now() - startedAt).toString() + 'ms');
      return { ok: ok, statusCode: statusCode, message: ok ? '' : webDavStatusMessage(statusCode) };
    } catch (error) {
      const message = remoteStorageErrorMessage(error);
      logRemoteStorageError('request PUT ' + url + ' failed: ' + message);
      return { ok: false, statusCode: 0, message: message };
    } finally {
      releaseWebDavSlot();
    }
  }

  async getBinary(path: string): Promise<ArrayBuffer | null> {
    const url = remoteStorageUrlForPath(this.baseUrl(), path);
    const hasCredentials = this.profile.username.length > 0 || this.profile.password.length > 0;
    const header: WebDavHeader = hasCredentials ? {
      'Accept': '*/*',
      'Authorization': webDavAuthorizationValue(this.profile.username, this.profile.password),
      'Depth': '',
      'Content-Type': ''
    } : {
      'Accept': '*/*',
      'Depth': '',
      'Content-Type': ''
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      customMethod: 'GET',
      header: header,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: REMOTE_STORAGE_CONNECT_TIMEOUT_MS,
      readTimeout: REMOTE_STORAGE_UPLOAD_TIMEOUT_MS,
      usingCache: false,
      reuseConnections: false
    };
    const startedAt = Date.now();
    logRemoteStorageInfo('request GET(binary) ' + url);
    await waitWebDavSlot();
    try {
      const result = await this.requestWithRedirects(url, options);
      const statusCode = Number(result.response.responseCode);
      if (statusCode < 200 || statusCode >= 300) {
        logRemoteStorageWarn('response GET(binary) ' + url + ' -> ' + statusCode.toString());
        return null;
      }
      logRemoteStorageInfo('response GET(binary) ' + url + ' -> ' + statusCode.toString() + ' in ' +
        (Date.now() - startedAt).toString() + 'ms');
      return result.response.result instanceof ArrayBuffer ? result.response.result : null;
    } catch (error) {
      logRemoteStorageError('request GET(binary) ' + url + ' failed: ' + remoteStorageErrorMessage(error));
      return null;
    } finally {
      releaseWebDavSlot();
    }
  }

  async putBinaryChunk(path: string, data: ArrayBuffer, start: number, end: number): Promise<RemoteStorageResult> {
    const url = remoteStorageUrlForPath(this.baseUrl(), path);
    const hasCredentials = this.profile.username.length > 0 || this.profile.password.length > 0;
    const header: WebDavHeader = hasCredentials ? {
      'Accept': '*/*',
      'Authorization': webDavAuthorizationValue(this.profile.username, this.profile.password),
      'Depth': '',
      'Content-Type': 'application/x-sabredav-partialupdate',
      'Content-Range': 'bytes ' + start.toString() + '-' + end.toString() + '/*'
    } : {
      'Accept': '*/*',
      'Depth': '',
      'Content-Type': 'application/x-sabredav-partialupdate',
      'Content-Range': 'bytes ' + start.toString() + '-' + end.toString() + '/*'
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.PUT,
      customMethod: 'PATCH',
      header: header,
      expectDataType: http.HttpDataType.STRING,
      extraData: data,
      connectTimeout: REMOTE_STORAGE_CONNECT_TIMEOUT_MS,
      readTimeout: REMOTE_STORAGE_UPLOAD_TIMEOUT_MS,
      usingCache: false,
      reuseConnections: false
    };
    await waitWebDavSlot();
    try {
      const result = await this.requestWithRedirects(url, options);
      const statusCode = Number(result.response.responseCode);
      const ok = statusCode >= 200 && statusCode < 300;
      if (!ok) {
        logRemoteStorageWarn('chunk PATCH ' + url + ' -> ' + statusCode.toString());
      }
      return { ok: ok, statusCode: statusCode, message: ok ? '' : webDavStatusMessage(statusCode) };
    } catch (error) {
      return { ok: false, statusCode: 0, message: remoteStorageErrorMessage(error) };
    } finally {
      releaseWebDavSlot();
    }
  }

  // 跟随 301/302/303/307/308（例如外网反向代理把 http 升级到 https），保持方法与请求体。
  private async requestWithRedirects(url: string,
    options: http.HttpRequestOptions): Promise<WebDavRedirectResult> {
    let currentUrl = url;
    for (let hop = 0; hop <= MAX_REDIRECT_HOPS; hop++) {
      const request = http.createHttp();
      let response: http.HttpResponse;
      try {
        response = await request.request(currentUrl, options);
      } finally {
        request.destroy();
      }
      const statusCode = Number(response.responseCode);
      if (!isRedirectStatus(statusCode)) {
        return { response: response, url: currentUrl };
      }
      const nextUrl = resolveRedirectUrl(currentUrl, responseHeaderValue(response.header, 'Location'));
      if (nextUrl.length === 0 || nextUrl === currentUrl) {
        return { response: response, url: currentUrl };
      }
      logRemoteStorageInfo('redirect ' + statusCode.toString() + ' ' + currentUrl + ' -> ' + nextUrl);
      currentUrl = nextUrl;
    }
    throw new Error('Remote connection failed: too many redirects');
  }

  private async ensurePartialUpdateSupport(): Promise<boolean> {
    if (this.partialUpdateChecked) {
      return this.partialUpdateSupported;
    }
    this.partialUpdateChecked = true;
    const probe = await this.send('OPTIONS', '', '0', '', '');
    if (probe.ok) {
      this.partialUpdateSupported = extractDavHeader(probe.headers).toLowerCase().indexOf('sabredav-partialupdate') >= 0;
    }
    logRemoteStorageInfo('server dav header=' + extractDavHeader(probe.headers) +
      ' partialUpdate=' + this.partialUpdateSupported.toString());
    return this.partialUpdateSupported;
  }

  async putBinaryResumable(path: string, data: ArrayBuffer): Promise<RemoteStorageResult> {
    const total = data.byteLength;
    if (total <= REMOTE_STORAGE_RESUMABLE_THRESHOLD || !await this.ensurePartialUpdateSupport()) {
      return this.putBinary(path, data);
    }
    await this.deleteFile(path);
    let offset = 0;
    let lastStatus = 200;
    while (offset < total) {
      const end = Math.min(total, offset + REMOTE_STORAGE_CHUNK_BYTES);
      const slice = data.slice(offset, end);
      let result = await this.putBinaryChunk(path, slice, offset, end - 1);
      if (!result.ok) {
        result = await this.putBinaryChunk(path, slice, offset, end - 1);
      }
      if (!result.ok) {
        // Any server-side refusal: fall back to a plain whole-file PUT for compatibility.
        this.partialUpdateSupported = false;
        return this.putBinary(path, data);
      }
      lastStatus = result.statusCode;
      offset = end;
    }
    return { ok: true, statusCode: lastStatus, message: '' };
  }

  async deleteFile(path: string): Promise<RemoteStorageResult> {
    const response = await this.send('DELETE', path, '', '', '');
    if (response.ok || response.statusCode === 404) {
      return { ok: true, statusCode: response.statusCode, message: '' };
    }
    return { ok: false, statusCode: response.statusCode, message: response.message };
  }

  private async send(customMethod: string, path: string, depth: string, body: string,
    contentType: string): Promise<WebDavRawResponse> {
    const url = remoteStorageUrlForPath(this.baseUrl(), path);
    const hasCredentials = this.profile.username.length > 0 || this.profile.password.length > 0;
    const header: WebDavHeader = hasCredentials ? {
      'Accept': 'application/xml, text/xml, */*',
      'Authorization': webDavAuthorizationValue(this.profile.username, this.profile.password),
      'Depth': depth,
      'Content-Type': contentType
    } : {
      'Accept': 'application/xml, text/xml, */*',
      'Depth': depth,
      'Content-Type': contentType
    };
    const options: http.HttpRequestOptions = {
      method: body.length > 0 ? http.RequestMethod.PUT : http.RequestMethod.GET,
      customMethod: customMethod,
      header: header,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: REMOTE_STORAGE_CONNECT_TIMEOUT_MS,
      readTimeout: body.length > 0 ? REMOTE_STORAGE_UPLOAD_TIMEOUT_MS : REMOTE_STORAGE_READ_TIMEOUT_MS,
      usingCache: false,
      reuseConnections: false
    };
    if (body.length > 0) {
      options.extraData = body;
    }
    const startedAt = Date.now();
    await waitWebDavSlot();
    logRemoteStorageInfo('request ' + customMethod + ' ' + url +
      (depth.length > 0 ? ' depth=' + depth : '') +
      (body.length > 0 ? ' bodyBytes=' + body.length.toString() : ''));
    try {
      const result = await this.requestWithRedirects(url, options);
      const response = result.response;
      const statusCode = Number(response.responseCode);
      const ok = statusCode >= 200 && statusCode < 300;
      const responseText = typeof response.result === 'string' ? response.result : '';
      const elapsed = Date.now() - startedAt;
      if (ok) {
        logRemoteStorageInfo('response ' + customMethod + ' ' + url + ' -> ' + statusCode.toString() +
          ' in ' + elapsed.toString() + 'ms bytes=' + responseText.length.toString());
      } else {
        logRemoteStorageWarn('response ' + customMethod + ' ' + url + ' -> ' + statusCode.toString() +
          ' in ' + elapsed.toString() + 'ms ' + webDavStatusMessage(statusCode));
      }
      return {
        ok: ok,
        statusCode: statusCode,
        message: ok ? '' : webDavStatusMessage(statusCode),
        body: responseText,
        headers: response.header
      };
    } catch (error) {
      const message = remoteStorageErrorMessage(error);
      logRemoteStorageError('request ' + customMethod + ' ' + url + ' failed in ' +
        (Date.now() - startedAt).toString() + 'ms: ' + message);
      return { ok: false, statusCode: 0, message: message, body: '' };
    } finally {
      releaseWebDavSlot();
    }
  }
}

function parentRemotePath(path: string): string {
  const normalized = path.trim().replace(/\\/g, '/').replace(/^\/+|\/+$/g, '');
  const index = normalized.lastIndexOf('/');
  return index <= 0 ? '' : normalized.substring(0, index);
}

interface RemoteStorageErrorInfo {
  code?: number;
  message?: string;
}

function remoteStorageErrorMessage(error: Object): string {
  const info = error as RemoteStorageErrorInfo;
  if (typeof info.code === 'number' && typeof info.message === 'string' && info.message.length > 0) {
    return 'Remote connection failed (' + info.code.toString() + '): ' + info.message;
  }
  if (error instanceof Error) {
    const message = error.message;
    return message.length > 0 ? 'Remote connection failed: ' + message : 'Remote connection failed';
  }
  try {
    const serialized = JSON.stringify(error);
    if (serialized !== undefined && serialized !== null && serialized.length > 0 && serialized !== '{}') {
      return 'Remote connection failed: ' + serialized.substring(0, 200);
    }
  } catch (serializationError) {
  }
  const fallback = String(error);
  return fallback.length > 0 ? 'Remote connection failed: ' + fallback : 'Remote connection failed';
}
