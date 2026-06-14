import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const PREFERENCES_NAME: string = 'ehviewer_session';
const COOKIE_KEY: string = 'cookie_header';
const KEY_IPB_MEMBER_ID: string = 'ipb_member_id';
const KEY_IPB_PASS_HASH: string = 'ipb_pass_hash';
const KEY_CONTENT_WARNING: string = 'nw';
const CONTENT_WARNING_NOT_SHOW: string = '1';

export interface CookieEntry {
  name: string;
  value: string;
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
    const pairs: string[] = [];
    let hasContentWarning = false;
    for (let i = 0; i < this.cookies.length; i++) {
      if (this.cookies[i].name === KEY_CONTENT_WARNING) {
        hasContentWarning = true;
      }
      pairs.push(this.cookies[i].name + '=' + this.cookies[i].value);
    }
    if (!hasContentWarning) {
      pairs.push(KEY_CONTENT_WARNING + '=' + CONTENT_WARNING_NOT_SHOW);
    }
    return pairs.join('; ');
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
    this.upsert(firstPart.substring(0, index), firstPart.substring(index + 1));
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
}

export const ehCookieStore: EhCookieStore = new EhCookieStore();
