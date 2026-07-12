import { ALL_CATEGORY, GalleryCategory, GallerySite } from '../model/GalleryModels';

export interface QueryParam {
  key: string;
  value: string;
}

export enum ListMode {
  Normal = 0,
  Uploader = 1,
  Tag = 2,
  WhatsHot = 3,
  ImageSearch = 4,
  Subscription = 5,
  Filter = 6,
  TopList = 7
}

export const DEFAULT_ADVANCE_SEARCH: number = 0x1 | 0x2;
export const DEFAULT_MIN_RATING: number = 2;

export class EhUrl {
  static readonly DOMAIN_EX: string = 'exhentai.org';
  static readonly DOMAIN_E: string = 'e-hentai.org';
  static readonly DOMAIN_LOFI: string = 'lofi.e-hentai.org';

  static readonly HOST_EX: string = 'https://exhentai.org/';
  static readonly HOST_E: string = 'https://e-hentai.org/';
  static readonly FORUM_ORIGIN: string = 'https://forums.e-hentai.org';
  static readonly API_SIGN_IN: string = 'https://forums.e-hentai.org/index.php?act=Login&CODE=01';
  static readonly URL_SIGN_IN: string = 'https://forums.e-hentai.org/index.php?act=Login';
  static readonly SIGN_IN_REFERER: string = 'https://forums.e-hentai.org/index.php?act=Login&CODE=00';

  static getHost(site: GallerySite = GallerySite.E): string {
    return site === GallerySite.Ex ? EhUrl.HOST_EX : EhUrl.HOST_E;
  }

  static getReferer(site: GallerySite = GallerySite.E): string {
    return site === GallerySite.Ex ? 'https://exhentai.org' : 'https://e-hentai.org';
  }

  static getApiUrl(site: GallerySite = GallerySite.E): string {
    return EhUrl.getHost(site) + 'api.php';
  }

  static getHomeUrl(_site: GallerySite = GallerySite.E): string {
    // Account limits are served only by E-Hentai, even when gallery browsing uses ExHentai.
    return EhUrl.HOST_E + 'home.php';
  }

  static getFavoritesUrl(site: GallerySite = GallerySite.E): string {
    return EhUrl.getHost(site) + 'favorites.php';
  }

  static getPopularUrl(site: GallerySite = GallerySite.E): string {
    return EhUrl.getHost(site) + 'popular';
  }

  static getTopListUrl(_site: GallerySite = GallerySite.E): string {
    return EhUrl.HOST_E + 'toplist.php';
  }

  static getAddFavoritesUrl(gid: number, token: string, site: GallerySite = GallerySite.E): string {
    return EhUrl.getHost(site) + 'gallerypopups.php?gid=' + gid.toString() + '&t=' + token + '&act=addfav';
  }

  static getDownloadArchiveUrl(gid: number, token: string, formParamOr: string = '',
    site: GallerySite = GallerySite.E): string {
    const params: QueryParam[] = [
      { key: 'gid', value: gid.toString() },
      { key: 'token', value: token }
    ];
    if (formParamOr.length > 0) {
      params.push({ key: 'or', value: formParamOr });
    }
    return buildUrl(EhUrl.getHost(site) + 'archiver.php', params);
  }

  static getImageSearchUrl(site: GallerySite = GallerySite.E): string {
    return site === GallerySite.Ex ? 'https://upld.exhentai.org/upld/image_lookup.php' :
      'https://upld.e-hentai.org/image_lookup.php';
  }

  static getWatchedUrl(site: GallerySite = GallerySite.E): string {
    return EhUrl.getHost(site) + 'watched';
  }

  static getGalleryDetailUrl(gid: number, token: string, index: number = 0, allComment: boolean = false,
    site: GallerySite = GallerySite.E): string {
    const params: QueryParam[] = [];
    if (index !== 0) {
      params.push({ key: 'p', value: index.toString() });
    }
    if (allComment) {
      params.push({ key: 'hc', value: '1' });
    }
    return buildUrl(EhUrl.getHost(site) + 'g/' + gid.toString() + '/' + token + '/', params);
  }

  static getPageUrl(gid: number, index: number, pageToken: string, site: GallerySite = GallerySite.E): string {
    return EhUrl.getHost(site) + 's/' + pageToken + '/' + gid.toString() + '-' + (index + 1).toString();
  }
}

