import { GallerySite } from '../model/GalleryModels';
import { EhHttpClient, EhHttpResponse } from './EhHttpClient';
import { CookieDebugSummary, ehCookieStore } from './EhCookieStore';
import { EhUrl } from './EhUrl';

export enum MyTagKind {
  Watched = 'watched',
  Hidden = 'hidden'
}

export interface MyTagItem {
  id: number;
  tag: string;
  watched: boolean;
  hidden: boolean;
  color: string;
  weight: string;
}

export interface MyTagSetOption {
  id: string;
  name: string;
  count: number;
  selected: boolean;
}

export interface MyTagSuggestion {
  tag: string;
  display: string;
}

export interface MyTagsPage {
  url: string;
  site: GallerySite;
  apiUrl: string;
  apiUid: number;
  apiKey: string;
  tagsetId: string;
  tagsetName: string;
  tagsetEnabled: boolean;
  tagsetColor: string;
  tagsets: MyTagSetOption[];
  watched: MyTagItem[];
  hidden: MyTagItem[];
  all: MyTagItem[];
}

interface FormField {
  key: string;
  value: string;
}

export class EhMyTagsService {
  private client: EhHttpClient = new EhHttpClient();

  async load(site: GallerySite): Promise<MyTagsPage> {
    try {
      return await this.loadSite(site);
    } catch (error) {
      const fallbackSite = site === GallerySite.Ex ? GallerySite.E : GallerySite.Ex;
      try {
        return await this.loadSite(fallbackSite);
      } catch (fallbackError) {
        throw new Error(error instanceof Error ? error.message : String(error));
      }
    }
  }

  private async loadSite(site: GallerySite): Promise<MyTagsPage> {
    const url = this.myTagsUrl(site);
    const response = await this.client.getText(url, url, 0);
    logMyTagsResponse('load', site, url, response);
    this.ensureOk(response, 'Load My Tags failed');
    const page = parseMyTagsPage(response.body, url, site);
    logMyTagsParse('load', page);
    this.ensureMyTagsPage(page, response.body);
    return page;
  }

  async suggestTags(site: GallerySite, page: MyTagsPage | null, text: string): Promise<MyTagSuggestion[]> {
    const query = normalizeSuggestText(text);
    if (query.replace(/^.*:/, '').length < 2) {
      return [];
    }
    const currentPage = page === null ? await this.load(site) : page;
    if (currentPage.apiUrl.length === 0) {
      return [];
    }
    const response = await this.client.postJson(currentPage.apiUrl, JSON.stringify({
      method: 'tagsuggest',
      text: query
    }), currentPage.url, originFromUrl(currentPage.url, site));
    logMyTagsResponse('suggest', currentPage.site, currentPage.apiUrl, response);
    this.ensureOk(response, 'Load tag suggestions failed');
    return parseTagSuggestions(response.body, query);
  }

  async saveTagsetSettings(site: GallerySite, page: MyTagsPage | null, enabled: boolean,
    color: string): Promise<MyTagsPage> {
    const currentPage = page === null ? await this.load(site) : page;
    const fields: FormField[] = [
      { key: 'tagset_action', value: 'update' },
      { key: 'tagset_name', value: '' },
      { key: 'tagset_color', value: normalizeColor(color) }
    ];
    if (enabled) {
      fields.push({ key: 'tagset_enable', value: 'on' });
    }
    const response = await this.client.postForm(currentPage.url, buildFormBody(fields), currentPage.url,
      originFromUrl(currentPage.url, site));
    logMyTagsResponse('saveTagset', currentPage.site, currentPage.url, response);
    this.ensureOk(response, 'Save My Tags settings failed');
    const nextPage = parseMyTagsPage(response.body, currentPage.url, currentPage.site);
    logMyTagsParse('saveTagset', nextPage);
    this.ensureMyTagsPage(nextPage, response.body);
    return nextPage;
  }

  async saveTag(site: GallerySite, page: MyTagsPage | null, tag: string, kind: MyTagKind): Promise<MyTagsPage> {
    const normalizedTag = normalizeTag(tag);
    if (normalizedTag.length === 0) {
      throw new Error('Enter a tag first');
    }
    const currentPage = page === null ? await this.load(site) : page;
    const existing = findTag(currentPage.all, normalizedTag);
    if (existing !== null) {
      await this.setExistingTagKind(site, currentPage, existing, kind);
      return this.load(currentPage.site);
    }
    return this.addTag(site, currentPage, normalizedTag, kind);
  }

