import { webview } from '@kit.ArkWeb';
import { ehCookieStore } from '../services/EhCookieStore';
import { EhHttpClient, SignInResult } from '../services/EhHttpClient';
import { EhUrl } from '../services/EhUrl';
import { applyAppChromeImmersiveMode } from '../services/EhWindowImmersive';
import { LANGUAGE_REVISION_KEY } from '../shared/EhShared';
import { themeFieldBackground, themeOnPrimaryText, themePageBackground, themePrimaryColor, themePrimaryText, themeSecondaryText, themeSuccessText, themeSurface, themeTransparentColor } from '../shared/EhTheme';
import { SessionMode, uiText, uiStatusText, getAbilityContext } from '../shared/EhShared';
import { AppSubToolbar } from './NavigationComponents';

@Component
export struct SessionScene {
  private client: EhHttpClient = new EhHttpClient();
  private webController: webview.WebviewController = new webview.WebviewController();

  @State mode: SessionMode = SessionMode.Password;
  @State username: string = '';
  @State password: string = '';
  @State cookieInput: string = '';
  @State memberId: string = '';
  @State passHash: string = '';
  @State igneous: string = '';
  @State signingIn: boolean = false;
  @State webCookieCaptured: boolean = false;
  @State webUrl: string = EhUrl.URL_SIGN_IN;
  @State statusText: string = 'Sign in with an E-Hentai forum account';
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @Prop initialMode: SessionMode = SessionMode.Password;
  onBack: () => void = () => {};
  onSignedIn: () => void = () => {};

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    this.mode = this.initialMode;
    this.cookieInput = ehCookieStore.getEditableCookieHeader();
    const context = getAbilityContext();
    if (context !== undefined) {
      ehCookieStore.ensureLoaded(context).then(() => {
        this.cookieInput = ehCookieStore.getEditableCookieHeader();
        this.syncCookieFieldsFromInput(this.cookieInput, false);
        this.statusText = ehCookieStore.hasCookies() ? 'Persisted Cookie loaded' : 'No Cookie saved';
      }).catch((error: Error) => {
        this.statusText = 'Cookie load failed: ' + error.message;
      });
    }
  }

  private switchMode(mode: SessionMode): void {
    this.mode = mode;
    if (mode === SessionMode.Password) {
      this.statusText = 'Sign in with an E-Hentai forum account';
    } else if (mode === SessionMode.Cookie) {
      this.statusText = 'Enter ipb_member_id and ipb_pass_hash, or paste a full Cookie header';
    } else {
      this.statusText = 'Finish login in the web page; Cookie will be captured automatically';
      this.webCookieCaptured = false;
    }
  }

  private modeTitle(): string {
    if (this.mode === SessionMode.Cookie) {
      return 'Cookie Sign In';
    }
    if (this.mode === SessionMode.Web) {
      return 'Web Sign In';
    }
    return 'Sign in';
  }

  private handleBack(): void {
    if (this.mode !== this.initialMode) {
      this.switchMode(this.initialMode);
      return;
    }
    this.onBack();
  }

  private signInWithPassword(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Ability context is not ready';
      return;
    }
    if (this.signingIn) {
      return;
    }
    if (this.username.trim().length === 0) {
      this.statusText = 'Username cannot be empty';
      return;
    }
    if (this.password.length === 0) {
      this.statusText = 'Password cannot be empty';
      return;
    }

    this.signingIn = true;
    this.statusText = 'Signing in...';
    this.client.signIn(this.username.trim(), this.password).then((result: SignInResult) => {
      this.signingIn = false;
      if (!result.ok) {
        this.statusText = 'Sign in failed: ' + result.message;
        return;
      }

      ehCookieStore.save(context).then(() => {
        this.cookieInput = ehCookieStore.getEditableCookieHeader();
        this.statusText = result.message;
        this.onSignedIn();
      }).catch((error: Error) => {
        this.statusText = 'Signed in but Cookie save failed: ' + error.message;
      });
    }).catch((error: Error) => {
      this.signingIn = false;
      this.statusText = 'Sign in failed: ' + error.message;
    });
  }

  private prepareWebSignIn(): void {
    clearAllWebCookies();
    this.webCookieCaptured = false;
    const context = getAbilityContext();
    if (context === undefined) {
      ehCookieStore.clear();
      this.enterWebSignIn();
      return;
    }
    ehCookieStore.clearPersisted(context).then(() => {
      this.enterWebSignIn();
    }).catch((error: Error) => {
      this.statusText = 'Cookie clear failed: ' + error.message;
    });
  }

  private enterWebSignIn(): void {
    try {
      webview.WebCookieManager.configCookieSync(EhUrl.HOST_E, 'nw=1; path=/', true);
      webview.WebCookieManager.configCookieSync(EhUrl.HOST_EX, 'nw=1; path=/', true);
    } catch (error) {
    }
    this.switchMode(SessionMode.Web);
    this.statusText = 'Finish login in the web page; Cookie will be captured automatically';
  }

  private checkWebCookie(url: string): void {
    if (this.webCookieCaptured) {
      return;
    }

    const cookieHeader = collectWebCookies(url, true);
    if (cookieHeader.length > 0) {
      ehCookieStore.setCookieHeader(cookieHeader);
      this.cookieInput = ehCookieStore.getEditableCookieHeader();
    }
    if (!hasLoginCookie(cookieHeader)) {
      this.statusText = cookieHeader.length > 0 ? 'Web verification Cookie captured; waiting for login...' :
        'Waiting for web login...';
      return;
    }

    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Web Cookie found, but context is not ready';
      return;
    }

    this.webCookieCaptured = true;
    ehCookieStore.setCookieHeader(cookieHeader);
    ehCookieStore.save(context).then(() => {
      this.cookieInput = ehCookieStore.getEditableCookieHeader();
      this.statusText = 'Web Cookie captured';
      clearWebCookies(true);
      this.onSignedIn();
    }).catch((error: Error) => {
      this.webCookieCaptured = false;
      this.statusText = 'Web Cookie save failed: ' + error.message;
    });
  }

  private saveCookie(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Ability context is not ready';
      return;
    }

    const cookieHeader = this.buildCookieHeader();
    if (!this.validateCookieFields()) {
      return;
    }
    ehCookieStore.setCookieHeader(cookieHeader);
    ehCookieStore.save(context).then(() => {
      this.cookieInput = ehCookieStore.getEditableCookieHeader();
      this.statusText = ehCookieStore.hasCookies() ? 'Cookie saved' : 'Empty Cookie saved';
      if (ehCookieStore.hasCookies()) {
        this.onSignedIn();
      }
    }).catch((error: Error) => {
      this.statusText = 'Cookie save failed: ' + error.message;
    });
  }

  private buildCookieHeader(): string {
    const parsed = parseCookieIdentity(this.cookieInput);
    const memberId = this.memberId.trim().length > 0 ? this.memberId.trim() : parsed.memberId;
    const passHash = this.passHash.trim().length > 0 ? this.passHash.trim() : parsed.passHash;
    const igneous = this.igneous.trim().length > 0 ? this.igneous.trim() : parsed.igneous;

    const parts: string[] = [];
    if (memberId.length > 0) {
      parts.push('ipb_member_id=' + memberId);
    }
    if (passHash.length > 0) {
      parts.push('ipb_pass_hash=' + passHash);
    }
    if (igneous.length > 0) {
      parts.push('igneous=' + igneous);
    }
    return parts.join('; ');
  }

  private syncCookieFieldsFromInput(value: string, showStatus: boolean): void {
    const parsed = parseCookieIdentity(value);
    this.memberId = parsed.memberId;
    this.passHash = parsed.passHash;
    this.igneous = parsed.igneous;
    if (showStatus) {
      const changed = parsed.memberId.length > 0 || parsed.passHash.length > 0 || parsed.igneous.length > 0;
      this.statusText = changed ? 'Cookie fields detected' : 'No known Cookie fields detected';
    }
  }

  private validateCookieFields(): boolean {
    const id = this.memberId.trim();
    const hash = this.passHash.trim();
    if (id.length === 0) {
      this.statusText = 'ipb_member_id is empty';
      return false;
    }
    if (hash.length === 0) {
      this.statusText = 'ipb_pass_hash is empty';
      return false;
    }
    if (!checkIpbMemberId(id)) {
      this.statusText = 'ipb_member_id should contain digits only';
      return false;
    }
    if (!checkIpbPassHash(hash)) {
      this.statusText = 'ipb_pass_hash should be 32 lowercase letters or digits';
      return false;
    }
    return true;
  }

  private clearCookie(): void {
    clearAllWebCookies();
    const context = getAbilityContext();
    if (context === undefined) {
      ehCookieStore.clear();
      this.cookieInput = '';
      this.memberId = '';
      this.passHash = '';
      this.igneous = '';
      this.statusText = 'Cookie cleared in memory';
      return;
    }

    ehCookieStore.clearPersisted(context).then(() => {
      this.cookieInput = '';
      this.memberId = '';
      this.passHash = '';
      this.igneous = '';
      this.statusText = 'Cookie cleared';
    }).catch((error: Error) => {
      this.statusText = 'Cookie clear failed: ' + error.message;
    });
  }

  build() {
    Column() {
      AppSubToolbar({
        title: uiText(this.modeTitle()),
        onBack: () => {
          this.handleBack();
        }
      })
      if (this.mode === SessionMode.Web) {
        this.WebSignInPanel()
      } else if (this.mode === SessionMode.Cookie) {
        this.CookieSignInPanel()
      } else {
        this.PasswordSignInPanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }

  @Builder
  private PasswordSignInPanel() {
    Scroll() {
      Column() {
        SignInMark({ label: 'EH' })

        Column() {
          TextInput({ text: this.username, placeholder: uiText('Username') })
            .height(46)
            .width('100%')
            .fontColor(themePrimaryText())
            .placeholderColor(themeSecondaryText())
            .caretColor(themePrimaryColor())
            .backgroundColor(themeFieldBackground())
            .onChange((value: string) => {
              this.username = value;
            })
          TextInput({ text: this.password, placeholder: uiText('Password') })
            .height(46)
            .width('100%')
            .margin({ top: 10 })
            .type(InputType.Password)
            .fontColor(themePrimaryText())
            .placeholderColor(themeSecondaryText())
            .caretColor(themePrimaryColor())
            .backgroundColor(themeFieldBackground())
            .onChange((value: string) => {
              this.password = value;
            })
        }
        .width('100%')
        .constraintSize({ maxWidth: 420 })
        .margin({ top: 8 })

        Text(uiStatusText(this.statusText))
          .fontSize(13)
          .fontColor(themeSuccessText())
          .textAlign(TextAlign.Center)
          .width('100%')
          .constraintSize({ maxWidth: 420 })
          .margin({ top: 12 })

        Row() {
          Button(uiText('Register'))
            .type(ButtonType.Normal)
            .fontColor(themePrimaryColor())
            .backgroundColor(themeTransparentColor())
            .layoutWeight(1)
          Button(this.signingIn ? uiText('Signing in...') : uiText('Sign in'))
            .type(ButtonType.Normal)
            .fontColor(themePrimaryColor())
            .fontWeight(FontWeight.Bold)
            .backgroundColor(themeTransparentColor())
            .layoutWeight(1)
            .enabled(!this.signingIn)
            .onClick(() => {
              this.signInWithPassword();
            })
        }
        .width('100%')
        .constraintSize({ maxWidth: 520 })
        .margin({ top: 22 })

        Text(uiText('Sign in via WebView'))
          .fontSize(14)
          .fontColor(themePrimaryColor())
          .margin({ top: 8 })
          .onClick(() => {
            this.prepareWebSignIn();
          })
        Text(uiText('Sign in via Cookies'))
          .fontSize(14)
          .fontColor(themePrimaryColor())
          .margin({ top: 10 })
          .onClick(() => {
            this.switchMode(SessionMode.Cookie);
          })
        Text(uiText('Guest mode'))
          .fontSize(14)
          .fontColor(themePrimaryColor())
          .margin({ top: 10, bottom: 18 })
          .onClick(() => {
            this.onSignedIn();
          })
      }
      .alignItems(HorizontalAlign.Center)
      .width('100%')
      .padding(20)
      .backgroundColor(themePageBackground())
    }
    .layoutWeight(1)
    .width('100%')
    .backgroundColor(themePageBackground())
  }

  @Builder
  private CookieSignInPanel() {
    Column() {
      Scroll() {
        Column() {
          SignInMark({ label: 'CK' })

          Text(uiText('Use this when password login needs captcha, or when importing an ExHentai session.'))
            .fontSize(13)
            .fontColor(themeSecondaryText())
            .lineHeight(20)
            .width('100%')
            .constraintSize({ maxWidth: 420 })

          TextInput({ text: this.memberId, placeholder: 'ipb_member_id' })
            .height(46)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .margin({ top: 14 })
            .fontColor(themePrimaryText())
            .placeholderColor(themeSecondaryText())
            .caretColor(themePrimaryColor())
            .backgroundColor(themeFieldBackground())
            .onChange((value: string) => {
              this.memberId = value;
            })
          TextInput({ text: this.passHash, placeholder: 'ipb_pass_hash' })
            .height(46)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .margin({ top: 10 })
            .fontColor(themePrimaryText())
            .placeholderColor(themeSecondaryText())
            .caretColor(themePrimaryColor())
            .backgroundColor(themeFieldBackground())
            .onChange((value: string) => {
              this.passHash = value;
            })
          TextInput({ text: this.igneous, placeholder: 'igneous' })
            .height(46)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .margin({ top: 10 })
            .fontColor(themePrimaryText())
            .placeholderColor(themeSecondaryText())
            .caretColor(themePrimaryColor())
            .backgroundColor(themeFieldBackground())
            .onChange((value: string) => {
              this.igneous = value;
            })
          TextArea({ text: this.cookieInput, placeholder: uiText('Full Cookie header') })
            .height(116)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .fontSize(13)
            .margin({ top: 12 })
            .fontColor(themePrimaryText())
            .placeholderColor(themeSecondaryText())
            .caretColor(themePrimaryColor())
            .backgroundColor(themeFieldBackground())
            .onChange((value: string) => {
              this.cookieInput = value;
              this.syncCookieFieldsFromInput(value, true);
            })
          Text(uiStatusText(this.statusText))
            .fontSize(13)
            .fontColor(themeSuccessText())
            .textAlign(TextAlign.Center)
            .width('100%')
            .constraintSize({ maxWidth: 420 })
            .margin({ top: 12 })
        }
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        .padding({ left: 20, right: 20, top: 12, bottom: 20 })
      }
      .layoutWeight(1)
      .width('100%')

      Row() {
        Button(uiText('Clear'))
          .type(ButtonType.Normal)
          .fontColor(themePrimaryColor())
          .backgroundColor(themeTransparentColor())
          .layoutWeight(1)
          .onClick(() => {
            this.clearCookie();
          })
        Button(uiText('OK'))
          .type(ButtonType.Normal)
          .fontColor(themePrimaryColor())
          .fontWeight(FontWeight.Bold)
          .backgroundColor(themeTransparentColor())
          .layoutWeight(1)
          .onClick(() => {
            this.saveCookie();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 12 })
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(themePageBackground())
  }

  @Builder
  private WebSignInPanel() {
    Column() {
      Text(uiStatusText(this.statusText))
        .fontSize(13)
        .fontColor(themeSecondaryText())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(themeSurface())

      Web({ src: this.webUrl, controller: this.webController, incognitoMode: true })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .backgroundColor(Color.Transparent)
        .onPageEnd((event: OnPageEndEvent) => {
          this.checkWebCookie(event.url);
        })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(themePageBackground())
  }
}

@Component
export struct SignInMark {
  label: string = '';

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.label)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(themeOnPrimaryText())
        .textAlign(TextAlign.Center)
    }
    .width(72)
    .height(72)
    .backgroundColor(themePrimaryColor())
    .borderRadius(18)
  }
}

export function collectWebCookies(currentUrl: string, incognito: boolean = false): string {
  const names: string[] = [];
  const values: string[] = [];
  absorbCookieHeader(currentUrl, names, values, incognito);
  absorbCookieHeader(EhUrl.HOST_E, names, values, incognito);
  absorbCookieHeader(EhUrl.HOST_EX, names, values, incognito);
  absorbCookieHeader(EhUrl.FORUM_ORIGIN, names, values, incognito);
  absorbCookieHeader(EhUrl.URL_SIGN_IN, names, values, incognito);

  const parts: string[] = [];
  for (let i = 0; i < names.length; i++) {
    parts.push(names[i] + '=' + values[i]);
  }
  return parts.join('; ');
}

export function syncCookieHeaderToWebView(url: string, cookieHeader: string, incognito: boolean = false): void {
  if (url.length === 0 || cookieHeader.trim().length === 0) {
    return;
  }

  const names: string[] = [];
  const values: string[] = [];
  absorbCookieHeaderText(cookieHeader, names, values);
  for (let i = 0; i < names.length; i++) {
    if (names[i].length === 0 || values[i].length === 0) {
      continue;
    }
    try {
      webview.WebCookieManager.configCookieSync(url, names[i] + '=' + values[i] + '; path=/', incognito);
    } catch (error) {
    }
  }
  if (!incognito) {
    try {
      webview.WebCookieManager.saveCookieSync();
    } catch (error) {
    }
  }
}

export function clearWebCookies(incognito: boolean): void {
  try {
    webview.WebCookieManager.clearAllCookiesSync(incognito);
  } catch (error) {
  }
}

export function clearAllWebCookies(): void {
  clearWebCookies(false);
  clearWebCookies(true);
}

interface CookieIdentity {
  memberId: string;
  passHash: string;
  igneous: string;
}

function parseCookieIdentity(text: string): CookieIdentity {
  const names: string[] = [];
  const values: string[] = [];
  absorbCookieHeaderText(text, names, values);
  return {
    memberId: findCookieValue('ipb_member_id', names, values),
    passHash: findCookieValue('ipb_pass_hash', names, values),
    igneous: findCookieValue('igneous', names, values)
  };
}

function absorbCookieHeaderText(text: string, names: string[], values: string[]): void {
  if (text.trim().length === 0) {
    return;
  }

  const rows = text.replace(/\r/g, '\n').split('\n');
  for (let i = 0; i < rows.length; i++) {
    absorbCookieRow(rows[i], names, values);
  }
}

function absorbCookieRow(row: string, names: string[], values: string[]): void {
  const trimmed = row.trim();
  if (trimmed.length === 0) {
    return;
  }

  const colon = trimmed.indexOf(':');
  if (colon > 0) {
    const key = trimmed.substring(0, colon).trim();
    const value = trimmed.substring(colon + 1).trim();
    if (isKnownCookieName(key) && value.length > 0) {
      upsertCookiePair(key, value, names, values);
      return;
    }
  }

  const normalized = trimmed.startsWith('Cookie:') ? trimmed.substring(7).trim() : trimmed;
  const pieces = normalized.split(';');
  for (let i = 0; i < pieces.length; i++) {
    const piece = pieces[i].trim();
    const eq = piece.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const key = piece.substring(0, eq).trim();
    const value = piece.substring(eq + 1).trim();
    if (key.length === 0 || value.length === 0 || isCookieAttribute(key)) {
      continue;
    }
    upsertCookiePair(key, value, names, values);
  }
}

function findCookieValue(name: string, names: string[], values: string[]): string {
  for (let i = 0; i < names.length; i++) {
    if (names[i] === name) {
      return values[i];
    }
  }
  return '';
}

function absorbCookieHeader(url: string, names: string[], values: string[], incognito: boolean): void {
  if (url.length === 0) {
    return;
  }

  let header = '';
  try {
    header = webview.WebCookieManager.fetchCookieSync(url, incognito);
  } catch (error) {
    header = '';
  }
  if (header.length === 0) {
    return;
  }

  const pairs = header.split(';');
  for (let i = 0; i < pairs.length; i++) {
    const pair = pairs[i].trim();
    const index = pair.indexOf('=');
    if (index <= 0) {
      continue;
    }
    upsertCookiePair(pair.substring(0, index), pair.substring(index + 1), names, values);
  }
}

function upsertCookiePair(name: string, value: string, names: string[], values: string[]): void {
  for (let i = 0; i < names.length; i++) {
    if (names[i] === name) {
      values[i] = value;
      return;
    }
  }
  names.push(name);
  values.push(value);
}

export function hasLoginCookie(cookieHeader: string): boolean {
  return cookieHeader.indexOf('ipb_member_id=') >= 0 && cookieHeader.indexOf('ipb_pass_hash=') >= 0;
}

function isKnownCookieName(name: string): boolean {
  return name === 'ipb_member_id' || name === 'ipb_pass_hash' || name === 'igneous' ||
    name === 'cf_clearance' || name === 'sk' || name === 'yay' || name === 'sl';
}

function isCookieAttribute(name: string): boolean {
  const lower = name.toLowerCase();
  return lower === 'domain' || lower === 'path' || lower === 'expires' || lower === 'max-age' ||
    lower === 'secure' || lower === 'httponly' || lower === 'samesite';
}

function checkIpbMemberId(id: string): boolean {
  if (id.length === 0) {
    return false;
  }
  for (let i = 0; i < id.length; i++) {
    const code = id.charCodeAt(i);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}

function checkIpbPassHash(hash: string): boolean {
  if (hash.length !== 32) {
    return false;
  }
  for (let i = 0; i < hash.length; i++) {
    const code = hash.charCodeAt(i);
    const digit = code >= 48 && code <= 57;
    const lower = code >= 97 && code <= 122;
    if (!digit && !lower) {
      return false;
    }
  }
  return true;
}
