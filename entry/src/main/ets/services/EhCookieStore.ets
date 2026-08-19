import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ehSettingsStore } from './EhSettingsStore';

const PREFERENCES_NAME: string = 'ehviewer_session';
const COOKIE_KEY: string = 'cookie_header';
const KEY_IPB_MEMBER_ID: string = 'ipb_member_id';
const KEY_IPB_PASS_HASH: string = 'ipb_pass_hash';
const KEY_IGNEOUS: string = 'igneous';
const KEY_CONTENT_WARNING: string = 'nw';
const KEY_UCONFIG: string = 'uconfig';
const UCONFIG_IMAGE_SIZE_KEY: string = 'xr';
const UCONFIG_ALWAYS_ORIGINAL_KEY: string = 'oi';
const CONTENT_WARNING_NOT_SHOW: string = '1';

export interface CookieEntry {
  name: string;
  value: string;
}

export interface CookieHeaderOptions {
  includeContentWarning?: boolean;
  includeUConfig?: boolean;
  includeIgneous?: boolean;
  forceUConfig?: boolean;
  imagePreferenceUConfig?: boolean;
}

export interface CookieDebugSummary {
  url: string;
  names: string[];
  headerLength: number;
  hasLogin: boolean;
  hasIgneous: boolean;
  hasContentWarning: boolean;
  hasUConfig: boolean;
}

export class EhCookieStore {
  private cookies: CookieEntry[] = [];
  private loaded: boolean = false;
  private ensurePromise: Promise<void> | null = null;

  setCookieHeader(cookieHeader: string): void {
    this.cookies = [];
    const pairs = cookieHeader.split(';');
    for (let i = 0; i < pairs.length; i++) {
      const pair = pairs[i].trim();
      const index = pair.indexOf('=');
      if (index <= 0) {
        continue;
      }
      this.upsert(pair.substring(0, index), pair.substring(index + 1));
    }
  }

  absorbSetCookieHeader(setCookieHeader: string): void {
    if (setCookieHeader.length === 0) {
      return;
    }

    const lines = setCookieHeader.split('\n');
    for (let i = 0; i < lines.length; i++) {
      this.absorbOne(lines[i]);
    }
  }

  getCookieHeader(): string {
    if (!this.hasCookies()) {
      return this.buildGuestCookieHeader();
    }
    return this.buildCookieHeader({ includeContentWarning: true, includeUConfig: true });
  }

  getCookieHeaderWithOptions(options: CookieHeaderOptions): string {
    if (!this.hasCookies()) {
      return this.buildGuestCookieHeader();
    }
    return this.buildCookieHeader(options);
  }

  getCookieHeaderForUrl(url: string, options?: CookieHeaderOptions): string {
    const eSite = isEHost(url);
    const uploadSite = isUploadHost(url);
    const includeContentWarning = eSite || uploadSite || options?.includeContentWarning !== false;
    const includeUConfig = uploadSite ? false : (options?.forceUConfig === true ? true :
      (eSite ? false : options?.includeUConfig !== false));
    if (!this.hasCookies()) {
      return includeContentWarning ? this.buildGuestCookieHeader() : '';
    }
    return this.buildCookieHeader({
      includeContentWarning: includeContentWarning,
      includeUConfig: includeUConfig,
      imagePreferenceUConfig: options?.imagePreferenceUConfig
    });
  }

  getCookieDebugSummaryForUrl(url: string, options?: CookieHeaderOptions): CookieDebugSummary {
    const header = this.getCookieHeaderForUrl(url, options);
    const names: string[] = [];
    const pairs = header.split(';');
    for (let i = 0; i < pairs.length; i++) {
      const pair = pairs[i].trim();
      const index = pair.indexOf('=');
      if (index <= 0) {
        continue;
      }
      names.push(pair.substring(0, index));
    }
    return {
      url: url,
      names: names,
      headerLength: header.length,
      hasLogin: names.indexOf(KEY_IPB_MEMBER_ID) >= 0 && names.indexOf(KEY_IPB_PASS_HASH) >= 0,
      hasIgneous: names.indexOf('igneous') >= 0,
      hasContentWarning: names.indexOf(KEY_CONTENT_WARNING) >= 0,
      hasUConfig: names.indexOf(KEY_UCONFIG) >= 0
    };
  }