export class ListUrlBuilder {
  mode: ListMode = ListMode.Normal;
  pageIndex: number = 0;
  category: number = GalleryCategory.None;
  keyword: string = '';
  follow: string = '';
  advanceSearch: number = -1;
  includeAdvSearchParam: boolean = true;
  minRating: number = -1;
  pageFrom: number = -1;
  pageTo: number = -1;
  showExpunged: boolean = false;
  imagePath: string = '';
  useSimilarityScan: boolean = false;
  onlySearchCovers: boolean = false;

  reset(): void {
    this.mode = ListMode.Normal;
    this.pageIndex = 0;
    this.category = GalleryCategory.None;
    this.keyword = '';
    this.follow = '';
    this.advanceSearch = -1;
    this.includeAdvSearchParam = true;
    this.minRating = -1;
    this.pageFrom = -1;
    this.pageTo = -1;
    this.showExpunged = false;
    this.imagePath = '';
    this.useSimilarityScan = false;
    this.onlySearchCovers = false;
  }

  build(site: GallerySite = GallerySite.E): string {
    switch (this.mode) {
      case ListMode.Uploader:
        return buildUrl(buildPathUrl(EhUrl.getHost(site), 'uploader', this.keyword, this.pageIndex),
          this.buildPathSearchParams());
      case ListMode.Tag:
        return buildUrl(buildPathUrl(EhUrl.getHost(site), 'tag', this.keyword, this.pageIndex),
          this.buildPathSearchParams());
      case ListMode.Filter:
        return buildUrl(EhUrl.getHost(site), this.buildFilterParams());
      case ListMode.WhatsHot:
        return buildUrl(EhUrl.getPopularUrl(site), this.buildPopularParams());
      case ListMode.ImageSearch:
        return EhUrl.getImageSearchUrl(site);
      case ListMode.Subscription:
        return buildUrl(EhUrl.getWatchedUrl(site), this.buildNormalParams());
      case ListMode.TopList:
        return buildTopListUrl(site, this.follow, this.pageIndex);
      case ListMode.Normal:
      default:
        return buildUrl(EhUrl.getHost(site), this.buildNormalParams());
    }
  }

  private buildNormalParams(): QueryParam[] {
    const params: QueryParam[] = [];
    if (this.category !== GalleryCategory.None) {
      params.push({ key: 'f_cats', value: ((~this.category) & ALL_CATEGORY).toString() });
    }
    const hasKeyword = this.keyword.trim().length > 0;
    if (hasKeyword || this.advanceSearch !== -1) {
      params.push({ key: 'f_search', value: hasKeyword ? this.keyword : '' });
    }
    if (this.pageIndex !== 0) {
      params.push({ key: 'page', value: this.pageIndex.toString() });
    }
    this.appendAdvanceParams(params);
    return params;
  }

  private buildFilterParams(): QueryParam[] {
    const params: QueryParam[] = [];
    if (this.pageIndex !== 0) {
      params.push({ key: 'page', value: this.pageIndex.toString() });
    }
    params.push({ key: 'f_search', value: this.keyword });
    return params;
  }

  private buildPopularParams(): QueryParam[] {
    const params: QueryParam[] = [];
    if (this.category !== GalleryCategory.None) {
      params.push({ key: 'f_cats', value: ((~this.category) & ALL_CATEGORY).toString() });
    }
    if (this.pageIndex !== 0) {
      params.push({ key: 'page', value: this.pageIndex.toString() });
    }
    this.appendAdvanceParams(params);
    return params;
  }

  private buildPathSearchParams(): QueryParam[] {
    const params: QueryParam[] = [];
    if (this.category !== GalleryCategory.None) {
      params.push({ key: 'f_cats', value: ((~this.category) & ALL_CATEGORY).toString() });
    }
    this.appendAdvanceParams(params);
    return params;
  }

  private appendAdvanceParams(params: QueryParam[]): void {
    if (this.advanceSearch === -1) {
      return;
    }
    if (this.includeAdvSearchParam) {
      params.push({ key: 'advsearch', value: '1' });
    }
    appendFlagParam(params, this.advanceSearch, 0x1, 'f_sname');
    appendFlagParam(params, this.advanceSearch, 0x2, 'f_stags');
    appendFlagParam(params, this.advanceSearch, 0x4, 'f_sdesc');
    appendFlagParam(params, this.advanceSearch, 0x8, 'f_storr');
    appendFlagParam(params, this.advanceSearch, 0x10, 'f_sto');
    appendFlagParam(params, this.advanceSearch, 0x20, 'f_sdt1');
    appendFlagParam(params, this.advanceSearch, 0x40, 'f_sdt2');
    appendFlagParam(params, this.advanceSearch, 0x80, 'f_sh');
    appendFlagParam(params, this.advanceSearch, 0x100, 'f_sfl');
    appendFlagParam(params, this.advanceSearch, 0x200, 'f_sfu');
    appendFlagParam(params, this.advanceSearch, 0x400, 'f_sft');
    if (this.minRating !== -1) {
      params.push({ key: 'f_sr', value: 'on' });
      params.push({ key: 'f_srdd', value: this.minRating.toString() });
    }
    if (this.pageFrom !== -1 || this.pageTo !== -1) {
      params.push({ key: 'f_sp', value: 'on' });
      params.push({ key: 'f_spf', value: this.pageFrom !== -1 ? this.pageFrom.toString() : '' });
      params.push({ key: 'f_spt', value: this.pageTo !== -1 ? this.pageTo.toString() : '' });
    }
  }
}

