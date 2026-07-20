import { bundleManager } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import {
  EH_APP_VERSION_CODE,
  EH_APP_VERSION_NAME,
  EH_RELEASE_TAG,
  EH_REPOSITORY_NAME,
  EH_REPOSITORY_URL
} from './EhBuildInfo';
import {
  applyEhNetworkOptions,
  createEhRequestPlan,
  EhRequestPlan,
  ensureEhHostRules,
  recordEhRequestOutcome
} from './EhNetworkConfig';
import { acquireHttpRequest, retireHttpRequest } from './HttpRequestLifecycle';

export interface AppVersionInfo {
  versionName: string;
  versionCode: number;
  releaseTag: string;
}

export interface ReleaseInfo {
  tagName: string;
  name: string;
  body: string;
  htmlUrl: string;
  hapDownloadUrl: string;
}

export interface UpdateCheckResult {
  checked: boolean;
  hasUpdate: boolean;
  current: AppVersionInfo;
  latest: ReleaseInfo | null;
  message: string;
}

interface GitHubReleaseAssetJson {
  name?: string;
  browser_download_url?: string;
}

interface GitHubReleaseJson {
  tag_name?: string;
  name?: string;
  body?: string;
  html_url?: string;
  assets?: GitHubReleaseAssetJson[];
  draft?: boolean;
  prerelease?: boolean;
}

interface GitHubReleaseRequestHeader {
  'Host': string;
  'User-Agent': string;
  'Accept': string;
  'Accept-Language': string;
  'Cache-Control': string;
  'Connection': string;
}

const LATEST_RELEASE_API: string = 'https://api.github.com/repos/' + EH_REPOSITORY_NAME + '/releases/latest';
const REQUEST_TIMEOUT_MS: number = 12000;

class EhUpdateChecker {
  private pending: Promise<UpdateCheckResult> | null = null;

  async checkLatestRelease(): Promise<UpdateCheckResult> {
    if (this.pending !== null) {
      return this.pending;
    }
    this.pending = this.checkLatestReleaseInternal();
    try {
      return await this.pending;
    } finally {
      this.pending = null;
    }
  }

  private async checkLatestReleaseInternal(): Promise<UpdateCheckResult> {
    const current = await getCurrentAppVersion();
    try {
      const latest = await fetchLatestRelease();
      const hasUpdate = isVersionNewer(latest.tagName, current.releaseTag);
      return {
        checked: true,
        hasUpdate: hasUpdate,
        current: current,
        latest: latest,
        message: hasUpdate ? 'New version available' : 'No updates available'
      };
    } catch (error) {
      return {
        checked: false,
        hasUpdate: false,
        current: current,
        latest: null,
        message: 'Check for updates failed: ' + errorMessage(error)
      };
    }
  }
}

export const ehUpdateChecker: EhUpdateChecker = new EhUpdateChecker();

async function getCurrentAppVersion(): Promise<AppVersionInfo> {
  try {
    const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    if (info.versionName.length > 0 && info.versionCode > 0) {
      return {
        versionName: info.versionName,
        versionCode: info.versionCode,
        releaseTag: 'v' + info.versionName
      };
    }
  } catch (error) {
  }
  return {
    versionName: EH_APP_VERSION_NAME,
    versionCode: EH_APP_VERSION_CODE,
    releaseTag: EH_RELEASE_TAG
  };
}