  getStoredCookieHeader(): string {
    return this.buildCookieHeader({ includeContentWarning: false, includeUConfig: true, includeIgneous: false });
  }

  getTransferCookieHeader(): string {
    return this.buildCookieHeader({ includeContentWarning: false, includeUConfig: true, includeIgneous: false });
  }

  setTransferCookieHeader(cookieHeader: string): void {
    this.setCookieHeader(cookieHeader);
    this.removeCookie(KEY_IGNEOUS);
  }

  getEditableCookieHeader(): string {
    const names = [KEY_IPB_MEMBER_ID, KEY_IPB_PASS_HASH, KEY_IGNEOUS];
    const pairs: string[] = [];
    for (let i = 0; i < names.length; i++) {
      const value = this.cookieValue(names[i]);
      if (value.length > 0) {
        pairs.push(names[i] + '=' + value);
      }
    }
    return pairs.join('; ');
  }

  private buildCookieHeader(options: CookieHeaderOptions): string {
    const includeContentWarning = options.includeContentWarning !== false;
    const includeUConfig = options.includeUConfig !== false;
    const includeIgneous = options.includeIgneous !== false;
    const pairs: string[] = [];
    let hasContentWarning = false;
    let existingUConfig = '';
    for (let i = 0; i < this.cookies.length; i++) {
      if (this.cookies[i].name === KEY_CONTENT_WARNING) {
        hasContentWarning = true;
      }
      if (this.cookies[i].name === KEY_UCONFIG) {
        existingUConfig = this.cookies[i].value;
      }
      if (!includeContentWarning && this.cookies[i].name === KEY_CONTENT_WARNING) {
        continue;
      }
      if (!includeIgneous && this.cookies[i].name === KEY_IGNEOUS) {
        continue;
      }
      if (this.cookies[i].name === KEY_UCONFIG) {
        if (!includeUConfig) {
          continue;
        }
        if (options.imagePreferenceUConfig === true) {
          continue;
        }
      }
      pairs.push(this.cookies[i].name + '=' + this.cookies[i].value);
    }
    if (includeUConfig && options.imagePreferenceUConfig === true) {
      const uconfig = imagePreferenceUConfig(existingUConfig);
      if (uconfig.length > 0) {
        pairs.push(KEY_UCONFIG + '=' + uconfig);
      }
    }
    if (includeContentWarning && !hasContentWarning) {
      pairs.push(KEY_CONTENT_WARNING + '=' + CONTENT_WARNING_NOT_SHOW);
    }
    return pairs.join('; ');
  }

  private buildGuestCookieHeader(): string {
    return KEY_CONTENT_WARNING + '=' + CONTENT_WARNING_NOT_SHOW;
  }

  hasCookies(): boolean {
    return this.hasCookie(KEY_IPB_MEMBER_ID) && this.hasCookie(KEY_IPB_PASS_HASH);
  }

  clear(): void {
    this.cookies = [];
    this.loaded = true;
  }

