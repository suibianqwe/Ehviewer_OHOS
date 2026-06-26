import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { GalleryDetail, GalleryInfo, GalleryPage, GallerySite, TopListDetail } from '../model/GalleryModels';
import { ehCookieStore } from './EhCookieStore';
import { EhUrl, FavListUrlBuilder, ListUrlBuilder } from './EhUrl';
import { GalleryDetailParseResult, parseGalleryDetail } from './GalleryDetailParser';
import { mergeGalleryApiMetadata } from './GalleryApiParser';
import { GalleryListParseResult, parseGalleryList } from './GalleryListParser';
import { GalleryPageApiParseResult, parseGalleryPageApi } from './GalleryPageApiParser';
import { GalleryPageParseResult, parseGalleryPage } from './GalleryPageParser';
import { GalleryPageUrlInfo, parseGalleryPageUrl } from './GalleryPageUrlParser';
import { ehSpiderInfoStore } from './EhSpiderInfoStore';
import { applyEhNetworkOptions, ensureEhHostRules } from './EhNetworkConfig';
import { TopListParseResult, parseTopList } from './TopListParser';

export interface EhHttpResponse {
  statusCode: number;
  body: string;
  cookies: string;
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
    await acquireTextSlot();
    try {
      const header = buildRequestHeader(url, referer, cookieHeader, cacheTtlMs);
      await ensureEhHostRules();
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: TEXT_CONNECT_TIMEOUT_MS,
        readTimeout: TEXT_READ_TIMEOUT_MS
      };
      applyEhNetworkOptions(options, url);
      const response = await requestWithDeadline(request, url, options, TEXT_DEADLINE_TIMEOUT_MS);

      ehCookieStore.absorbSetCookieHeader(response.cookies);
      syncSetCookiesToWebView(url, response.cookies);
      return {
        statusCode: Number(response.responseCode),
        body: response.result as string,
        cookies: response.cookies
      };
    } catch (error) {
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
    await acquireTextSlot();
    try {
      const header = buildPostRequestHeader(referer, origin, cookieHeader);
      await ensureEhHostRules();
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: header,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: TEXT_CONNECT_TIMEOUT_MS,
        readTimeout: TEXT_READ_TIMEOUT_MS
      };
      applyEhNetworkOptions(options, url);
      const response = await requestWithDeadline(request, url, options, TEXT_DEADLINE_TIMEOUT_MS);

      ehCookieStore.absorbSetCookieHeader(response.cookies);
      syncSetCookiesToWebView(url, response.cookies);
      return {
        statusCode: Number(response.responseCode),
        body: response.result as string,
        cookies: response.cookies
      };
    } catch (error) {
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
    await acquireTextSlot();
    try {
      const cookieHeader = ehCookieStore.getCookieHeaderForUrl(url);
      const header = buildJsonRequestHeader(referer, origin, cookieHeader);
      await ensureEhHostRules();
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: header,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: API_TIMEOUT_MS,
        readTimeout: API_TIMEOUT_MS
      };
      applyEhNetworkOptions(options, url);
      const response = await requestWithDeadline(request, url, options, API_DEADLINE_TIMEOUT_MS);

      ehCookieStore.absorbSetCookieHeader(response.cookies);
      syncSetCookiesToWebView(url, response.cookies);
      return {
        statusCode: Number(response.responseCode),
        body: response.result as string,
        cookies: response.cookies
      };
    } catch (error) {
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
      { label: 'E', url: EhUrl.HOST_E + '/', referer: EhUrl.HOST_E + '/' },
      { label: 'EX', url: EhUrl.HOST_EX + '/', referer: EhUrl.HOST_EX + '/' },
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

function networkErrorMessage(error: Object): string {
  let message = String(error);
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

function buildRequestHeader(url: string, referer: string, cookieHeader: string, cacheTtlMs: number): RequestHeader {
  const maxAge = Math.max(0, Math.floor(cacheTtlMs / 1000));
  const header: RequestHeader = {
    'Host': requestHost(url),
    'User-Agent': CHROME_USER_AGENT,
    'Accept': CHROME_ACCEPT,
    'Accept-Language': CHROME_ACCEPT_LANGUAGE,
    'Referer': referer,
    'Cache-Control': maxAge > 0 ? 'max-age=' + maxAge.toString() : 'no-cache',
    'Connection': 'keep-alive'
  };
  if (cookieHeader.length > 0) {
    header.Cookie = cookieHeader;
  }
  return header;
}

function buildPostRequestHeader(referer: string, origin: string, cookieHeader: string): RequestHeader {
  const header: RequestHeader = {
    'User-Agent': CHROME_USER_AGENT,
    'Accept': CHROME_ACCEPT,
    'Accept-Language': CHROME_ACCEPT_LANGUAGE,
    'Referer': referer,
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
    'Connection': 'keep-alive',
    'Content-Type': 'application/x-www-form-urlencoded',
    'Origin': origin
  };
  if (cookieHeader.length > 0) {
    header.Cookie = cookieHeader;
  }
  return header;
}

function buildJsonRequestHeader(referer: string, origin: string, cookieHeader: string): RequestHeader {
  const header: RequestHeader = {
    'User-Agent': CHROME_USER_AGENT,
    'Accept': 'application/json,text/plain,*/*;q=0.8',
    'Accept-Language': CHROME_ACCEPT_LANGUAGE,
    'Referer': referer,
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
    'Connection': 'keep-alive',
    'Content-Type': 'application/json',
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

function requestHost(url: string): string {
  const match = /^https?:\/\/([^\/?#]+)/i.exec(url);
  return match === null ? '' : match[1];
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
    cookies: response.cookies
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
