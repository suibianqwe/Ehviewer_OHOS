import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  ArchiverInfo,
  ArchiverOption,
  GalleryDetail,
  GalleryInfo,
  GalleryPage,
  GallerySite,
  HathArchiveList,
  TopListDetail
} from '../model/GalleryModels';
import { ehCookieStore } from './EhCookieStore';
import { EhUrl, FavListUrlBuilder, ListMode, ListUrlBuilder } from './EhUrl';
import { GalleryDetailParseResult, parseGalleryDetail } from './GalleryDetailParser';
import { mergeGalleryApiMetadata } from './GalleryApiParser';
import { GalleryListParseResult, parseGalleryList } from './GalleryListParser';
import { GalleryPageApiParseResult, parseGalleryPageApi } from './GalleryPageApiParser';
import { GalleryPageParseResult, parseGalleryPage } from './GalleryPageParser';
import { GalleryPageUrlInfo, parseGalleryPageUrl } from './GalleryPageUrlParser';
import {
  parseArchiverContinueUrl,
  parseArchiverDownloadUrl,
  parseArchiverInfo,
  parseHathArchiveList
} from './ArchiveParser';
import { ehSpiderInfoStore } from './EhSpiderInfoStore';
import {
  applyEhNetworkOptions,
  createEhRequestPlan,
  EhRequestPlan,
  ensureEhHostRules,
  recordEhRequestOutcome
} from './EhNetworkConfig';
import { TopListParseResult, parseTopList } from './TopListParser';

export interface EhHttpResponse {
  statusCode: number;
  body: string;
  cookies: string;
  headers?: Record<string, Object>;
}

export interface EhTextRequestOptions {
  includeUConfig?: boolean;
}

interface CachedHttpResponse {
  key: string;
  response: EhHttpResponse;
  expiresAt: number;
}

interface PendingHttpResponse {
  key: string;
  promise: Promise<EhHttpResponse>;
}

interface PendingGalleryPageResponse {
  key: string;
  promise: Promise<GalleryPageLoadResult>;
}

interface TextSlotWaiter {
  resume: () => void;
}

const SHARED_RESPONSE_CACHE: CachedHttpResponse[] = [];
const SHARED_PENDING_RESPONSES: PendingHttpResponse[] = [];
const SHARED_PENDING_PAGE_LOADS: PendingGalleryPageResponse[] = [];
const SHARED_SHOW_KEYS: ShowKeyEntry[] = [];
const WAITING_TEXT_SLOTS: TextSlotWaiter[] = [];
const MAX_ACTIVE_TEXT_REQUESTS: number = 6;
const TEXT_CONNECT_TIMEOUT_MS: number = 15000;
const TEXT_READ_TIMEOUT_MS: number = 15000;
const TEXT_DEADLINE_TIMEOUT_MS: number = 26000;
const API_TIMEOUT_MS: number = 10000;
const API_DEADLINE_TIMEOUT_MS: number = 18000;
const TEXT_RETRY_DELAYS_MS: number[] = [250, 750];
const CHROME_USER_AGENT: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36';
const CHROME_ACCEPT: string = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8';
const CHROME_ACCEPT_LANGUAGE: string = 'zh-CN,zh;q=0.9,en;q=0.8';
let activeTextRequests: number = 0;

interface ShowKeyEntry {
  key: string;
  showKey: string;
}

interface NetworkDiagnosticTarget {
  label: string;
  url: string;
  referer: string;
}

export interface GalleryListLoadResult {
  ok: boolean;
  url: string;
  statusCode: number;
  message: string;
  pages: number;
  nextPage: number;
  nextUrl: string;
  resultCount: string;
  galleries: GalleryInfo[];
}

export interface GalleryDetailLoadResult {
  ok: boolean;
  url: string;
  statusCode: number;
  message: string;
  detail: GalleryDetail | null;
}

export interface GalleryPageLoadResult {
  ok: boolean;
  url: string;
  statusCode: number;
  message: string;
  page: GalleryPage | null;
}

export interface TopListLoadResult {
  ok: boolean;
  url: string;
  statusCode: number;
  message: string;
  detail: TopListDetail | null;
}

export interface SignInResult {
  ok: boolean;
  statusCode: number;
  message: string;
  displayName: string;
}

export interface ToggleFavoriteResult {
  ok: boolean;
  statusCode: number;
  message: string;
  nowFavorited: boolean;
}

export interface RateGalleryResult {
  ok: boolean;
  statusCode: number;
  message: string;
  rating: number;
  ratingCount: number;
}

export interface HathArchiveListLoadResult {
  ok: boolean;
  url: string;
  statusCode: number;
  message: string;
  list: HathArchiveList | null;
}

export interface HathArchiveSubmitResult {
  ok: boolean;
  statusCode: number;
  message: string;
}

export interface ArchiverLoadResult {
  ok: boolean;
  url: string;
  statusCode: number;
  message: string;
  info: ArchiverInfo | null;
}

export interface ArchiverDownloadResult {
  ok: boolean;
  statusCode: number;
  message: string;
  downloadUrl: string;
}

export interface NetworkDiagnosticResult {
  label: string;
  url: string;
  ok: boolean;
  statusCode: number;
  elapsedMs: number;
  message: string;
}

export class EhHttpClient {
  async getText(url: string, referer: string = EhUrl.getReferer(), cacheTtlMs: number = 45000,
    options?: EhTextRequestOptions): Promise<EhHttpResponse> {
    const includeUConfig = options?.includeUConfig !== false;
    const cookieHeader = ehCookieStore.getCookieHeaderForUrl(url, {
      includeContentWarning: true,
      includeUConfig: includeUConfig
    });
    const cacheKey = buildCacheKey('GET', url, referer, cookieHeader);
    if (cacheTtlMs > 0) {
      const cached = this.getCachedResponse(cacheKey);
      if (cached !== null) {
        return cached;
      }

      const pending = this.getPendingResponse(cacheKey);
      if (pending !== null) {
        return pending;
      }
    }

    const promise = this.getTextNetwork(url, referer, cookieHeader, cacheTtlMs)
      .then((response: EhHttpResponse) => {
        if (cacheTtlMs > 0 && response.statusCode >= 200 && response.statusCode < 300) {
          this.putCachedResponse(cacheKey, response, cacheTtlMs);
        }
        return response;
      });

    if (cacheTtlMs > 0) {
      this.putPendingResponse(cacheKey, promise);
    }

    try {
      return await promise;
    } finally {
      this.removePendingResponse(cacheKey);
    }
  }

  private async getTextNetwork(url: string, referer: string, cookieHeader: string,
    cacheTtlMs: number): Promise<EhHttpResponse> {
    return requestTextWithRetry((): Promise<EhHttpResponse> => {
      return this.getTextOnce(url, referer, cookieHeader, cacheTtlMs);
    }, 3);
  }

