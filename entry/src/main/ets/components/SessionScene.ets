import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { GallerySite } from '../model/GalleryModels';
import { ehCookieStore } from '../services/EhCookieStore';
import { EhHttpClient } from '../services/EhHttpClient';
import { ehSettingsStore } from '../services/EhSettingsStore';
import {
  configureEhWebDns,
  EH_WEB_COMPATIBILITY_SCRIPTS,
  loadEhWebUrlWithAndroidCompatibility
} from '../services/EhWebRuntime';
import { EhUrl } from '../services/EhUrl';
import { applyAppChromeImmersiveMode } from '../services/EhWindowImmersive';
import { LANGUAGE_REVISION_KEY, setActiveBackHandler } from '../shared/EhShared';
import { themeFieldBackground, themeOnPrimaryText, themePageBackground, themePrimaryColor, themePrimaryText, themeSecondaryText, themeSuccessText, themeSurface, themeTransparentColor } from '../shared/EhTheme';
import { SessionMode, uiText, uiStatusText, getAbilityContext } from '../shared/EhShared';
import { AppSubToolbar } from './NavigationComponents';
import { ConfirmActionOverlay } from './ConfirmActionOverlay';

@Component
export struct SessionScene {
  private client: EhHttpClient = new EhHttpClient();
  private webController: webview.WebviewController = new webview.WebviewController();
  private passwordWebController: webview.WebviewController = new webview.WebviewController();
  private passwordWebSubmitted: boolean = false;
  private passwordWebCheckingForm: boolean = false;
  private passwordWebLoadingAccountConfiguration: boolean = false;
  private passwordWebSubmitAttempts: number = 0;
  private passwordWebRetryTimer: number = -1;
  private passwordWebDeadlineTimer: number = -1;

  @State mode: SessionMode = SessionMode.Password;
  @State username: string = '';
  @State password: string = '';
  @State cookieInput: string = '';
  @State memberId: string = '';
  @State passHash: string = '';
  @State igneous: string = '';
  @State signingIn: boolean = false;
  @State passwordWebActive: boolean = false;
  @State passwordWebVerificationVisible: boolean = false;
  @State webCookieCaptured: boolean = false;
  @State webUrl: string = EhUrl.URL_SIGN_IN;
  @State statusText: string = 'Sign in with an E-Hentai forum account';
  @State clearCookieConfirmationVisible: boolean = false;
  @StorageProp(LANGUAGE_REVISION_KEY) languageRevision: number = 0;
  @Prop initialMode: SessionMode = SessionMode.Password;
  onBack: () => void = () => {};
  onSignedIn: () => void = () => {};

