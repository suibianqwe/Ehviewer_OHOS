import { bundleManager } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ReleaseInfo, parseGitHubRelease, parseGitHubReleasePage, findGitHubHapLink } from './GitHubReleaseParser';
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
import { acquireHttpRequest, markHttpRequestVolatile, retireHttpRequest } from './HttpRequestLifecycle';

export { ReleaseInfo } from './GitHubReleaseParser';

export interface AppVersionInfo {
  versionName: string;
  versionCode: number;
  releaseTag: string;
}

export interface UpdateCheckResult {
  checked: boolean;
  hasUpdate: boolean;
  current: AppVersionInfo;
  latest: ReleaseInfo | null;
  message: string;
}

interface GitHubReleaseRequestHeader {
  'Host': string;
  'User-Agent': string;
  'Accept': string;
  'Accept-Language': string;
  'Cache-Control': string;
}

const LATEST_RELEASE_API: string = 'https://api.github.com/repos/' + EH_REPOSITORY_NAME + '/releases/latest';
const LATEST_RELEASE_PAGE: string = EH_REPOSITORY_URL + '/releases/latest';
const REQUEST_TIMEOUT_MS: number = 12000;
const SUCCESS_CACHE_MS: number = 60000;
const API_RETRY_DELAY_MS: number = 60000;
const LOG_DOMAIN: number = 0xD004001;
const LOG_TAG: string = 'EhUpdateChecker';
let apiRetryAt: number = 0;
let cachedRelease: ReleaseInfo | null = null;
let cachedReleaseUntil: number = 0;

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
  if (cachedRelease !== null && Date.now() < cachedReleaseUntil) {
    return cachedRelease;
  }
  let apiFailure = 'GitHub API cooling down';
  if (Date.now() >= apiRetryAt) {
    try {
      const response = await fetchReleaseResponse(LATEST_RELEASE_API, 'application/vnd.github+json');
      const status = Number(response.responseCode);
      if (status === 403 || status === 429) {
        apiRetryAt = githubRetryAt(response.header, Date.now());
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'GitHub API HTTP %{public}d, remaining=%{public}s; using release page',
          status, githubHeaderValue(response.header, 'x-ratelimit-remaining'));
      }
      requireSuccess(response);
      const release = parseGitHubRelease(response.result as string);
      if (release === null) {
        throw new Error('Unable to parse GitHub release');
      }
      return cacheRelease(release);
    } catch (error) {
      apiFailure = errorMessage(error);
      apiRetryAt = Math.max(apiRetryAt, Date.now() + API_RETRY_DELAY_MS);
    }
  }
  try {
    const response = await fetchReleaseResponse(LATEST_RELEASE_PAGE, 'text/html');
    requireSuccess(response);
    const release = parseGitHubReleasePage(response.result as string);
    if (release === null) {
      throw new Error('Unable to parse GitHub release page');
    }
    if (release.hapDownloadUrl === release.htmlUrl) {
      // Assets are lazy-loaded on GitHub. A missing asset list must not discard valid version information.
      try {
        const assets = await fetchReleaseResponse(EH_REPOSITORY_URL + '/releases/expanded_assets/' +
          encodeURIComponent(release.tagName), 'text/html');
        requireSuccess(assets);
        release.hapDownloadUrl = findGitHubHapLink(assets.result as string, release.tagName, release.htmlUrl);
      } catch (_error) {
        // Keep the verified official release page as the safe download destination.
      }
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Release page fallback succeeded: %{public}s', release.tagName);
    return cacheRelease(release);
  } catch (error) {
    throw new Error('GitHub API: ' + apiFailure + '; release page: ' + errorMessage(error));
  }
}

function cacheRelease(release: ReleaseInfo): ReleaseInfo {
  cachedRelease = release;
  cachedReleaseUntil = Date.now() + SUCCESS_CACHE_MS;
  return release;
}

function githubHeaderValue(header: Object, name: string): string {
  try {
    const values = (typeof header === 'string' ? JSON.parse(header) : header) as Record<string, string>;
    const keys = Object.keys(values);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === name) {
        return String(values[keys[i]]);
      }
    }
  } catch (_error) {
  }
  return '';
}

function githubRetryAt(header: Object, now: number): number {
  let retryAt = now + API_RETRY_DELAY_MS;
  const retryAfter = githubHeaderValue(header, 'retry-after');
  if (retryAfter.length > 0) {
    const seconds = Number(retryAfter);
    const time = Number.isFinite(seconds) ? now + seconds * 1000 : Date.parse(retryAfter);
    if (Number.isFinite(time)) {
      retryAt = Math.max(retryAt, time);
    }
  }
  if (githubHeaderValue(header, 'x-ratelimit-remaining') === '0') {
    const reset = Number(githubHeaderValue(header, 'x-ratelimit-reset')) * 1000;
    if (Number.isFinite(reset)) {
      retryAt = Math.max(retryAt, reset);
    }
  }
  return retryAt;
}

function requireSuccess(response: http.HttpResponse): void {
  const status = Number(response.responseCode);
  if (status < 200 || status >= 300) {
    throw new Error('HTTP ' + status.toString());
  }
}

async function fetchReleaseResponse(url: string, accept: string): Promise<http.HttpResponse> {
  await ensureEhHostRules();
  const request = acquireHttpRequest();
  const plan = createEhRequestPlan(url);
  const startedAt = Date.now();
  let outcomeRecorded = false;
  try {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: buildGitHubReleaseHeader(plan, accept),
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: REQUEST_TIMEOUT_MS,
      readTimeout: REQUEST_TIMEOUT_MS,
      maxLimit: 1024 * 1024
    };
    applyEhNetworkOptions(options, plan);
    if (plan.fronted) {
      markHttpRequestVolatile(request);
    }
    const response = await request.request(plan.url, options);
    const statusCode = Number(response.responseCode);
    recordEhRequestOutcome(plan, statusCode >= 200 && statusCode < 500, Date.now() - startedAt);
    outcomeRecorded = true;
    return response;
  } catch (error) {
    if (!outcomeRecorded) {
      recordEhRequestOutcome(plan, false, Date.now() - startedAt);
    }
    throw new Error(errorMessage(error as Object));
  } finally {
    retireHttpRequest(request);
  }
}

function buildGitHubReleaseHeader(plan: EhRequestPlan, accept: string): GitHubReleaseRequestHeader {
  return {
    'Host': plan.host,
    'User-Agent': 'EhViewerHarmony/' + EH_APP_VERSION_NAME,
    'Accept': accept,
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Cache-Control': 'no-cache'
  };
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