  private async getTextOnce(url: string, referer: string, cookieHeader: string,
    cacheTtlMs: number): Promise<EhHttpResponse> {
    const request = http.createHttp();
    let plan: EhRequestPlan | null = null;
    const startedAt = Date.now();
    let outcomeRecorded = false;
    await acquireTextSlot();
    try {
      plan = createEhRequestPlan(url);
      const header = buildRequestHeader(plan, referer, cookieHeader, cacheTtlMs);
      await ensureEhHostRules();
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: TEXT_CONNECT_TIMEOUT_MS,
        readTimeout: TEXT_READ_TIMEOUT_MS
      };
      applyEhNetworkOptions(options, plan);
      const response = await requestWithDeadline(request, plan.url, options, TEXT_DEADLINE_TIMEOUT_MS);
      const statusCode = Number(response.responseCode);
      recordEhRequestOutcome(plan, statusCode >= 200 && statusCode < 500, Date.now() - startedAt);
      outcomeRecorded = true;

      ehCookieStore.absorbSetCookieHeader(response.cookies);
      syncSetCookiesToWebView(url, response.cookies);
      return {
        statusCode: statusCode,
        body: response.result as string,
        cookies: response.cookies
      };
    } catch (error) {
      if (plan !== null && !outcomeRecorded) {
        recordEhRequestOutcome(plan, false, Date.now() - startedAt);
      }
      throw new Error(networkErrorMessage(error));
    } finally {
      try {
        request.destroy();
      } catch (error) {
      }
      releaseTextSlot();
    }
  }

  private getCachedResponse(key: string): EhHttpResponse | null {
    const now = Date.now();
    for (let i = 0; i < SHARED_RESPONSE_CACHE.length; i++) {
      const item = SHARED_RESPONSE_CACHE[i];
      if (item.key === key) {
        if (item.expiresAt <= now) {
          SHARED_RESPONSE_CACHE.splice(i, 1);
          return null;
        }
        SHARED_RESPONSE_CACHE.splice(i, 1);
        SHARED_RESPONSE_CACHE.unshift(item);
        return cloneResponse(item.response);
      }
    }
    return null;
  }

  private putCachedResponse(key: string, response: EhHttpResponse, ttlMs: number): void {
    for (let i = 0; i < SHARED_RESPONSE_CACHE.length; i++) {
      if (SHARED_RESPONSE_CACHE[i].key === key) {
        SHARED_RESPONSE_CACHE.splice(i, 1);
        break;
      }
    }
    SHARED_RESPONSE_CACHE.unshift({
      key: key,
      response: cloneResponse(response),
      expiresAt: Date.now() + ttlMs
    });

    while (SHARED_RESPONSE_CACHE.length > 96) {
      SHARED_RESPONSE_CACHE.pop();
    }
  }

  private getPendingResponse(key: string): Promise<EhHttpResponse> | null {
    for (let i = 0; i < SHARED_PENDING_RESPONSES.length; i++) {
      if (SHARED_PENDING_RESPONSES[i].key === key) {
        return SHARED_PENDING_RESPONSES[i].promise.then((response: EhHttpResponse) => cloneResponse(response));
      }
    }
    return null;
  }

  private putPendingResponse(key: string, promise: Promise<EhHttpResponse>): void {
    this.removePendingResponse(key);
    SHARED_PENDING_RESPONSES.push({ key: key, promise: promise });
  }

  private removePendingResponse(key: string): void {
    for (let i = SHARED_PENDING_RESPONSES.length - 1; i >= 0; i--) {
      if (SHARED_PENDING_RESPONSES[i].key === key) {
        SHARED_PENDING_RESPONSES.splice(i, 1);
      }
    }
  }

  async postForm(url: string, body: string, referer: string, origin: string): Promise<EhHttpResponse> {
    return requestTextWithRetry((): Promise<EhHttpResponse> => {
      return this.postFormOnce(url, body, referer, origin, ehCookieStore.getCookieHeaderForUrl(url));
    }, 2);
  }

  private async postFormOnce(url: string, body: string, referer: string, origin: string,
    cookieHeader: string): Promise<EhHttpResponse> {
    const request = http.createHttp();
    let plan: EhRequestPlan | null = null;
    const startedAt = Date.now();
    let outcomeRecorded = false;
    await acquireTextSlot();
    try {
      plan = createEhRequestPlan(url);
      const header = buildPostRequestHeader(plan, referer, origin, cookieHeader);
      await ensureEhHostRules();
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: header,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: TEXT_CONNECT_TIMEOUT_MS,
        readTimeout: TEXT_READ_TIMEOUT_MS
      };
      applyEhNetworkOptions(options, plan);
      const response = await requestWithDeadline(request, plan.url, options, TEXT_DEADLINE_TIMEOUT_MS);
      const statusCode = Number(response.responseCode);
      recordEhRequestOutcome(plan, statusCode >= 200 && statusCode < 500, Date.now() - startedAt);
      outcomeRecorded = true;

      ehCookieStore.absorbSetCookieHeader(response.cookies);
      syncSetCookiesToWebView(url, response.cookies);
      return {
        statusCode: statusCode,
        body: response.result as string,
        cookies: response.cookies
      };
    } catch (error) {
      if (plan !== null && !outcomeRecorded) {
        recordEhRequestOutcome(plan, false, Date.now() - startedAt);
      }
      throw new Error(networkErrorMessage(error));
    } finally {
      try {
        request.destroy();
      } catch (error) {
      }
      releaseTextSlot();
    }
  }

  async postJson(url: string, body: string, referer: string = '', origin: string = ''): Promise<EhHttpResponse> {
    return requestTextWithRetry((): Promise<EhHttpResponse> => {
      return this.postJsonOnce(url, body, referer, origin);
    }, 3);
  }

  private async postJsonOnce(url: string, body: string, referer: string = '',
    origin: string = ''): Promise<EhHttpResponse> {
    const request = http.createHttp();
    let plan: EhRequestPlan | null = null;
    const startedAt = Date.now();
    let outcomeRecorded = false;
    await acquireTextSlot();
    try {
      const cookieHeader = ehCookieStore.getCookieHeaderForUrl(url);
      plan = createEhRequestPlan(url);
      const header = buildJsonRequestHeader(plan, referer, origin, cookieHeader);
      await ensureEhHostRules();
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: header,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: API_TIMEOUT_MS,
        readTimeout: API_TIMEOUT_MS
      };
      applyEhNetworkOptions(options, plan);
      const response = await requestWithDeadline(request, plan.url, options, API_DEADLINE_TIMEOUT_MS);
      const statusCode = Number(response.responseCode);
      recordEhRequestOutcome(plan, statusCode >= 200 && statusCode < 500, Date.now() - startedAt);
      outcomeRecorded = true;

      ehCookieStore.absorbSetCookieHeader(response.cookies);
      syncSetCookiesToWebView(url, response.cookies);
      return {
        statusCode: statusCode,
        body: response.result as string,
        cookies: response.cookies
      };
    } catch (error) {
      if (plan !== null && !outcomeRecorded) {
        recordEhRequestOutcome(plan, false, Date.now() - startedAt);
      }
      throw new Error(networkErrorMessage(error));
    } finally {
      try {
        request.destroy();
      } catch (error) {
      }
      releaseTextSlot();
    }
  }

  async runNetworkDiagnostics(): Promise<NetworkDiagnosticResult[]> {
    const targets: NetworkDiagnosticTarget[] = [
      { label: 'E', url: EhUrl.HOST_E, referer: EhUrl.HOST_E },
      { label: 'EX', url: EhUrl.HOST_EX, referer: EhUrl.HOST_EX },
      { label: 'Forums', url: EhUrl.FORUM_ORIGIN + '/', referer: EhUrl.FORUM_ORIGIN + '/' },
      { label: 'Repo', url: 'https://repo.e-hentai.org/', referer: EhUrl.HOST_E + '/' }
    ];
    const results: NetworkDiagnosticResult[] = [];
    for (let i = 0; i < targets.length; i++) {
      results.push(await this.runNetworkDiagnosticTarget(targets[i]));
    }
    return results;
  }

  private async runNetworkDiagnosticTarget(target: NetworkDiagnosticTarget): Promise<NetworkDiagnosticResult> {
    const startedAt = Date.now();
    try {
      const response = await this.getText(target.url, target.referer, 0);
      const elapsedMs = Date.now() - startedAt;
      const ok = response.statusCode >= 200 && response.statusCode < 400;
      return {
        label: target.label,
        url: target.url,
        ok: ok,
        statusCode: response.statusCode,
        elapsedMs: elapsedMs,
        message: ok ? 'OK' : httpStatusMessage(response.statusCode, response.body)
      };
    } catch (error) {
      return {
        label: target.label,
        url: target.url,
        ok: false,
        statusCode: 0,
        elapsedMs: Date.now() - startedAt,
        message: networkErrorMessage(error)
      };
    }
  }

  async signIn(username: string, password: string): Promise<SignInResult> {
    const form = buildFormBody([
      { key: 'UserName', value: username },
      { key: 'PassWord', value: password },
      { key: 'submit', value: 'Log me in' },
      { key: 'CookieDate', value: '1' },
      { key: 'temporary_https', value: 'off' }
    ]);

    try {
      ehCookieStore.clear();
      const response = await this.postFormOnce(EhUrl.API_SIGN_IN, form, EhUrl.SIGN_IN_REFERER, EhUrl.FORUM_ORIGIN,
        ehCookieStore.getStoredCookieHeader());
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          ok: false,
          statusCode: response.statusCode,
          message: httpStatusMessage(response.statusCode, response.body),
          displayName: ''
        };
      }

      const parsed = parseSignIn(response.body);
      const hasSession = ehCookieStore.hasCookies();
      return {
        ok: parsed.ok && hasSession,
        statusCode: response.statusCode,
        message: parsed.ok ? (hasSession ? 'Signed in as ' + parsed.displayName : 'Login page parsed but no Cookie returned') :
          parsed.message,
        displayName: parsed.displayName
      };
    } catch (error) {
      return {
        ok: false,
        statusCode: 0,
        message: networkErrorMessage(error),
        displayName: ''
      };
    }
  }

  async toggleFavorite(gid: number, token: string, isFavorited: boolean,
    site: GallerySite = GallerySite.E): Promise<ToggleFavoriteResult> {
    const favcat = isFavorited ? 'favdel' : '0';
    const form = buildFormBody([
      { key: 'favcat', value: favcat },
      { key: 'favnote', value: '' },
      { key: 'submit', value: 'Apply Changes' },
      { key: 'update', value: '1' }
    ]);
    const url = EhUrl.getAddFavoritesUrl(gid, token, site);
    const referer = EhUrl.getGalleryDetailUrl(gid, token, 0, false, site);
    const origin = EhUrl.getHost(site);
    try {
      const response = await this.postForm(url, form, referer, origin);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          ok: false,
          statusCode: response.statusCode,
          message: httpStatusMessage(response.statusCode, response.body),
          nowFavorited: isFavorited
        };
      }
      return {
        ok: true,
        statusCode: response.statusCode,
        message: isFavorited ? 'Removed from favorites' : 'Added to favorites',
        nowFavorited: !isFavorited
      };
    } catch (error) {
      return {
        ok: false,
        statusCode: 0,
        message: networkErrorMessage(error),
        nowFavorited: isFavorited
      };
    }
  }

  async rateGallery(gid: number, token: string, apiUid: number, apiKey: string, starRating: number,
    site: GallerySite = GallerySite.E): Promise<RateGalleryResult> {
    const clampedRating = Math.max(1, Math.min(5, starRating));
    const apiRating = Math.ceil(clampedRating * 2);
    const payload = JSON.stringify({
      method: 'rategallery',
      apiuid: apiUid,
      apikey: apiKey,
      gid: gid,
      token: token,
      rating: apiRating
    });
    const url = EhUrl.getApiUrl(site);
    const referer = EhUrl.getGalleryDetailUrl(gid, token, 0, false, site);
    const origin = EhUrl.getHost(site);
    try {
      const response = await this.postJson(url, payload, referer, origin);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          ok: false,
          statusCode: response.statusCode,
          message: httpStatusMessage(response.statusCode, response.body),
          rating: clampedRating,
          ratingCount: 0
        };
      }
      const parsed = parseRateGalleryResponse(response.body, clampedRating);
      return {
        ok: true,
        statusCode: response.statusCode,
        message: 'Rating submitted: ' + clampedRating.toString() + ' stars',
        rating: parsed.rating,
        ratingCount: parsed.ratingCount
      };
    } catch (error) {
      return {
        ok: false,
        statusCode: 0,
        message: networkErrorMessage(error),
        rating: clampedRating,
        ratingCount: 0
      };
    }
  }

  async loadGalleryList(builder: ListUrlBuilder, site: GallerySite = GallerySite.E,
    includeUConfig: boolean = true): Promise<GalleryListLoadResult> {
    if (builder.mode === ListMode.ImageSearch) {
      return this.loadImageSearchList(builder, site);
    }
    const url = builder.build(site);
    return this.loadGalleryListUrl(url, site, includeUConfig);
  }

  async loadFavoritesList(builder: FavListUrlBuilder, site: GallerySite = GallerySite.E): Promise<GalleryListLoadResult> {
    const url = builder.build(site);
    return this.loadGalleryListUrl(url, site);
  }

  async loadGalleryListUrl(url: string, site: GallerySite = GallerySite.E,
    includeUConfig: boolean = true): Promise<GalleryListLoadResult> {
    try {
      const response = await this.getText(url, EhUrl.getReferer(site), includeUConfig ? 60000 : 0,
        { includeUConfig: includeUConfig });
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          ok: false,
          url: url,
          statusCode: response.statusCode,
          message: httpStatusMessage(response.statusCode, response.body),
          pages: 0,
          nextPage: -1,
          nextUrl: '',
          resultCount: '',
          galleries: []
        };
      }

      const parsed: GalleryListParseResult = parseGalleryList(response.body);
      await this.fillGalleryListByApi(parsed.galleries, url, site);
      const parseMessage = parsed.warning.length > 0 ? parsed.warning + '; ' + galleryListBodyDiagnostic(response.body) :
        'Parsed ' + parsed.galleries.length.toString() + ' galleries';
      return {
        ok: parsed.galleries.length > 0,
        url: url,
        statusCode: response.statusCode,
        message: parseMessage,
        pages: parsed.pages,
        nextPage: parsed.nextPage,
        nextUrl: parsed.nextUrl,
        resultCount: parsed.resultCount,
        galleries: parsed.galleries
      };
    } catch (error) {
      return {
        ok: false,
        url: url,
        statusCode: 0,
        message: networkErrorMessage(error),
        pages: 0,
        nextPage: -1,
        nextUrl: '',
        resultCount: '',
        galleries: []
      };
    }
  }

  private async fillGalleryListByApi(galleries: GalleryInfo[], referer: string, site: GallerySite): Promise<void> {
    if (galleries.length === 0) {
      return;
    }
    const maxBatchSize = 25;
    for (let start = 0; start < galleries.length; start += maxBatchSize) {
      const batch = galleries.slice(start, Math.min(start + maxBatchSize, galleries.length));
      const gidlist: (number | string)[][] = [];
      for (let i = 0; i < batch.length; i++) {
        gidlist.push([batch[i].gid, batch[i].token]);
      }
      const payload = JSON.stringify({
        method: 'gdata',
        gidlist: gidlist,
        namespace: 1
      });
      try {
        const response = await this.postJson(EhUrl.getApiUrl(site), payload, referer, EhUrl.getReferer(site));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          mergeGalleryApiMetadata(response.body, galleries);
        }
      } catch (error) {
        return;
      }
    }
  }

  async loadGalleryDetail(gid: number, token: string, pageIndex: number = 0,
    site: GallerySite = GallerySite.E, referer: string = EhUrl.getReferer(site)): Promise<GalleryDetailLoadResult> {
    const url = EhUrl.getGalleryDetailUrl(gid, token, pageIndex, false, site);
    try {
      const response = await this.getText(url, referer, 120000);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          ok: false,
          url: url,
          statusCode: response.statusCode,
          message: httpStatusMessage(response.statusCode, response.body),
          detail: null
        };
      }

      const parsed: GalleryDetailParseResult = parseGalleryDetail(response.body);
      return {
        ok: parsed.detail !== null,
        url: url,
        statusCode: response.statusCode,
        message: parsed.warning.length > 0 ? parsed.warning : 'Parsed gallery detail',
        detail: parsed.detail
      };
    } catch (error) {
      return {
        ok: false,
        url: url,
        statusCode: 0,
        message: networkErrorMessage(error),
        detail: null
      };
    }
  }

  async loadGalleryPage(pageUrl: string, site: GallerySite = GallerySite.E,
    referer: string = EhUrl.getReferer(site)): Promise<GalleryPageLoadResult> {
    return this.loadGalleryPageFast(pageUrl, site, referer, true);
  }

  async loadHathArchiveList(gid: number, token: string, archiveUrl: string,
    site: GallerySite = GallerySite.E): Promise<HathArchiveListLoadResult> {
    const url = archiveUrl.length > 0 ? archiveUrl : EhUrl.getDownloadArchiveUrl(gid, token, '', site);
    try {
      const response = await this.getText(url, EhUrl.getGalleryDetailUrl(gid, token, 0, false, site), 0);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          ok: false,
          url: url,
          statusCode: response.statusCode,
          message: httpStatusMessage(response.statusCode, response.body),
          list: null
        };
      }
      const list = parseHathArchiveList(response.body);
      return {
        ok: list.options.length > 0,
        url: url,
        statusCode: response.statusCode,
        message: list.options.length > 0 ? 'Parsed H@H archive list' : 'No H@H archives',
        list: list
      };
    } catch (error) {
      return {
        ok: false,
        url: url,
        statusCode: 0,
        message: networkErrorMessage(error),
        list: null
      };
    }
  }

  async submitHathArchive(gid: number, token: string, formParamOr: string, resolution: string,
    site: GallerySite = GallerySite.E): Promise<HathArchiveSubmitResult> {
    if (resolution.length === 0) {
      return { ok: false, statusCode: 0, message: 'Invalid H@H resolution' };
    }
    const url = EhUrl.getDownloadArchiveUrl(gid, token, formParamOr, site);
    const referer = EhUrl.getGalleryDetailUrl(gid, token, 0, false, site);
    const origin = EhUrl.getReferer(site);
    try {
      const response = await this.postForm(url, buildFormBody([{ key: 'hathdl_xres', value: resolution }]), referer, origin);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return { ok: false, statusCode: response.statusCode, message: httpStatusMessage(response.statusCode, response.body) };
      }
      if (/No H@H client|H@H client/i.test(response.body) && /not|no|need|requires/i.test(response.body)) {
        return { ok: false, statusCode: response.statusCode, message: 'No H@H client available' };
      }
      return { ok: true, statusCode: response.statusCode, message: 'H@H download request submitted' };
    } catch (error) {
      return { ok: false, statusCode: 0, message: networkErrorMessage(error) };
    }
  }

  async loadArchiver(gid: number, token: string, archiveUrl: string,
    site: GallerySite = GallerySite.E): Promise<ArchiverLoadResult> {
    const url = archiveUrl.length > 0 ? archiveUrl : EhUrl.getDownloadArchiveUrl(gid, token, '', site);
    try {
      const response = await this.getText(url, EhUrl.getGalleryDetailUrl(gid, token, 0, false, site), 0);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          ok: false,
          url: url,
          statusCode: response.statusCode,
          message: httpStatusMessage(response.statusCode, response.body),
          info: null
        };
      }
      const info = parseArchiverInfo(response.body);
      return {
        ok: info.options.length > 0,
        url: url,
        statusCode: response.statusCode,
        message: info.options.length > 0 ? 'Parsed archiver options' : 'No archiver options',
        info: info
      };
    } catch (error) {
      return {
        ok: false,
        url: url,
        statusCode: 0,
        message: networkErrorMessage(error),
        info: null
      };
    }
  }

  async requestArchiverDownload(option: ArchiverOption, referer: string,
    site: GallerySite = GallerySite.E): Promise<ArchiverDownloadResult> {
    const form = buildFormBody([
      { key: 'dltype', value: option.dlType },
      { key: 'dlcheck', value: option.dlCheck }
    ]);
    try {
      const response = await this.postForm(option.url, form, referer, EhUrl.getReferer(site));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          ok: false,
          statusCode: response.statusCode,
          message: httpStatusMessage(response.statusCode, response.body),
          downloadUrl: ''
        };
      }
      const continueUrl = parseArchiverContinueUrl(response.body);
      if (continueUrl.length === 0) {
        return {
          ok: false,
          statusCode: response.statusCode,
          message: 'No archiver continuation URL',
          downloadUrl: ''
        };
      }
      const continueResponse = await this.getText(absoluteUrl(continueUrl, EhUrl.getHost(site)), EhUrl.getReferer(site), 0);
      const path = parseArchiverDownloadUrl(continueResponse.body);
      if (path.length === 0) {
        return {
          ok: false,
          statusCode: continueResponse.statusCode,
          message: 'No archiver download URL',
          downloadUrl: ''
        };
      }
      return {
        ok: true,
        statusCode: continueResponse.statusCode,
        message: 'Archiver download URL ready',
        downloadUrl: absoluteUrl(path, continueUrl)
      };
    } catch (error) {
      return {
        ok: false,
        statusCode: 0,
        message: networkErrorMessage(error),
        downloadUrl: ''
      };
    }
  }

  async skipHathAndReloadPage(pageUrl: string, skipHathKey: string, site: GallerySite = GallerySite.E,
    referer: string = EhUrl.getReferer(site)): Promise<GalleryPageLoadResult> {
    if (skipHathKey.length === 0) {
      return this.loadGalleryPage(pageUrl, site, referer);
    }
    return this.loadGalleryPageHtml(appendQueryParam(pageUrl, 'nl', skipHathKey), site, referer);
  }

  async loadGalleryPageFast(pageUrl: string, site: GallerySite = GallerySite.E,
    referer: string = EhUrl.getReferer(site), allowApi: boolean = true): Promise<GalleryPageLoadResult> {
    const pendingKey = buildGalleryPagePendingKey(pageUrl, site, referer, allowApi);
    const pending = getPendingGalleryPage(pendingKey);
    if (pending !== null) {
      return pending;
    }

    const promise = this.loadGalleryPageFastNetwork(pageUrl, site, referer, allowApi);
    putPendingGalleryPage(pendingKey, promise);
    try {
      return await promise;
    } finally {
      removePendingGalleryPage(pendingKey);
    }
  }

  private async loadGalleryPageFastNetwork(pageUrl: string, site: GallerySite = GallerySite.E,
    referer: string = EhUrl.getReferer(site), allowApi: boolean = true): Promise<GalleryPageLoadResult> {
    const urlInfo = parseGalleryPageUrl(pageUrl);
    if (allowApi && urlInfo !== null) {
      ehSpiderInfoStore.putPageToken(site, urlInfo.gid, urlInfo.pageIndex, urlInfo.pageToken);
      const showKey = getSharedShowKey(site, urlInfo.gid);
      if (showKey.length > 0) {
        const apiResult = await this.loadGalleryPageApi(urlInfo, showKey, pageUrl, site, referer);
        if (apiResult.ok || apiResult.message !== 'Key mismatch') {
          if (apiResult.ok && apiResult.page !== null) {
            const parsed = parseGalleryPageUrl(apiResult.page.pageUrl.length > 0 ? apiResult.page.pageUrl : pageUrl);
            if (parsed !== null) {
              ehSpiderInfoStore.putPageToken(site, parsed.gid, parsed.pageIndex, parsed.pageToken);
            }
          }
          return apiResult;
        }
        putSharedShowKey(site, urlInfo.gid, '');
      }
    }

    const htmlResult = await this.loadGalleryPageHtml(pageUrl, site, referer);
    if (htmlResult.ok && htmlResult.page !== null) {
      const parsed = parseGalleryPageUrl(htmlResult.page.pageUrl.length > 0 ? htmlResult.page.pageUrl : pageUrl);
      if (parsed !== null && htmlResult.page.showKey.length > 0) {
        putSharedShowKey(site, parsed.gid, htmlResult.page.showKey);
        ehSpiderInfoStore.putPageToken(site, parsed.gid, parsed.pageIndex, parsed.pageToken);
      }
    }
    return htmlResult;
  }

  private async loadGalleryPageApi(urlInfo: GalleryPageUrlInfo, showKey: string, pageUrl: string,
    site: GallerySite, referer: string): Promise<GalleryPageLoadResult> {
    const payload = JSON.stringify({
      method: 'showpage',
      gid: urlInfo.gid,
      page: urlInfo.pageIndex + 1,
      imgkey: urlInfo.pageToken,
      showkey: showKey
    });
    const requestReferer = referer.length > 0 ? referer : pageUrl;
    const origin = EhUrl.getReferer(site);
    const url = EhUrl.getApiUrl(site);
    try {
      const response = await this.postJson(url, payload, requestReferer, origin);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          ok: false,
          url: pageUrl,
          statusCode: response.statusCode,
          message: httpStatusMessage(response.statusCode, response.body),
          page: null
        };
      }

      const parsed: GalleryPageApiParseResult = parseGalleryPageApi(response.body, pageUrl, showKey);
      return {
        ok: parsed.page !== null,
        url: pageUrl,
        statusCode: response.statusCode,
        message: parsed.warning.length > 0 ? parsed.warning : 'Parsed gallery page via API',
        page: parsed.page
      };
    } catch (error) {
      return {
        ok: false,
        url: pageUrl,
        statusCode: 0,
        message: networkErrorMessage(error),
        page: null
      };
    }
  }

  private async loadGalleryPageHtml(pageUrl: string, site: GallerySite = GallerySite.E,
    referer: string = EhUrl.getReferer(site)): Promise<GalleryPageLoadResult> {
    try {
      const response = await this.getText(pageUrl, referer, 600000);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          ok: false,
          url: pageUrl,
          statusCode: response.statusCode,
          message: httpStatusMessage(response.statusCode, response.body),
          page: null
        };
      }

      const parsed: GalleryPageParseResult = parseGalleryPage(response.body, pageUrl);
      return {
        ok: parsed.page !== null,
        url: pageUrl,
        statusCode: response.statusCode,
        message: parsed.warning.length > 0 ? parsed.warning : 'Parsed gallery page',
        page: parsed.page
      };
    } catch (error) {
      return {
        ok: false,
        url: pageUrl,
        statusCode: 0,
        message: networkErrorMessage(error),
        page: null
      };
    }
  }

  async loadTopList(site: GallerySite = GallerySite.E): Promise<TopListLoadResult> {
    const url = EhUrl.getTopListUrl(site);
    try {
      const response = await this.getText(url, EhUrl.getReferer(site), 300000);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          ok: false,
          url: url,
          statusCode: response.statusCode,
          message: httpStatusMessage(response.statusCode, response.body),
          detail: null
        };
      }

      const parsed: TopListParseResult = parseTopList(response.body);
      return {
        ok: parsed.detail !== null,
        url: url,
        statusCode: response.statusCode,
        message: parsed.warning.length > 0 ? parsed.warning : 'Parsed top lists',
        detail: parsed.detail
      };
    } catch (error) {
      return {
        ok: false,
        url: url,
        statusCode: 0,
        message: networkErrorMessage(error),
        detail: null
      };
    }
  }

  private async loadImageSearchList(builder: ListUrlBuilder, site: GallerySite): Promise<GalleryListLoadResult> {
    const url = EhUrl.getImageSearchUrl(site);
    if (builder.imagePath.length === 0) {
      return emptyGalleryListResult(url, 'No image selected for search');
    }
    try {
      const multipart = buildImageSearchMultipartBody(builder.imagePath, builder.useSimilarityScan,
        builder.onlySearchCovers, builder.showExpunged);
      const referer = EhUrl.getReferer(site) + '/';
      let response = await this.postMultipart(url, multipart.body, multipart.contentType, referer, EhUrl.getReferer(site));
      const redirectUrl = imageSearchRedirectUrl(response, url);
      if (redirectUrl.length > 0) {
        response = await this.getText(redirectUrl, referer, 0);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return emptyGalleryListResult(url, httpStatusMessage(response.statusCode, response.body), response.statusCode);
      }
      const parsed: GalleryListParseResult = parseGalleryList(response.body);
      await this.fillGalleryListByApi(parsed.galleries, url, site);
      const ok = parsed.galleries.length > 0 || isSuccessfulEmptyImageSearch(parsed.warning);
      return {
        ok: ok,
        url: redirectUrl.length > 0 ? redirectUrl : url,
        statusCode: response.statusCode,
        message: parsed.warning.length > 0 ? parsed.warning : 'Parsed image search results',
        pages: parsed.pages,
        nextPage: parsed.nextPage,
        nextUrl: parsed.nextUrl,
        resultCount: parsed.resultCount,
        galleries: parsed.galleries
      };
    } catch (error) {
      return emptyGalleryListResult(url, networkErrorMessage(error));
    }
  }

  private async postMultipart(url: string, body: ArrayBuffer, contentType: string, referer: string,
    origin: string): Promise<EhHttpResponse> {
    return requestTextWithRetry((): Promise<EhHttpResponse> => {
      return this.postMultipartOnce(url, body, contentType, referer, origin);
    }, 2);
  }

  private async postMultipartOnce(url: string, body: ArrayBuffer, contentType: string, referer: string,
    origin: string): Promise<EhHttpResponse> {
    const request = http.createHttp();
    let plan: EhRequestPlan | null = null;
    const startedAt = Date.now();
    let outcomeRecorded = false;
    let responseHeaders: Record<string, Object> = {};
    await acquireTextSlot();
    try {
      plan = createEhRequestPlan(url);
      const header = buildMultipartRequestHeader(plan, referer, origin, ehCookieStore.getCookieHeaderForUrl(url),
        contentType);
      await ensureEhHostRules();
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: header,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: TEXT_CONNECT_TIMEOUT_MS,
        readTimeout: TEXT_READ_TIMEOUT_MS
      };
      applyEhNetworkOptions(options, plan);
      request.on('headersReceive', (header: Object) => {
        responseHeaders = header as Record<string, Object>;
      });
      const response = await requestWithDeadline(request, plan.url, options, TEXT_DEADLINE_TIMEOUT_MS);
      const statusCode = Number(response.responseCode);
      recordEhRequestOutcome(plan, statusCode >= 200 && statusCode < 500, Date.now() - startedAt);
      outcomeRecorded = true;

      ehCookieStore.absorbSetCookieHeader(response.cookies);
      syncSetCookiesToWebView(url, response.cookies);
      return {
        statusCode: statusCode,
        body: response.result as string,
        cookies: response.cookies,
        headers: responseHeaders
      };
    } catch (error) {
      if (plan !== null && !outcomeRecorded) {
        recordEhRequestOutcome(plan, false, Date.now() - startedAt);
      }
      throw new Error(networkErrorMessage(error));
    } finally {
      try {
        request.off('headersReceive');
        request.destroy();
      } catch (error) {
      }
      releaseTextSlot();
    }
  }
}

