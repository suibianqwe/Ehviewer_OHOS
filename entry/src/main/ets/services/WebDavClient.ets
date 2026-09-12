import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { RemoteStorageProfile } from './RemoteStorageProfiles';
import {
  RemoteStorageListEntry,
  normalizeRemoteStorageBasePath,
  normalizeRemoteStorageUrl,
  parseWebDavMultiStatus,
  remoteStorageUrlForPath,
  webDavStatusMessage
} from './RemoteStorageSupport';

const REMOTE_STORAGE_CONNECT_TIMEOUT_MS: number = 10000;
const REMOTE_STORAGE_READ_TIMEOUT_MS: number = 30000;
const REMOTE_STORAGE_UPLOAD_TIMEOUT_MS: number = 60000;

interface WebDavHeader {
  'Accept'?: string;
  'Authorization'?: string;
  'Depth'?: string;
  'Content-Type'?: string;
}

interface WebDavRawResponse {
  ok: boolean;
  statusCode: number;
  message: string;
  body: string;
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

export function webDavAuthorizationValue(username: string, password: string): string {
  const encoder = util.TextEncoder.create('utf-8');
  const bytes = encoder.encodeInto(username + ':' + password);
  const base64 = new util.Base64Helper().encodeToStringSync(bytes);
  return 'Basic ' + base64;
}

export class WebDavClient {
  private readonly profile: RemoteStorageProfile;

  constructor(profile: RemoteStorageProfile) {
    this.profile = profile;
  }

  baseUrl(): string {
    const url = normalizeRemoteStorageUrl(this.profile.url);
    const base = normalizeRemoteStorageBasePath(this.profile.basePath);
    return base.length > 0 ? url + '/' + base : url;
  }

  async testConnection(): Promise<RemoteStorageResult> {
    const response = await this.send('PROPFIND', '', '0', '', '');
    if (response.ok) {
      return { ok: true, statusCode: response.statusCode, message: '' };
    }
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
    const response = await this.send('MKCOL', path, '', '', '');
    if (response.ok || response.statusCode === 405) {
      return { ok: true, statusCode: response.statusCode, message: '' };
    }
    return { ok: false, statusCode: response.statusCode, message: response.message };
  }

  async putText(path: string, text: string): Promise<RemoteStorageResult> {
    const parent = parentRemotePath(path);
    if (parent.length > 0) {
      const directory = await this.ensureDirectory(parent);
      if (!directory.ok) {
        return directory;
      }
    }
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
      readTimeout: body.length > 0 ? REMOTE_STORAGE_UPLOAD_TIMEOUT_MS : REMOTE_STORAGE_READ_TIMEOUT_MS
    };
    if (body.length > 0) {
      options.extraData = body;
    }
    let request: http.HttpRequest | null = null;
    try {
      request = http.createHttp();
      const response = await request.request(url, options);
      const statusCode = Number(response.responseCode);
      const ok = statusCode >= 200 && statusCode < 300;
      return {
        ok: ok,
        statusCode: statusCode,
        message: ok ? '' : webDavStatusMessage(statusCode),
        body: typeof response.result === 'string' ? response.result : ''
      };
    } catch (error) {
      return { ok: false, statusCode: 0, message: remoteStorageErrorMessage(error), body: '' };
    } finally {
      if (request !== null) {
        request.destroy();
      }
    }
  }
}

function parentRemotePath(path: string): string {
  const normalized = path.trim().replace(/\\/g, '/').replace(/^\/+|\/+$/g, '');
  const index = normalized.lastIndexOf('/');
  return index <= 0 ? '' : normalized.substring(0, index);
}

function remoteStorageErrorMessage(error: Object): string {
  const message = error instanceof Error ? error.message : String(error);
  if (message.length === 0) {
    return 'Remote connection failed';
  }
  return 'Remote connection failed: ' + message;
}