  private async setExistingTagKind(site: GallerySite, page: MyTagsPage, item: MyTagItem,
    kind: MyTagKind): Promise<void> {
    if (page.apiUrl.length === 0 || page.apiUid <= 0 || page.apiKey.length === 0) {
      throw new Error('My Tags API key not found');
    }
    const payload = JSON.stringify({
      method: 'setusertag',
      apiuid: page.apiUid,
      apikey: page.apiKey,
      tagid: item.id,
      tagwatch: kind === MyTagKind.Watched ? 1 : 0,
      taghide: kind === MyTagKind.Hidden ? 1 : 0,
      tagcolor: item.color,
      tagweight: parseTagWeight(item.weight)
    });
    const response = await this.client.postJson(page.apiUrl, payload, page.url, originFromUrl(page.url, site));
    logMyTagsResponse('setTag', page.site, page.apiUrl, response);
    this.ensureOk(response, 'Save My Tags failed');
  }

  private async addTag(site: GallerySite, page: MyTagsPage, tag: string, kind: MyTagKind): Promise<MyTagsPage> {
    const url = page.url.length > 0 ? page.url : this.myTagsUrl(site);
    const fields: FormField[] = [
      { key: 'usertag_action', value: 'add' },
      { key: 'tagname_new', value: tag },
      { key: 'tagcolor_new', value: '' },
      { key: 'tagweight_new', value: '10' }
    ];
    if (kind === MyTagKind.Watched) {
      fields.push({ key: 'tagwatch_new', value: 'on' });
    } else {
      fields.push({ key: 'taghide_new', value: 'on' });
    }
    fields.push({ key: 'usertag_target', value: '0' });
    const response = await this.client.postForm(url, buildFormBody(fields), url, originFromUrl(url, site));
    logMyTagsResponse('addTag', page.site, url, response);
    this.ensureOk(response, 'Save My Tags failed');
    const nextPage = parseMyTagsPage(response.body, url, page.site);
    logMyTagsParse('addTag', nextPage);
    this.ensureMyTagsPage(nextPage, response.body);
    return nextPage;
  }

  private myTagsUrl(site: GallerySite): string {
    return EhUrl.getHost(site) + 'mytags';
  }

  private ensureOk(response: EhHttpResponse, prefix: string): void {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw new Error(prefix + ': HTTP ' + response.statusCode.toString());
    }
    const pageError = parsePageError(response.body);
    if (pageError.length > 0) {
      throw new Error(prefix + ': ' + pageError);
    }
  }

  private ensureMyTagsPage(page: MyTagsPage, body: string): void {
    if (page.apiUrl.length > 0 && page.apiUid > 0 && page.apiKey.length > 0 &&
      body.indexOf('id="usertag_form"') >= 0) {
      return;
    }
    if (body.indexOf('bounce_login') >= 0 || body.indexOf('act=Login') >= 0 ||
      body.indexOf('You are not currently logged in') >= 0) {
      throw new Error('My Tags page requires a valid signed-in session');
    }
    throw new Error('Cannot parse My Tags page');
  }
}

export const ehMyTagsService: EhMyTagsService = new EhMyTagsService();

export function parseMyTagsPage(html: string, url: string, site: GallerySite = GallerySite.E): MyTagsPage {
  const all = parseUserTags(html);
  const watched: MyTagItem[] = [];
  const hidden: MyTagItem[] = [];
  for (let i = 0; i < all.length; i++) {
    if (all[i].watched) {
      watched.push(all[i]);
    }
    if (all[i].hidden) {
      hidden.push(all[i]);
    }
  }
  return {
    url: url,
    site: site,
    apiUrl: matchStringVariable(html, 'api_url'),
    apiUid: matchNumberVariable(html, 'apiuid'),
    apiKey: matchStringVariable(html, 'apikey'),
    tagsetId: matchSelectedTagsetId(html),
    tagsetName: matchStringVariable(html, 'tagset_name'),
    tagsetEnabled: matchTagsetEnabled(html),
    tagsetColor: matchTagsetColor(html),
    tagsets: parseTagsetOptions(html),
    watched: watched,
    hidden: hidden,
    all: all
  };
}