interface RequestHeader {
  'Host'?: string;
  'User-Agent': string;
  'Accept': string;
  'Accept-Language': string;
  'Accept-Encoding'?: string;
  'Referer': string;
  'Cache-Control'?: string;
  'Pragma'?: string;
  'Connection': string;
  'Content-Type'?: string;
  'Origin'?: string;
  'Cookie'?: string;
}

interface FormField {
  key: string;
  value: string;
}

interface ImageSearchMultipartBody {
  body: ArrayBuffer;
  contentType: string;
}

interface ParsedSignIn {
  ok: boolean;
  displayName: string;
  message: string;
}

async function requestTextWithRetry(requester: () => Promise<EhHttpResponse>, maxAttempts: number): Promise<EhHttpResponse> {
  let lastError = '';
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      const response = await requester();
      if (attempt + 1 < maxAttempts && isTransientStatus(response.statusCode)) {
        await sleepRetry(attempt);
        continue;
      }
      return response;
    } catch (error) {
      lastError = networkErrorMessage(error);
      if (attempt + 1 >= maxAttempts || !isTransientError(lastError)) {
        throw new Error(lastError);
      }
      await sleepRetry(attempt);
    }
  }
  throw new Error(lastError.length > 0 ? lastError : 'Network request failed');
}

function acquireTextSlot(): Promise<void> {
  if (activeTextRequests < MAX_ACTIVE_TEXT_REQUESTS) {
    activeTextRequests++;
    return Promise.resolve();
  }

  return new Promise<void>((resolve: (value: void | PromiseLike<void>) => void) => {
    WAITING_TEXT_SLOTS.push({
      resume: () => {
        activeTextRequests++;
        resolve();
      }
    });
  });
}