  async ensureLoaded(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    if (this.ensurePromise !== null) {
      await this.ensurePromise;
      return;
    }
    this.ensurePromise = this.load(context);
    try {
      await this.ensurePromise;
      this.loaded = true;
    } finally {
      this.ensurePromise = null;
    }
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const value = await prefs.get(COOKIE_KEY, '');
      if (typeof value === 'string' && value.length > 0) {
        this.setCookieHeader(value);
        const persisted = this.getStoredCookieHeader();
        if (persisted !== value) {
          await prefs.put(COOKIE_KEY, persisted);
          await prefs.flush();
        }
      }
    } catch (error) {
      throw new Error(String(error));
    }
  }

  async save(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(COOKIE_KEY, this.getStoredCookieHeader());
      await prefs.flush();
    } catch (error) {
      throw new Error(String(error));
    }
  }

  async clearPersisted(context: common.UIAbilityContext): Promise<void> {
    this.clear();
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(COOKIE_KEY, '');
      await prefs.flush();
    } catch (error) {
      throw new Error(String(error));
    }
  }

  private absorbOne(rawCookie: string): void {
    const firstPart = rawCookie.split(';')[0].trim();
    const index = firstPart.indexOf('=');
    if (index <= 0) {
      return;
    }
    const name = firstPart.substring(0, index);
    const value = firstPart.substring(index + 1);
    if (this.isInvalidNetworkIdentityCookie(name, value)) {
      return;
    }
    this.upsert(name, value);
  }

  private upsert(name: string, value: string): void {
    if (name.length === 0) {
      return;
    }
    if (this.isInvalidNetworkIdentityCookie(name, value)) {
      return;
    }
    for (let i = 0; i < this.cookies.length; i++) {
      if (this.cookies[i].name === name) {
        this.cookies[i].value = value;
        return;
      }
    }
    this.cookies.push({ name: name, value: value });
  }

  private hasCookie(name: string): boolean {
    return this.cookieValue(name).length > 0;
  }

  private removeCookie(name: string): void {
    const retained: CookieEntry[] = [];
    for (let i = 0; i < this.cookies.length; i++) {
      if (this.cookies[i].name !== name) {
        retained.push(this.cookies[i]);
      }
    }
    this.cookies = retained;
  }

  private cookieValue(name: string): string {
    for (let i = 0; i < this.cookies.length; i++) {
      if (this.cookies[i].name === name && this.cookies[i].value.length > 0) {
        return this.cookies[i].value;
      }
    }
    return '';
  }

  private isInvalidNetworkIdentityCookie(name: string, value: string): boolean {
    if (name !== KEY_IPB_MEMBER_ID && name !== KEY_IPB_PASS_HASH) {
      return false;
    }
    if (!this.hasCookie(name)) {
      return false;
    }
    const normalized = value.trim().toLowerCase();
    return normalized.length === 0 || normalized === '0' || normalized === 'deleted';
  }
}

function imagePreferenceUConfig(current: string): string {
  const imageSize = normalizedImageSizeSetting(ehSettingsStore.getValue('image_size', 'Auto'));
  const alwaysOriginal = imageSize === 'Original' ? 'y' : 'n';
  const xres = imageSize === 'Original' ? 'a' : imageSizeValue(imageSize);
  const segments = current.length > 0 ? current.split('-') : [];
  upsertUConfigSegment(segments, UCONFIG_IMAGE_SIZE_KEY, xres);
  upsertUConfigSegment(segments, UCONFIG_ALWAYS_ORIGINAL_KEY, alwaysOriginal);
  return segments.join('-');
}

function normalizedImageSizeSetting(value: string): string {
  if (value === '780x' || value === '780') {
    return '780x';
  }
  if (value === '980x' || value === '980') {
    return '780x';
  }
  if (value === '1280x' || value === '1280') {
    return '1280x';
  }
  if (value === '1600x' || value === '1600') {
    return '1600x';
  }
  if (value === '2400x' || value === '2400') {
    return '2400x';
  }
  if (value === 'Original') {
    return 'Original';
  }
  return 'Auto';
}

function imageSizeValue(value: string): string {
  if (value === '780x') {
    return '780';
  }
  if (value === '1280x') {
    return '1280';
  }
  if (value === '1600x') {
    return '1600';
  }
  if (value === '2400x') {
    return '2400';
  }
  return 'a';
}

function upsertUConfigSegment(segments: string[], key: string, value: string): void {
  const prefix = key + '_';
  for (let i = 0; i < segments.length; i++) {
    if (segments[i].indexOf(prefix) === 0) {
      segments[i] = prefix + value;
      return;
    }
  }
  segments.push(prefix + value);
}

function isEHost(url: string): boolean {
  const host = requestHost(url);
  return host === 'e-hentai.org' || host.endsWith('.e-hentai.org');
}

function isUploadHost(url: string): boolean {
  const host = requestHost(url);
  return host === 'upld.e-hentai.org' || host === 'upld.exhentai.org';
}

function requestHost(url: string): string {
  const match = /^https?:\/\/([^\/?#]+)/i.exec(url);
  return match === null ? '' : match[1].toLowerCase();
}

export const ehCookieStore: EhCookieStore = new EhCookieStore();