function parseTagSuggestions(body: string, query: string): MyTagSuggestion[] {
  try {
    const obj = JSON.parse(body) as Record<string, Object>;
    const rawError = obj['error'];
    if (typeof rawError === 'string' && rawError.length > 0) {
      throw new Error(rawError);
    }
    const rawTags = obj['tags'];
    if (rawTags === undefined) {
      return [];
    }
    const tags = rawTags as Record<string, Object>;
    const keys = Object.keys(tags);
    const suggestions: MyTagSuggestion[] = [];
    const lowerQuery = query.toLowerCase();
    for (let i = 0; i < keys.length; i++) {
      const item = tags[keys[i]] as Record<string, Object>;
      const ns = stringValue(item['ns']);
      const tn = stringValue(item['tn']);
      if (ns.length === 0 || tn.length === 0) {
        continue;
      }
      const tag = ns + ':' + tn;
      const mappedNs = stringValue(item['mns']);
      const mappedTn = stringValue(item['mtn']);
      const mapped = mappedNs.length > 0 && mappedTn.length > 0 ? mappedNs + ':' + mappedTn : '';
      const value = mapped.length > 0 ? mapped : tag;
      if (value.toLowerCase().indexOf(lowerQuery) < 0 && tag.toLowerCase().indexOf(lowerQuery) < 0) {
        continue;
      }
      suggestions.push({
        tag: value,
        display: mapped.length > 0 ? tag + ' => ' + mapped : tag
      });
      if (suggestions.length >= 8) {
        break;
      }
    }
    return suggestions;
  } catch (error) {
    throw new Error(error instanceof Error ? error.message : 'Invalid tag suggestion response');
  }
}

function parseUserTags(html: string): MyTagItem[] {
  const result: MyTagItem[] = [];
  let offset = 0;
  while (offset >= 0 && offset < html.length) {
    const start = html.indexOf('<div id="usertag_', offset);
    if (start < 0) {
      break;
    }
    const idStart = start + '<div id="usertag_'.length;
    const idEnd = html.indexOf('"', idStart);
    if (idEnd < 0) {
      break;
    }
    const id = Number.parseInt(html.substring(idStart, idEnd), 10);
    const next = html.indexOf('<div id="usertag_', idEnd);
    const mass = html.indexOf('<div id="usertags_mass"', idEnd);
    const end = next >= 0 && (mass < 0 || next < mass) ? next : (mass >= 0 ? mass : html.length);
    const block = html.substring(start, end);
    offset = end;
    if (id <= 0 || Number.isNaN(id)) {
      continue;
    }
    const tag = decodeHtml(matchTagPreviewTitle(block, id));
    if (tag.length === 0) {
      continue;
    }
    result.push({
      id: id,
      tag: tag,
      watched: isInputChecked(block, 'tagwatch_' + id.toString()),
      hidden: isInputChecked(block, 'taghide_' + id.toString()),
      color: matchInputValue(block, 'tagcolor_' + id.toString()),
      weight: matchInputValue(block, 'tagweight_' + id.toString())
    });
  }
  return result;
}

function matchStringVariable(html: string, name: string): string {
  const re = new RegExp('var\\s+' + name + '\\s*=\\s*"([^"]*)"', 'i');
  const matched = re.exec(html);
  return matched === null ? '' : decodeHtml(matched[1]);
}

function matchNumberVariable(html: string, name: string): number {
  const re = new RegExp('var\\s+' + name + '\\s*=\\s*(\\d+)', 'i');
  const matched = re.exec(html);
  if (matched === null) {
    return 0;
  }
  const value = Number.parseInt(matched[1], 10);
  return Number.isNaN(value) ? 0 : value;
}

function matchSelectedTagsetId(html: string): string {
  const matched = /<option\s+value="([^"]+)"\s+selected=/i.exec(html);
  return matched === null ? '' : decodeHtml(matched[1]);
}