function releaseTextSlot(): void {
  activeTextRequests = Math.max(0, activeTextRequests - 1);
  const next = WAITING_TEXT_SLOTS.shift();
  if (next !== undefined) {
    next.resume();
  }
}

function sleepRetry(attempt: number): Promise<void> {
  const index = Math.min(attempt, TEXT_RETRY_DELAYS_MS.length - 1);
  const delay = TEXT_RETRY_DELAYS_MS[index];
  return new Promise<void>((resolve: (value: void | PromiseLike<void>) => void) => {
    setTimeout(() => {
      resolve();
    }, delay);
  });
}

function requestWithDeadline(request: http.HttpRequest, url: string, options: http.HttpRequestOptions,
  timeoutMs: number): Promise<http.HttpResponse> {
  return new Promise<http.HttpResponse>((resolve: (value: http.HttpResponse) => void, reject: (reason: Error) => void) => {
    let finished = false;
    const timer = setTimeout(() => {
      if (finished) {
        return;
      }
      finished = true;
      try {
        request.destroy();
      } catch (error) {
      }
      reject(new Error('Network request timed out after ' + Math.floor(timeoutMs / 1000).toString() + 's'));
    }, timeoutMs);

    request.request(url, options).then((response: http.HttpResponse) => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimeout(timer);
      resolve(response);
    }).catch((error: Error) => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimeout(timer);
      reject(error);
    });
  });
}