export class FavListUrlBuilder {
  static readonly FAV_CAT_ALL: number = -1;
  static readonly FAV_CAT_LOCAL: number = -2;

  index: number = 0;
  keyword: string = '';
  favCat: number = FavListUrlBuilder.FAV_CAT_ALL;

  static isValidFavCat(favCat: number): boolean {
    return favCat >= 0 && favCat <= 9;
  }

  build(site: GallerySite = GallerySite.E): string {
    const params: QueryParam[] = [];
    if (FavListUrlBuilder.isValidFavCat(this.favCat)) {
      params.push({ key: 'favcat', value: this.favCat.toString() });
    }
    if (this.keyword.trim().length > 0) {
      params.push({ key: 'f_search', value: this.keyword });
      params.push({ key: 'sn', value: 'on' });
      params.push({ key: 'st', value: 'on' });
      params.push({ key: 'sf', value: 'on' });
    }
    if (this.index > 0) {
      params.push({ key: 'page', value: this.index.toString() });
    }
    return buildUrl(EhUrl.getFavoritesUrl(site), params);
  }
}

export function buildUrl(base: string, params: QueryParam[]): string {
  if (params.length === 0) {
    return base;
  }

  const separator = base.indexOf('?') >= 0 ? '&' : '?';
  const queryParts: string[] = [];
  for (let i = 0; i < params.length; i++) {
    queryParts.push(encodeURIComponent(params[i].key) + '=' + encodeURIComponent(params[i].value));
  }
  return base + separator + queryParts.join('&');
}

export function buildJumpSeekUrl(url: string, appendParam: string): string {
  if (url.length === 0 || appendParam.length === 0) {
    return url;
  }
  const seekPattern = /([?&])seek=\d+-\d+-\d+/;
  const jumpPattern = /([?&])jump=\d[ymwd]/;
  if (seekPattern.test(url)) {
    return url.replace(seekPattern, (_match: string, prefix: string): string => prefix + appendParam);
  }
  if (jumpPattern.test(url)) {
    return url.replace(jumpPattern, (_match: string, prefix: string): string => prefix + appendParam);
  }
  return url + (url.indexOf('?') >= 0 ? '&' : '?') + appendParam;
}

function buildPathUrl(host: string, segment: string, value: string, pageIndex: number): string {
  let url = host + segment + '/' + encodeURIComponent(value);
  if (pageIndex !== 0) {
    url += '/' + pageIndex.toString();
  }
  return url;
}

function buildTopListUrl(site: GallerySite, follow: string, pageIndex: number): string {
  if (pageIndex < 0 || pageIndex >= 200) {
    return '127.0.0.1:8888';
  }
  const params: QueryParam[] = parseQuery(follow);
  if (pageIndex > 0) {
    params.push({ key: 'p', value: pageIndex.toString() });
  }
  return buildUrl(EhUrl.getTopListUrl(site), params);
}

function parseQuery(query: string): QueryParam[] {
  const normalized = query.startsWith('?') ? query.substring(1) : query;
  const params: QueryParam[] = [];
  if (normalized.length === 0) {
    return params;
  }

  const pairs = normalized.split('&');
  for (let i = 0; i < pairs.length; i++) {
    const index = pairs[i].indexOf('=');
    if (index < 0) {
      params.push({ key: pairs[i], value: '' });
    } else {
      params.push({
        key: safeDecode(pairs[i].substring(0, index)),
        value: safeDecode(pairs[i].substring(index + 1))
      });
    }
  }
  return params;
}

function appendFlagParam(params: QueryParam[], flags: number, flag: number, key: string): void {
  if ((flags & flag) !== 0) {
    params.push({ key: key, value: 'on' });
  }
}

function safeDecode(value: string): string {
  try {
    return decodeURIComponent(value.replace(/\+/g, '%20'));
  } catch (error) {
    return '';
  }
}