function parseTagsetOptions(html: string): MyTagSetOption[] {
  const result: MyTagSetOption[] = [];
  const selectMatched = /<select[^>]*onchange="change_tagset\(this\.value\)"[^>]*>([\s\S]*?)<\/select>/i.exec(html);
  if (selectMatched === null) {
    return result;
  }
  const optionRe = /<option\s+value="([^"]+)"([^>]*)>([\s\S]*?)<\/option>/gi;
  let matched: RegExpExecArray | null = optionRe.exec(selectMatched[1]);
  while (matched !== null) {
    const label = decodeHtml(stripTags(matched[3]));
    result.push({
      id: decodeHtml(matched[1]),
      name: label.replace(/\s*\(\d+\)\s*$/, ''),
      count: parseOptionCount(label),
      selected: matched[2].indexOf('selected') >= 0
    });
    matched = optionRe.exec(selectMatched[1]);
  }
  return result;
}

function matchTagsetEnabled(html: string): boolean {
  const matched = /id="tagset_enable"[^>]*checked/i.exec(html);
  return matched !== null;
}

function matchTagsetColor(html: string): string {
  const matched = /id="tagcolor"[^>]*value="([^"]*)"/i.exec(html);
  return matched === null ? '' : decodeHtml(matched[1]);
}

function matchAttribute(block: string, name: string): string {
  const re = new RegExp(name + '="([^"]*)"', 'i');
  const matched = re.exec(block);
  return matched === null ? '' : matched[1];
}

function matchTagPreviewTitle(block: string, id: number): string {
  const idText = id.toString();
  let re = new RegExp('id="tagpreview_' + escapeRegExp(idText) + '"[^>]*title="([^"]*)"', 'i');
  let matched = re.exec(block);
  if (matched !== null) {
    return matched[1];
  }
  re = new RegExp('title="([^"]*)"[^>]*id="tagpreview_' + escapeRegExp(idText) + '"', 'i');
  matched = re.exec(block);
  return matched === null ? '' : matched[1];
}

function isInputChecked(block: string, id: string): boolean {
  const tag = matchInputTag(block, id);
  return /(^|\s)checked(\s|=|\/|>|$)/i.test(tag);
}

function matchInputValue(block: string, id: string): string {
  const tag = matchInputTag(block, id);
  const matched = /value="([^"]*)"/i.exec(tag);
  return matched === null ? '' : decodeHtml(matched[1]);
}

function matchInputTag(block: string, id: string): string {
  const re = new RegExp('<input\\b[^>]*id="' + escapeRegExp(id) + '"[^>]*>', 'i');
  const matched = re.exec(block);
  return matched === null ? '' : matched[0];
}

function findTag(tags: MyTagItem[], tag: string): MyTagItem | null {
  const normalizedTag = normalizeTag(tag).toLowerCase();
  for (let i = 0; i < tags.length; i++) {
    if (normalizeTag(tags[i].tag).toLowerCase() === normalizedTag) {
      return tags[i];
    }
  }
  return null;
}

function normalizeTag(tag: string): string {
  return tag.trim().replace(/\s+/g, ' ');
}

function parseTagWeight(weight: string): number {
  const value = Number.parseInt(weight, 10);
  if (Number.isNaN(value)) {
    return 10;
  }
  return Math.max(-99, Math.min(999, value));
}