function syncSetCookiesToWebView(url: string, setCookieHeader: string): void {
  if (setCookieHeader.length === 0) {
    return;
  }

  const lines = setCookieHeader.split('\n');
  let synced = false;
  for (let i = 0; i < lines.length; i++) {
    const cookie = lines[i].trim();
    if (cookie.length === 0) {
      continue;
    }
    try {
      webview.WebCookieManager.configCookieSync(url, cookie);
      synced = true;
    } catch (error) {
    }
  }

  if (synced) {
    try {
      webview.WebCookieManager.saveCookieSync();
    } catch (error) {
    }
  }
}

function isTransientStatus(statusCode: number): boolean {
  return statusCode === 408 || statusCode === 429 || statusCode === 500 || statusCode === 502 ||
    statusCode === 503 || statusCode === 504 || statusCode === 522 || statusCode === 524;
}

function isTransientError(message: string): boolean {
  const lower = message.toLowerCase();
  return lower.indexOf('timeout') >= 0 || lower.indexOf('timed out') >= 0 || lower.indexOf('reset') >= 0 ||
    lower.indexOf('refused') >= 0 || lower.indexOf('unreachable') >= 0 || lower.indexOf('unknownhost') >= 0 ||
    lower.indexOf('dns') >= 0 || lower.indexOf('network') >= 0 || lower.indexOf('socket') >= 0 ||
    lower.indexOf('ssl') >= 0 || lower.indexOf('tls') >= 0 || lower.indexOf('certificate') >= 0 ||
    lower.indexOf('http2') >= 0 || lower.indexOf('2300016') >= 0 ||
    lower.indexOf('2300007') >= 0 || lower.indexOf('230350') >= 0 ||
    lower.indexOf('temporary') >= 0 || lower.indexOf('503') >= 0 || lower.indexOf('504') >= 0;
}

