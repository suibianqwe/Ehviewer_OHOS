import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const PREFERENCES_NAME: string = 'ehviewer_session';
const COOKIE_KEY: string = 'cookie_header';
const KEY_IPB_MEMBER_ID: string = 'ipb_member_id';
const KEY_IPB_PASS_HASH: string = 'ipb_pass_hash';
const KEY_CONTENT_WARNING: string = 'nw';
const KEY_UCONFIG: string = 'uconfig';
const CONTENT_WARNING_NOT_SHOW: string = '1';

export interface CookieEntry {
  name: string;
  value: string;
}

export interface CookieHeaderOptions {
  includeContentWarning?: boolean;
  includeUConfig?: boolean;
}

export class EhCookieStore {
  private cookies: CookieEntry[] = [];

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
    const includeContentWarning = eSite || options?.includeContentWarning !== false;
    const includeUConfig = eSite ? false : options?.includeUConfig !== false;
    if (!this.hasCookies()) {
      return includeContentWarning ? this.buildGuestCookieHeader() : '';
    }
    return this.buildCookieHeader({
      includeContentWarning: includeContentWarning,
      includeUConfig: includeUConfig
    });
  }

  getStoredCookieHeader(): string {
    return this.buildCookieHeader({ includeContentWarning: false, includeUConfig: true });
  }

  getEditableCookieHeader(): string {
    return this.buildCookieHeader({ includeContentWarning: false, includeUConfig: true });
  }

  private buildCookieHeader(options: CookieHeaderOptions): string {
    const includeContentWarning = options.includeContentWarning !== false;
    const includeUConfig = options.includeUConfig !== false;
    const pairs: string[] = [];
    let hasContentWarning = false;
    for (let i = 0; i < this.cookies.length; i++) {
      if (this.cookies[i].name === KEY_CONTENT_WARNING) {
        hasContentWarning = true;
      }
      if (!includeContentWarning && this.cookies[i].name === KEY_CONTENT_WARNING) {
        continue;
      }
      if (!includeUConfig && this.cookies[i].name === KEY_UCONFIG) {
        continue;
      }
      pairs.push(this.cookies[i].name + '=' + this.cookies[i].value);
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
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const value = await prefs.get(COOKIE_KEY, '');
      if (typeof value === 'string' && value.length > 0) {
        this.setCookieHeader(value);
      }
    } catch (error) {
      throw new Error(String(error));
    }
  }

  async save(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(COOKIE_KEY, this.getCookieHeader());
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
    for (let i = 0; i < this.cookies.length; i++) {
      if (this.cookies[i].name === name) {
        this.cookies[i].value = value;
        return;
      }
    }
    this.cookies.push({ name: name, value: value });
  }

  private hasCookie(name: string): boolean {
    for (let i = 0; i < this.cookies.length; i++) {
      if (this.cookies[i].name === name && this.cookies[i].value.length > 0) {
        return true;
      }
    }
    return false;
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

export const ehCookieStore: EhCookieStore = new EhCookieStore();

function isEHost(url: string): boolean {
  const host = requestHost(url);
  return host === 'e-hentai.org' || host.endsWith('.e-hentai.org');
}

function requestHost(url: string): string {
  const match = /^https?:\/\/([^\/?#]+)/i.exec(url);
  return match === null ? '' : match[1].toLowerCase();
}