function normalizeSuggestText(text: string): string {
  let value = normalizeTag(text).replace(/["']/g, '').toLowerCase();
  if (/^(x|mix).*:/.test(value)) {
    value = value.replace(/^(x|mix).*:/, 'mixed:');
  } else if (/^(mis).*:/.test(value)) {
    value = value.replace(/^(mis).*:/, 'temp:');
  } else if (/^(co).*:/.test(value)) {
    value = value.replace(/^(co).*:/, 'cosplayer:');
  } else if (/^(lo).*:/.test(value)) {
    value = value.replace(/^(lo).*:/, 'location:');
  } else {
    value = value
      .replace(/^t.*:/, 'temp:')
      .replace(/^f.*:/, 'female:')
      .replace(/^m.*:/, 'male:')
      .replace(/^r.*:/, 'reclass:')
      .replace(/^l.*:/, 'language:')
      .replace(/^p.*:/, 'parody:')
      .replace(/^c.*:/, 'character:')
      .replace(/^g.*:/, 'group:')
      .replace(/^a.*:/, 'artist:')
      .replace(/^o.*:/, 'other:');
  }
  return value;
}

function normalizeColor(color: string): string {
  const value = color.trim().replace(/^#/, '').toUpperCase();
  if (value.length === 0) {
    return '';
  }
  return /^[0-9A-F]{6}$/.test(value) ? '#' + value : color.trim();
}

function parseOptionCount(label: string): number {
  const matched = /\((\d+)\)\s*$/.exec(label);
  if (matched === null) {
    return 0;
  }
  const count = Number.parseInt(matched[1], 10);
  return Number.isNaN(count) ? 0 : count;
}

function parsePageError(html: string): string {
  const matched = /<div\s+class="d">\s*<p>([^<]+)<\/p>/i.exec(html);
  return matched === null ? '' : decodeHtml(matched[1]);
}

function stripTags(html: string): string {
  return html.replace(/<[^>]+>/g, '');
}

function stringValue(value: Object | undefined): string {
  return typeof value === 'string' ? value : '';
}

function originFromUrl(url: string, fallbackSite: GallerySite): string {
  const matched = /^(https?:\/\/[^\/?#]+)/i.exec(url);
  return matched === null ? EhUrl.getReferer(fallbackSite) : matched[1];
}

function logMyTagsResponse(phase: string, site: GallerySite, url: string, response: EhHttpResponse): void {
  const body = response.body;
  const cookie: CookieDebugSummary = ehCookieStore.getCookieDebugSummaryForUrl(url);
  console.info('[MyTags] phase=' + phase +
    ' site=' + siteName(site) +
    ' url=' + url +
    ' status=' + response.statusCode.toString() +
    ' bodyLength=' + body.length.toString() +
    ' title="' + pageTitle(body) + '"' +
    ' hasForm=' + boolText(body.indexOf('id="usertag_form"') >= 0) +
    ' hasApiUrl=' + boolText(body.indexOf('var api_url') >= 0) +
    ' hasApiUid=' + boolText(body.indexOf('var apiuid') >= 0) +
    ' hasApiKey=' + boolText(body.indexOf('var apikey') >= 0) +
    ' hasBounceLogin=' + boolText(body.indexOf('bounce_login') >= 0 || body.indexOf('act=Login') >= 0) +
    ' cookieNames=' + cookie.names.join('|') +
    ' cookieLength=' + cookie.headerLength.toString() +
    ' cookieHasLogin=' + boolText(cookie.hasLogin) +
    ' cookieHasIgneous=' + boolText(cookie.hasIgneous) +
    ' cookieHasNw=' + boolText(cookie.hasContentWarning) +
    ' cookieHasUConfig=' + boolText(cookie.hasUConfig));
}

function logMyTagsParse(phase: string, page: MyTagsPage): void {
  const first = page.all.length > 0 ? page.all[0].tag : '';
  console.info('[MyTags] parse phase=' + phase +
    ' site=' + siteName(page.site) +
    ' tagset="' + page.tagsetName + '"' +
    ' tagsets=' + page.tagsets.length.toString() +
    ' all=' + page.all.length.toString() +
    ' watched=' + page.watched.length.toString() +
    ' hidden=' + page.hidden.length.toString() +
    ' first="' + first + '"');
}

function siteName(site: GallerySite): string {
  return site === GallerySite.Ex ? 'ExHentai' : 'E-Hentai';
}

function boolText(value: boolean): string {
  return value ? '1' : '0';
}

function pageTitle(html: string): string {
  const matched = /<title>([\s\S]*?)<\/title>/i.exec(html);
  if (matched === null) {
    return '';
  }
  return decodeHtml(stripTags(matched[1])).replace(/\s+/g, ' ').trim();
}

function buildFormBody(fields: FormField[]): string {
  const parts: string[] = [];
  for (let i = 0; i < fields.length; i++) {
    parts.push(encodeURIComponent(fields[i].key) + '=' + encodeURIComponent(fields[i].value));
  }
  return parts.join('&');
}

function decodeHtml(value: string): string {
  return value
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .trim();
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