function httpStatusMessage(statusCode: number, body: string): string {
  const lower = body.toLowerCase();
  if (statusCode === 403) {
    if (lower.indexOf('captcha') >= 0) {
      return 'Access denied: captcha is required';
    }
    return 'Access denied: check login cookies or site permission';
  }
  if (statusCode === 404) {
    return 'Not found: the gallery or page may have been removed';
  }
  if (statusCode === 429) {
    return 'Too many requests: slow down and retry later';
  }
  if (statusCode === 509 || lower.indexOf('509') >= 0 || lower.indexOf('bandwidth limit') >= 0) {
    return 'Image limit reached: wait for quota reset or use original site settings';
  }
  if (statusCode === 503 && (lower.indexOf('cloudflare') >= 0 || lower.indexOf('checking your browser') >= 0)) {
    return 'Site protection is blocking the request; retry after web verification';
  }
  if (isTransientStatus(statusCode)) {
    return 'Temporary network error: HTTP ' + statusCode.toString();
  }
  return 'HTTP ' + statusCode.toString();
}

function galleryListBodyDiagnostic(body: string): string {
  const linkCount = countPattern(body, /\/g\/\d+\/[A-Za-z0-9]+\//g);
  const tableCount = countPattern(body, /class=["'][^"']*\bitg\b/gi);
  const title = parseHtmlTitle(body);
  const parts: string[] = [
    'body ' + body.length.toString() + ' bytes',
    'links ' + linkCount.toString(),
    'itg ' + tableCount.toString()
  ];
  if (title.length > 0) {
    parts.push('title "' + title + '"');
  }
  return parts.join(', ');
}

function countPattern(text: string, pattern: RegExp): number {
  let count = 0;
  let match: RegExpExecArray | null = pattern.exec(text);
  while (match !== null) {
    count++;
    match = pattern.exec(text);
  }
  return count;
}

function parseHtmlTitle(body: string): string {
  const match = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(body);
  return match === null ? '' : cleanHtml(match[1]);
}

function appendQueryParam(url: string, key: string, value: string): string {
  const hashIndex = url.indexOf('#');
  const base = hashIndex >= 0 ? url.substring(0, hashIndex) : url;
  const hash = hashIndex >= 0 ? url.substring(hashIndex) : '';
  const separator = base.indexOf('?') >= 0 ? '&' : '?';
  return base + separator + encodeURIComponent(key) + '=' + encodeURIComponent(value) + hash;
}

function networkErrorMessage(error: Object): string {
  let message = readableErrorMessage(error);
  if (message.indexOf('Error: ') === 0) {
    message = message.substring(7);
  }
  const lower = message.toLowerCase();
  if (lower.indexOf('timeout') >= 0 || lower.indexOf('timed out') >= 0) {
    return 'Network timeout: please retry or adjust proxy/DNS settings';
  }
  if (lower.indexOf('unknownhost') >= 0 || lower.indexOf('dns') >= 0) {
    return 'DNS lookup failed: check network, built-in hosts or DoH settings';
  }
  if (lower.indexOf('ssl') >= 0 || lower.indexOf('tls') >= 0 || lower.indexOf('certificate') >= 0) {
    return 'TLS connection failed: check network interception or domain fronting settings';
  }
  if (lower.indexOf('refused') >= 0 || lower.indexOf('proxy') >= 0) {
    return 'Connection refused: check proxy settings';
  }
  return message.length > 0 ? message : 'Network request failed';
}

function readableErrorMessage(error: Object): string {
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
  const name = record['name'];
  if (typeof name === 'string' && name.length > 0) {
    return name;
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

function buildRequestHeader(plan: EhRequestPlan, referer: string, cookieHeader: string, cacheTtlMs: number): RequestHeader {
  const maxAge = Math.max(0, Math.floor(cacheTtlMs / 1000));
  const header: RequestHeader = {
    'Host': plan.host,
    'User-Agent': CHROME_USER_AGENT,
    'Accept': CHROME_ACCEPT,
    'Accept-Language': CHROME_ACCEPT_LANGUAGE,
    'Referer': referer,
    'Cache-Control': maxAge > 0 ? 'max-age=' + maxAge.toString() : 'no-cache',
    'Connection': plan.fronted ? 'close' : 'keep-alive'
  };
  if (cookieHeader.length > 0) {
    header.Cookie = cookieHeader;
  }
  return header;
}

function buildPostRequestHeader(plan: EhRequestPlan, referer: string, origin: string,
  cookieHeader: string): RequestHeader {
  const header: RequestHeader = {
    'Host': plan.host,
    'User-Agent': CHROME_USER_AGENT,
    'Accept': CHROME_ACCEPT,
    'Accept-Language': CHROME_ACCEPT_LANGUAGE,
    'Referer': referer,
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
    'Connection': plan.fronted ? 'close' : 'keep-alive',
    'Content-Type': 'application/x-www-form-urlencoded',
    'Origin': origin
  };
  if (cookieHeader.length > 0) {
    header.Cookie = cookieHeader;
  }
  return header;
}

function buildJsonRequestHeader(plan: EhRequestPlan, referer: string, origin: string,
  cookieHeader: string): RequestHeader {
  const header: RequestHeader = {
    'Host': plan.host,
    'User-Agent': CHROME_USER_AGENT,
    'Accept': 'application/json,text/plain,*/*;q=0.8',
    'Accept-Language': CHROME_ACCEPT_LANGUAGE,
    'Referer': referer,
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
    'Connection': plan.fronted ? 'close' : 'keep-alive',
    'Content-Type': 'application/json',
    'Origin': origin
  };
  if (cookieHeader.length > 0) {
    header.Cookie = cookieHeader;
  }
  return header;
}

function buildMultipartRequestHeader(plan: EhRequestPlan, referer: string, origin: string, cookieHeader: string,
  contentType: string): RequestHeader {
  const header: RequestHeader = {
    'Host': plan.host,
    'User-Agent': CHROME_USER_AGENT,
    'Accept': CHROME_ACCEPT,
    'Accept-Language': CHROME_ACCEPT_LANGUAGE,
    'Referer': referer,
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
    'Connection': plan.fronted ? 'close' : 'keep-alive',
    'Content-Type': contentType,
    'Origin': origin
  };
  if (cookieHeader.length > 0) {
    header.Cookie = cookieHeader;
  }
  return header;
}

function buildFormBody(fields: FormField[]): string {
  const parts: string[] = [];
  for (let i = 0; i < fields.length; i++) {
    parts.push(encodeURIComponent(fields[i].key) + '=' + encodeURIComponent(fields[i].value));
  }
  return parts.join('&');
}

function emptyGalleryListResult(url: string, message: string, statusCode: number = 0): GalleryListLoadResult {
  return {
    ok: false,
    url: url,
    statusCode: statusCode,
    message: message,
    pages: 0,
    nextPage: -1,
    nextUrl: '',
    resultCount: '',
    galleries: []
  };
}

function buildImageSearchMultipartBody(imagePath: string, useSimilarityScan: boolean, onlySearchCovers: boolean,
  showExpunged: boolean): ImageSearchMultipartBody {
  const boundary = '----EhViewerOHOS' + Date.now().toString(16);
  const fileName = imageFileName(imagePath);
  const fileData = readFileBuffer(imagePath);
  const chunks: ArrayBuffer[] = [];
  chunks.push(stringToUtf8Buffer('--' + boundary + '\r\n'));
  chunks.push(stringToUtf8Buffer('Content-Disposition: form-data; name="sfile"; filename="' + fileName +
    '"; size="40"\r\n'));
  chunks.push(stringToUtf8Buffer('Content-Type: ' + imageMimeType(fileName) + '\r\n\r\n'));
  chunks.push(fileData);
  chunks.push(stringToUtf8Buffer('\r\n'));
  if (useSimilarityScan) {
    appendMultipartText(chunks, boundary, 'fs_similar', 'on');
  }
  if (onlySearchCovers) {
    appendMultipartText(chunks, boundary, 'fs_covers', 'on');
  }
  if (showExpunged) {
    appendMultipartText(chunks, boundary, 'fs_exp', 'on');
  }
  appendMultipartText(chunks, boundary, 'f_sfile', 'File Search');
  chunks.push(stringToUtf8Buffer('--' + boundary + '--\r\n'));
  return {
    body: concatBuffers(chunks),
    contentType: 'multipart/form-data; boundary=' + boundary
  };
}

function appendMultipartText(chunks: ArrayBuffer[], boundary: string, name: string, value: string): void {
  chunks.push(stringToUtf8Buffer('--' + boundary + '\r\n'));
  chunks.push(stringToUtf8Buffer('Content-Disposition: form-data; name="' + name + '"\r\n\r\n'));
  chunks.push(stringToUtf8Buffer(value + '\r\n'));
}

function readFileBuffer(path: string): ArrayBuffer {
  let fd = -1;
  try {
    const stat = fs.statSync(path);
    const buffer = new ArrayBuffer(stat.size);
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    fd = file.fd;
    fs.readSync(fd, buffer);
    return buffer;
  } catch (error) {
    throw new Error('Failed to read image file');
  } finally {
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (error) {
      }
    }
  }
}

function stringToUtf8Buffer(value: string): ArrayBuffer {
  const bytes: number[] = [];
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xc0 | (code >> 6));
      bytes.push(0x80 | (code & 0x3f));
    } else {
      bytes.push(0xe0 | (code >> 12));
      bytes.push(0x80 | ((code >> 6) & 0x3f));
      bytes.push(0x80 | (code & 0x3f));
    }
  }
  return new Uint8Array(bytes).buffer;
}

function concatBuffers(chunks: ArrayBuffer[]): ArrayBuffer {
  let length = 0;
  for (let i = 0; i < chunks.length; i++) {
    length += chunks[i].byteLength;
  }
  const merged = new Uint8Array(length);
  let offset = 0;
  for (let i = 0; i < chunks.length; i++) {
    merged.set(new Uint8Array(chunks[i]), offset);
    offset += chunks[i].byteLength;
  }
  return merged.buffer;
}

function imageFileName(path: string): string {
  const index = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  const name = index >= 0 ? path.substring(index + 1) : path;
  return name.indexOf('.') > 0 ? name : name + '.jpg';
}

function imageMimeType(fileName: string): string {
  const lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lower.endsWith('.gif')) {
    return 'image/gif';
  }
  return 'image/jpeg';
}