async function fetchLatestRelease(): Promise<ReleaseInfo> {
  const request = acquireHttpRequest();
  const plan = createEhRequestPlan(LATEST_RELEASE_API);
  const startedAt = Date.now();
  let outcomeRecorded = false;
  try {
    await ensureEhHostRules();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: buildGitHubReleaseHeader(plan),
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: REQUEST_TIMEOUT_MS,
      readTimeout: REQUEST_TIMEOUT_MS
    };
    applyEhNetworkOptions(options, plan);
    const response = await request.request(plan.url, options);
    const statusCode = Number(response.responseCode);
    recordEhRequestOutcome(plan, statusCode >= 200 && statusCode < 500, Date.now() - startedAt);
    outcomeRecorded = true;
    if (statusCode < 200 || statusCode >= 300) {
      throw new Error('HTTP ' + statusCode.toString());
    }
    const release = parseGitHubRelease(response.result as string);
    if (release === null) {
      throw new Error('Unable to parse GitHub release');
    }
    return release;
  } catch (error) {
    if (!outcomeRecorded) {
      recordEhRequestOutcome(plan, false, Date.now() - startedAt);
    }
    throw new Error(errorMessage(error as Object));
  } finally {
    retireHttpRequest(request);
  }
}

function buildGitHubReleaseHeader(plan: EhRequestPlan): GitHubReleaseRequestHeader {
  return {
    'Host': plan.host,
    'User-Agent': 'EhViewerHarmony/' + EH_APP_VERSION_NAME,
    'Accept': 'application/vnd.github+json',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Cache-Control': 'no-cache',
    'Connection': plan.fronted ? 'close' : 'keep-alive'
  };
}

function parseGitHubRelease(body: string): ReleaseInfo | null {
  try {
    const parsed = JSON.parse(body) as GitHubReleaseJson;
    const tagName = typeof parsed.tag_name === 'string' ? parsed.tag_name.trim() : '';
    if (tagName.length === 0) {
      return null;
    }
    const htmlUrl = typeof parsed.html_url === 'string' && parsed.html_url.length > 0 ?
      parsed.html_url : EH_REPOSITORY_URL + '/releases/tag/' + tagName;
    const hapDownloadUrl = findHapDownloadUrl(parsed.assets, htmlUrl);
    return {
      tagName: tagName,
      name: typeof parsed.name === 'string' && parsed.name.length > 0 ? parsed.name : tagName,
      body: typeof parsed.body === 'string' ? parsed.body.trim() : '',
      htmlUrl: htmlUrl,
      hapDownloadUrl: hapDownloadUrl
    };
  } catch (error) {
    return null;
  }
}

function findHapDownloadUrl(assets: GitHubReleaseAssetJson[] | undefined, fallbackUrl: string): string {
  if (assets === undefined || !Array.isArray(assets)) {
    return fallbackUrl;
  }
  for (let i = 0; i < assets.length; i++) {
    const asset = assets[i];
    const name = typeof asset.name === 'string' ? asset.name.toLowerCase() : '';
    const downloadUrl = typeof asset.browser_download_url === 'string' ? asset.browser_download_url : '';
    if (name.endsWith('.hap') && downloadUrl.length > 0) {
      return downloadUrl;
    }
  }
  return fallbackUrl;
}

function isVersionNewer(latestTag: string, currentTag: string): boolean {
  const latest = parseVersionParts(latestTag);
  const current = parseVersionParts(currentTag);
  const maxLength = Math.max(latest.length, current.length);
  for (let i = 0; i < maxLength; i++) {
    const latestPart = i < latest.length ? latest[i] : 0;
    const currentPart = i < current.length ? current[i] : 0;
    if (latestPart > currentPart) {
      return true;
    }
    if (latestPart < currentPart) {
      return false;
    }
  }
  return false;
}

function parseVersionParts(tag: string): number[] {
  const match = /(\d+(?:\.\d+)*)/.exec(tag);
  if (match === null) {
    return [0];
  }
  const rawParts = match[1].split('.');
  const parts: number[] = [];
  for (let i = 0; i < rawParts.length; i++) {
    const value = Number.parseInt(rawParts[i]);
    parts.push(Number.isNaN(value) ? 0 : value);
  }
  return parts.length === 0 ? [0] : parts;
}

function errorMessage(error: Object): string {
  let message = String(error);
  if (message.indexOf('Error: ') === 0) {
    message = message.substring(7);
  }
  return message.length > 0 ? message : 'Network request failed';
}