  aboutToAppear(): void {
    applyAppChromeImmersiveMode();
    setActiveBackHandler(() => this.handleSystemBack());
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

  aboutToDisappear(): void {
    this.clearPasswordWebTimers();
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

  private handleSystemBack(): boolean {
    if (this.clearCookieConfirmationVisible) {
      this.clearCookieConfirmationVisible = false;
      return true;
    }
    if (this.passwordWebVerificationVisible) {
      this.failPasswordWebSignIn('Sign in cancelled');
      return true;
    }
    this.handleBack();
    return true;
  }

  private signInWithPassword(): void {
    if (getAbilityContext() === undefined) {
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
    this.statusText = 'Preparing secure sign in...';
    this.passwordWebSubmitted = false;
    this.passwordWebCheckingForm = false;
    this.passwordWebLoadingAccountConfiguration = false;
    this.passwordWebVerificationVisible = false;
    this.passwordWebSubmitAttempts = 0;
    this.clearPasswordWebTimers();
    clearWebSessionCookies(false);
    ehCookieStore.clearLoginPreservingBrowserState();
    configureWebCookieAccess();
    const cookieHeader = ehCookieStore.getStoredCookieHeader();
    syncCookieHeaderToWebView(EhUrl.HOST_E, cookieHeader, false);
    syncCookieHeaderToWebView(EhUrl.HOST_EX, cookieHeader, false);
    syncCookieHeaderToWebView(EhUrl.FORUM_ORIGIN, cookieHeader, false);
    this.passwordWebDeadlineTimer = setTimeout(() => {
      if (this.signingIn) {
        console.warn('SessionScene: password Web sign-in timed out');
        this.failPasswordWebSignIn('Sign in timed out; continue in web sign in');
        this.prepareWebSignIn('Direct sign in needs visible site verification. Continue signing in on the web page.');
      }
    }, 120000) as number;
    if (this.passwordWebActive) {
      loadEhWebUrlWithAndroidCompatibility(this.passwordWebController, EhUrl.SIGN_IN_REFERER);
    } else {
      this.passwordWebActive = true;
    }
  }

  private handlePasswordWebPageEnd(url: string): void {
    if (!this.signingIn) {
      return;
    }
    console.info('SessionScene: password Web page finished: ' + sanitizeWebLogUrl(url));
    if (this.passwordWebLoadingAccountConfiguration) {
      captureEhAccountWebCookies(url);
      if (ehCookieStore.hasAccountConfiguration()) {
        console.info('SessionScene: account configuration Cookie captured');
      } else {
        console.warn('SessionScene: account configuration Cookie was not returned by Web');
      }
      this.finishPasswordWebSignIn();
      return;
    }
    const cookieHeader = collectWebCookies(url, false);
    if (hasLoginCookie(cookieHeader)) {
      console.info('SessionScene: password Web sign-in Cookie captured');
      ehCookieStore.setCookieHeaderPreservingIgneous(cookieHeader);
      this.passwordWebLoadingAccountConfiguration = true;
      this.statusText = 'Signed in; loading account configuration...';
      const accountConfigurationUrl = this.accountConfigurationUrl();
      prepareEhAccountWebViewCookies(accountConfigurationUrl);
      try {
        this.passwordWebController.loadUrl(accountConfigurationUrl);
      } catch (error) {
        this.finishPasswordWebSignIn();
      }
      return;
    }
    if (!this.passwordWebSubmitted) {
      this.attemptPasswordWebSubmit();
      return;
    }
    this.inspectPasswordWebResult();
  }

  private attemptPasswordWebSubmit(): void {
    if (!this.signingIn || this.passwordWebSubmitted || this.passwordWebCheckingForm) {
      return;
    }
    this.passwordWebCheckingForm = true;
    this.passwordWebSubmitAttempts++;
    const script = buildWebPasswordSubmitScript(this.username.trim(), this.password);
    this.passwordWebController.runJavaScript(script).then((result: string) => {
      this.passwordWebCheckingForm = false;
      if (!this.signingIn) {
        return;
      }
      if (result.indexOf('submitted') >= 0) {
        console.info('SessionScene: password Web form submitted');
        this.passwordWebSubmitted = true;
        this.passwordWebVerificationVisible = false;
        this.statusText = 'Signing in...';
        return;
      }
      if (result.indexOf('verification') >= 0) {
        this.passwordWebVerificationVisible = true;
        this.statusText = 'Waiting for site verification...';
      }
      this.retryPasswordWebSubmit();
    }).catch(() => {
      this.passwordWebCheckingForm = false;
      this.retryPasswordWebSubmit();
    });
  }

  private retryPasswordWebSubmit(): void {
    if (!this.signingIn) {
      return;
    }
    if (this.passwordWebSubmitAttempts >= 220) {
      console.warn('SessionScene: password Web form was not available after retries');
      this.failPasswordWebSignIn('Site verification did not finish; continue in web sign in');
      this.prepareWebSignIn('Direct sign in needs visible site verification. Continue signing in on the web page.');
      return;
    }
    if (this.passwordWebRetryTimer !== -1) {
      clearTimeout(this.passwordWebRetryTimer);
    }
    this.passwordWebRetryTimer = setTimeout(() => {
      this.passwordWebRetryTimer = -1;
      this.attemptPasswordWebSubmit();
    }, 500) as number;
  }

  private inspectPasswordWebResult(): void {
    this.passwordWebController.runJavaScript(
      "document.body ? document.body.innerText : ''"
    ).then((result: string) => {
      if (!this.signingIn) {
        return;
      }
      if (hasLoginCookie(collectWebCookies(EhUrl.FORUM_ORIGIN, false))) {
        this.handlePasswordWebPageEnd(EhUrl.FORUM_ORIGIN);
        return;
      }
      const message = webPasswordSignInError(result);
      if (message.length > 0) {
        this.failPasswordWebSignIn('Sign in failed: ' + message);
        return;
      }
      this.passwordWebSubmitted = false;
      this.retryPasswordWebSubmit();
    }).catch(() => {
      this.passwordWebSubmitted = false;
      this.retryPasswordWebSubmit();
    });
  }

  private finishPasswordWebSignIn(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.failPasswordWebSignIn('Web Cookie found, but context is not ready');
      return;
    }
    this.clearPasswordWebTimers();
    this.passwordWebActive = false;
    this.passwordWebSubmitted = false;
    this.passwordWebLoadingAccountConfiguration = false;
    this.passwordWebVerificationVisible = false;
    this.signingIn = false;
    this.completeSignedIn(context, 'Signed in');
  }

  private failPasswordWebSignIn(status: string): void {
    this.clearPasswordWebTimers();
    this.passwordWebActive = false;
    this.passwordWebSubmitted = false;
    this.passwordWebCheckingForm = false;
    this.passwordWebLoadingAccountConfiguration = false;
    this.passwordWebVerificationVisible = false;
    this.signingIn = false;
    this.statusText = status;
  }

  private clearPasswordWebTimers(): void {
    if (this.passwordWebRetryTimer !== -1) {
      clearTimeout(this.passwordWebRetryTimer);
      this.passwordWebRetryTimer = -1;
    }
    if (this.passwordWebDeadlineTimer !== -1) {
      clearTimeout(this.passwordWebDeadlineTimer);
      this.passwordWebDeadlineTimer = -1;
    }
  }

  private accountConfigurationUrl(): string {
    const site = ehSettingsStore.getValue('gallery_site', 'E-Hentai') === 'ExHentai' ?
      GallerySite.Ex : GallerySite.E;
    return EhUrl.getUConfigUrl(site);
  }

  private prepareWebSignIn(status: string = 'Finish login in the web page; Cookie will be captured automatically'): void {
    clearWebSessionCookies(false);
    clearWebSessionCookies(true);
    this.webCookieCaptured = false;
    this.statusText = status;
    const context = getAbilityContext();
    if (context === undefined) {
      ehCookieStore.clearLoginPreservingBrowserState();
      this.enterWebSignIn(status);
      return;
    }
    ehCookieStore.clearLoginPreservingBrowserState();
    ehCookieStore.save(context).then(() => {
      this.enterWebSignIn(status);
    }).catch((error: Error) => {
      this.statusText = 'Cookie clear failed: ' + error.message;
    });
  }

  private completeSignedIn(context: common.UIAbilityContext, successStatus: string): void {
    this.statusText = 'Signed in; loading account configuration...';
    let refresh: Promise<void> = new Promise<void>((resolve) => resolve());
    if (!ehCookieStore.hasAccountConfiguration()) {
      refresh = this.client.refreshAccountConfiguration().catch((configurationError: Error) => {
        console.warn('SessionScene: account configuration refresh failed: ' + configurationError.message);
      });
    }
    refresh.then(() => {
      return ehCookieStore.save(context);
    }).then(() => {
      this.cookieInput = ehCookieStore.getEditableCookieHeader();
      this.statusText = successStatus;
      this.onSignedIn();
    }).catch((saveError: Error) => {
      this.webCookieCaptured = false;
      this.statusText = 'Signed in but Cookie save failed: ' + saveError.message;
    });
  }

  private enterWebSignIn(status: string = 'Finish login in the web page; Cookie will be captured automatically'): void {
    configureWebCookieAccess();
    const cookieHeader = ehCookieStore.getStoredCookieHeader();
    syncCookieHeaderToWebView(EhUrl.HOST_E, cookieHeader, false);
    syncCookieHeaderToWebView(EhUrl.HOST_EX, cookieHeader, false);
    syncCookieHeaderToWebView(EhUrl.FORUM_ORIGIN, cookieHeader, false);
    try {
      webview.WebCookieManager.configCookieSync(EhUrl.HOST_E, 'nw=1; path=/', false);
      webview.WebCookieManager.configCookieSync(EhUrl.HOST_EX, 'nw=1; path=/', false);
      webview.WebCookieManager.saveCookieSync();
    } catch (error) {
    }
    this.switchMode(SessionMode.Web);
    this.statusText = status;
  }

  private checkWebCookie(url: string): void {
    if (this.webCookieCaptured) {
      return;
    }

    const cookieHeader = collectWebCookies(url, false);
    if (cookieHeader.length > 0) {
      ehCookieStore.setCookieHeaderPreservingIgneous(cookieHeader);
      this.cookieInput = ehCookieStore.getEditableCookieHeader();
    }
    if (!hasLoginCookie(cookieHeader)) {
      this.statusText = hasCookieName(cookieHeader, 'cf_clearance') ?
        'Site verification complete; waiting for login...' :
        (cookieHeader.length > 0 ? 'Web verification Cookie captured; waiting for login...' :
          'Waiting for web login...');
      return;
    }

    const context = getAbilityContext();
    if (context === undefined) {
      this.statusText = 'Web Cookie found, but context is not ready';
      return;
    }

    this.webCookieCaptured = true;
    ehCookieStore.setCookieHeaderPreservingIgneous(cookieHeader);
    this.completeSignedIn(context, 'Web Cookie captured');
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
    if (ehCookieStore.hasCookies()) {
      this.completeSignedIn(context, 'Cookie saved');
      return;
    }
    ehCookieStore.save(context).then(() => {
      this.cookieInput = ehCookieStore.getEditableCookieHeader();
      this.statusText = 'Empty Cookie saved';
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

  private requestClearCookie(): void {
    this.clearCookieConfirmationVisible = true;
  }

  private clearCookie(): void {
    this.clearCookieConfirmationVisible = false;
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
    Stack() {
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

      if (this.passwordWebActive) {
        Column() {
          Row() {
            Text(uiStatusText(this.statusText))
              .fontSize(13)
              .fontColor(themeSecondaryText())
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Button(uiText('Cancel'))
              .type(ButtonType.Normal)
              .fontColor(themePrimaryColor())
              .backgroundColor(themeTransparentColor())
              .onClick(() => {
                this.failPasswordWebSignIn('Sign in cancelled');
              })
          }
          .width('100%')
          .height(this.passwordWebVerificationVisible ? 48 : 0)
          .padding({ left: 12, right: 8 })
          .opacity(this.passwordWebVerificationVisible ? 1 : 0)
          .backgroundColor(themeSurface())

          Web({ src: '', controller: this.passwordWebController, incognitoMode: false })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .javaScriptOnDocumentStart(EH_WEB_COMPATIBILITY_SCRIPTS)
            .width('100%')
            .layoutWeight(1)
            .opacity(this.passwordWebVerificationVisible ? 1 : 0.01)
            .hitTestBehavior(this.passwordWebVerificationVisible ? HitTestMode.Default : HitTestMode.None)
            .onControllerAttached(() => {
              console.info('SessionScene: password Web controller attached');
              loadEhWebUrlWithAndroidCompatibility(this.passwordWebController, EhUrl.SIGN_IN_REFERER);
            })
            .onPageEnd((event: OnPageEndEvent) => {
              this.handlePasswordWebPageEnd(event.url);
            })
        }
        .width(this.passwordWebVerificationVisible ? '100%' : 2)
        .height(this.passwordWebVerificationVisible ? '100%' : 2)
        .opacity(this.passwordWebVerificationVisible ? 1 : 0.01)
        .backgroundColor(themePageBackground())
        .zIndex(10)
      }

      if (this.clearCookieConfirmationVisible) {
        ConfirmActionOverlay({
          title: 'Clear Cookie',
          message: 'Saved identity cookies and web cookies will be removed.',
          confirmLabel: 'Clear',
          onCancel: () => {
            this.clearCookieConfirmationVisible = false;
          },
          onConfirm: () => {
            this.clearCookie();
          }
        })
          .zIndex(20)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
      }
    }
    .width('100%')
    .height('100%')
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
            this.requestClearCookie();
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

      Web({ src: '', controller: this.webController, incognitoMode: false })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .javaScriptOnDocumentStart(EH_WEB_COMPATIBILITY_SCRIPTS)
        .backgroundColor(Color.Transparent)
        .onControllerAttached(() => {
          loadEhWebUrlWithAndroidCompatibility(this.webController, this.webUrl);
        })
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

export function captureEhAccountWebCookies(url: string): boolean {
  const cookieHeader = collectWebCookies(url, false);
  if (!hasLoginCookie(cookieHeader)) {
    return false;
  }
  ehCookieStore.setCookieHeaderPreservingIgneous(cookieHeader);
  console.info('EhAccountWeb: Cookie captured, has account configuration=' +
    ehCookieStore.hasAccountConfiguration().toString());
  return true;
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

export function prepareEhAccountWebViewCookies(url: string): void {
  configureWebCookieAccess();
  clearWebSessionCookies(false);
  const cookieHeader = ehCookieStore.getCookieHeader();
  if (cookieHeader.length === 0) {
    return;
  }

  syncCookieHeaderToWebView(url, cookieHeader, false);
  syncCookieHeaderToWebView(EhUrl.HOST_E, cookieHeader, false);
  syncCookieHeaderToWebView(EhUrl.HOST_EX, cookieHeader, false);
  syncCookieHeaderToWebView(EhUrl.FORUM_ORIGIN, cookieHeader, false);
  try {
    webview.WebCookieManager.configCookieSync(EhUrl.HOST_E, 'nw=1; path=/', false);
    webview.WebCookieManager.configCookieSync(EhUrl.HOST_EX, 'nw=1; path=/', false);
    webview.WebCookieManager.saveCookieSync();
  } catch (error) {
  }
}

export function configureWebCookieAccess(): void {
  configureEhWebDns();
  try {
    webview.WebCookieManager.putAcceptCookieEnabled(true);
  } catch (error) {
  }
  try {
    webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true);
  } catch (error) {
  }
}

export function clearWebCookies(incognito: boolean): void {
  try {
    webview.WebCookieManager.clearAllCookiesSync(incognito);
  } catch (error) {
  }
}

export function clearWebSessionCookies(incognito: boolean): void {
  const urls: string[] = [EhUrl.HOST_E, EhUrl.HOST_EX, EhUrl.FORUM_ORIGIN, EhUrl.URL_SIGN_IN];
  const cookieNames: string[] = ['ipb_member_id', 'ipb_pass_hash', 'igneous'];
  for (let i = 0; i < urls.length; i++) {
    const domain = webCookieDomain(urls[i]);
    for (let j = 0; j < cookieNames.length; j++) {
      expireWebCookie(urls[i], cookieNames[j] + '=; Max-Age=0; path=/', incognito);
      if (domain.length > 0) {
        expireWebCookie(urls[i], cookieNames[j] + '=; Max-Age=0; Domain=.' + domain + '; path=/', incognito);
      }
    }
  }
  if (!incognito) {
    try {
      webview.WebCookieManager.saveCookieSync();
    } catch (error) {
    }
  }
}

function expireWebCookie(url: string, cookie: string, incognito: boolean): void {
  try {
    webview.WebCookieManager.configCookieSync(url, cookie, incognito, true);
  } catch (error) {
  }
}

function webCookieDomain(url: string): string {
  return url.indexOf(EhUrl.DOMAIN_EX) >= 0 ? EhUrl.DOMAIN_EX :
    (url.indexOf(EhUrl.DOMAIN_E) >= 0 ? EhUrl.DOMAIN_E : '');
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

function hasCookieName(cookieHeader: string, name: string): boolean {
  const pairs = cookieHeader.split(';');
  for (let i = 0; i < pairs.length; i++) {
    const pair = pairs[i].trim();
    const index = pair.indexOf('=');
    if (index > 0 && pair.substring(0, index).trim() === name) {
      return true;
    }
  }
  return false;
}

function isKnownCookieName(name: string): boolean {
  return name === 'ipb_member_id' || name === 'ipb_pass_hash' || name === 'igneous' ||
    name === 'cf_clearance' || name === 'uconfig' || name === 'nw' ||
    name === 'sk' || name === 'yay' || name === 'sl';
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

function buildWebPasswordSubmitScript(username: string, password: string): string {
  const escapedUsername = JSON.stringify(username);
  const escapedPassword = JSON.stringify(password);
  return "(() => { const user = document.querySelector('input[name=\\\"UserName\\\"]'); " +
    "const pass = document.querySelector('input[name=\\\"PassWord\\\"]'); " +
    "if (!user || !pass) return 'missing'; user.value = " + escapedUsername + "; pass.value = " +
    escapedPassword + "; const cookieDate = document.querySelector('input[name=\\\"CookieDate\\\"]'); " +
    "if (cookieDate) cookieDate.value = '1'; const temporary = " +
    "document.querySelector('input[name=\\\"temporary_https\\\"]'); if (temporary) temporary.value = 'off'; " +
    "const verification = document.querySelector('input[name=\\\"cf-turnstile-response\\\"]'); " +
    "const challenge = document.querySelector('.cf-turnstile, iframe[src*=\\\"challenges.cloudflare.com\\\"]'); " +
    "if ((verification && !verification.value) || (challenge && !verification)) return 'verification'; " +
    "const form = user.form || pass.form || document.querySelector('form'); if (!form) return 'missing'; " +
    "setTimeout(() => HTMLFormElement.prototype.submit.call(form), 0); return 'submitted'; })();";
}

function sanitizeWebLogUrl(url: string): string {
  const queryIndex = url.indexOf('?');
  if (queryIndex >= 0) {
    return url.substring(0, queryIndex);
  }
  return url;
}

function decodeWebJavaScriptString(raw: string): string {
  let text = raw.trim();
  if (!text.startsWith('"') || !text.endsWith('"')) {
    return text;
  }
  return text.substring(1, text.length - 1)
    .replace(/\\n/g, '\n')
    .replace(/\\r/g, '\n')
    .replace(/\\"/g, '"')
    .replace(/\\\\/g, '\\');
}

function webPasswordSignInError(raw: string): string {
  const text = decodeWebJavaScriptString(raw);
  const normalized = text.replace(/\r/g, '\n');
  const lines = normalized.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    const lower = line.toLowerCase();
    if (lower.indexOf('incorrect') >= 0 || lower.indexOf('password') >= 0 && lower.indexOf('error') >= 0 ||
      lower.indexOf('not recognized') >= 0 || lower.indexOf('account has been locked') >= 0) {
      return line.substring(0, Math.min(240, line.length));
    }
  }
  return '';
}