function imageSearchRedirectUrl(response: EhHttpResponse, baseUrl: string): string {
  if (response.statusCode < 300 || response.statusCode >= 400 || response.headers === undefined) {
    return '';
  }
  const location = responseHeaderValue(response.headers, 'location');
  if (location.length === 0) {
    return '';
  }
  return absoluteUrl(location, baseUrl);
}

function isSuccessfulEmptyImageSearch(warning: string): boolean {
  return warning === 'No hits found';
}

function responseHeaderValue(headers: Record<string, Object>, name: string): string {
  const keys = Object.keys(headers);
  const target = name.toLowerCase();
  for (let i = 0; i < keys.length; i++) {
    if (keys[i].toLowerCase() !== target) {
      continue;
    }
    const value = headers[keys[i]];
    if (typeof value === 'string') {
      return value;
    }
    if (Array.isArray(value) && value.length > 0 && typeof value[0] === 'string') {
      return value[0];
    }
    return String(value);
  }
  return '';
}

function absoluteUrl(url: string, base: string): string {
  if (url.indexOf('http://') === 0 || url.indexOf('https://') === 0) {
    return url;
  }
  if (url.indexOf('//') === 0) {
    return 'https:' + url;
  }
  const hostMatch = /^(https?:\/\/[^/]+)/i.exec(base);
  const host = hostMatch === null ? base : hostMatch[1];
  if (url.indexOf('/') === 0) {
    return host + url;
  }
  const slash = base.lastIndexOf('/');
  return (slash > 'https://'.length ? base.substring(0, slash + 1) : host + '/') + url;
}

function buildCacheKey(method: string, url: string, referer: string, cookieHeader: string): string {
  return method + '\n' + url + '\n' + referer + '\n' + cookieHeader;
}

function buildGalleryPagePendingKey(pageUrl: string, site: GallerySite, referer: string, allowApi: boolean): string {
  return Number(site).toString() + '\n' + pageUrl + '\n' + referer + '\n' + (allowApi ? '1' : '0');
}

function cloneResponse(response: EhHttpResponse): EhHttpResponse {
  return {
    statusCode: response.statusCode,
    body: response.body,
    cookies: response.cookies,
    headers: response.headers
  };
}

function getPendingGalleryPage(key: string): Promise<GalleryPageLoadResult> | null {
  for (let i = 0; i < SHARED_PENDING_PAGE_LOADS.length; i++) {
    if (SHARED_PENDING_PAGE_LOADS[i].key === key) {
      return SHARED_PENDING_PAGE_LOADS[i].promise.then((result: GalleryPageLoadResult) => cloneGalleryPageLoadResult(result));
    }
  }
  return null;
}

function putPendingGalleryPage(key: string, promise: Promise<GalleryPageLoadResult>): void {
  removePendingGalleryPage(key);
  SHARED_PENDING_PAGE_LOADS.push({ key: key, promise: promise });
}

function removePendingGalleryPage(key: string): void {
  for (let i = SHARED_PENDING_PAGE_LOADS.length - 1; i >= 0; i--) {
    if (SHARED_PENDING_PAGE_LOADS[i].key === key) {
      SHARED_PENDING_PAGE_LOADS.splice(i, 1);
    }
  }
}

function cloneGalleryPageLoadResult(result: GalleryPageLoadResult): GalleryPageLoadResult {
  return {
    ok: result.ok,
    url: result.url,
    statusCode: result.statusCode,
    message: result.message,
    page: result.page === null ? null : {
      pageUrl: result.page.pageUrl,
      imageUrl: result.page.imageUrl,
      skipHathKey: result.page.skipHathKey,
      originImageUrl: result.page.originImageUrl,
      showKey: result.page.showKey,
      cachedImagePath: result.page.cachedImagePath,
      cachedOriginImagePath: result.page.cachedOriginImagePath
    }
  };
}

function showKeyCacheKey(site: GallerySite, gid: number): string {
  return site.toString() + ':' + gid.toString();
}

function getSharedShowKey(site: GallerySite, gid: number): string {
  const key = showKeyCacheKey(site, gid);
  for (let i = 0; i < SHARED_SHOW_KEYS.length; i++) {
    if (SHARED_SHOW_KEYS[i].key === key) {
      return SHARED_SHOW_KEYS[i].showKey;
    }
  }
  const persisted = ehSpiderInfoStore.getShowKey(site, gid);
  if (persisted.length > 0) {
    SHARED_SHOW_KEYS.unshift({ key: key, showKey: persisted });
    while (SHARED_SHOW_KEYS.length > 32) {
      SHARED_SHOW_KEYS.pop();
    }
  }
  return persisted;
}

function putSharedShowKey(site: GallerySite, gid: number, showKey: string): void {
  const key = showKeyCacheKey(site, gid);
  for (let i = 0; i < SHARED_SHOW_KEYS.length; i++) {
    if (SHARED_SHOW_KEYS[i].key === key) {
      if (showKey.length === 0) {
        SHARED_SHOW_KEYS.splice(i, 1);
        ehSpiderInfoStore.putShowKey(site, gid, '');
      } else {
        SHARED_SHOW_KEYS[i].showKey = showKey;
        ehSpiderInfoStore.putShowKey(site, gid, showKey);
      }
      return;
    }
  }
  if (showKey.length > 0) {
    SHARED_SHOW_KEYS.unshift({ key: key, showKey: showKey });
    ehSpiderInfoStore.putShowKey(site, gid, showKey);
  }

  while (SHARED_SHOW_KEYS.length > 32) {
    SHARED_SHOW_KEYS.pop();
  }
}

function parseSignIn(body: string): ParsedSignIn {
  const namePattern: RegExp = /<p>You are now logged in as:\s*(.+?)</i;
  const nameMatch = namePattern.exec(body);
  if (nameMatch !== null) {
    return { ok: true, displayName: cleanHtml(nameMatch[1]), message: '' };
  }

  const errorPattern: RegExp = /(?:<h4>The error returned was:<\/h4>\s*<p>(.+?)<\/p>)|(?:<span class=["']postcolor["']>(.+?)<\/span>)/i;
  const errorMatch = errorPattern.exec(body);
  if (errorMatch !== null) {
    const message = errorMatch[1] === undefined ? errorMatch[2] : errorMatch[1];
    return { ok: false, displayName: '', message: cleanHtml(message) };
  }

  if (body.indexOf('captcha') >= 0 || body.indexOf('CAPTCHA') >= 0) {
    return { ok: false, displayName: '', message: 'Captcha required; use Cookie sign in or web login later' };
  }
  return { ok: false, displayName: '', message: 'Cannot parse sign in response' };
}

interface RateGalleryParsed {
  rating: number;
  ratingCount: number;
}

function parseRateGalleryResponse(body: string, fallbackRating: number): RateGalleryParsed {
  try {
    const obj = JSON.parse(body) as Record<string, Object>;
    const avg = typeof obj['avg_rating'] === 'number' ? obj['avg_rating'] as number : fallbackRating;
    const count = typeof obj['rating_count'] === 'number' ? obj['rating_count'] as number : 0;
    return { rating: avg, ratingCount: count };
  } catch (error) {
    return { rating: fallbackRating, ratingCount: 0 };
  }
}

function cleanHtml(value: string): string {
  return value
    .replace(/<[^>]+>/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, '\'')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/\s+/g, ' ')
    .trim();
}
