import {
  webview,
} from '@kit.ArkWeb';
import {
  deviceInfo,
} from '@kit.BasicServicesKit';
import {
  currentDnsOverHttpsUrl,
} from './EhNetworkConfig';

const LOG_TAG: string = 'EhWebRuntime';
export const EH_WEB_COMPATIBILITY_SCRIPTS: ScriptItem[] = [{
  script: "(() => { const names = ['RTCPeerConnection', 'webkitRTCPeerConnection']; " +
    "for (const name of names) { try { Object.defineProperty(globalThis, name, " +
    "{ configurable: false, get: () => undefined }); } catch (_) {} } })();",
  scriptRules: ['https://*.e-hentai.org', 'https://*.exhentai.org', 'https://*.cloudflare.com']
}];

export function configureEhWebDns(): void {
  const dohUrl = currentDnsOverHttpsUrl();
  if (dohUrl.length === 0) {
    return;
  }
  try {
    webview.WebviewController.setHttpDns(webview.SecureDnsMode.AUTO, dohUrl);
    console.info(LOG_TAG + ': ArkWeb HTTP DNS configured: ' + dohUrl);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(LOG_TAG + ': failed to configure ArkWeb HTTP DNS: ' + message);
  }
}

export function loadEhWebUrlWithAndroidCompatibility(controller: webview.WebviewController, url: string): void {
  try {
    const defaultUserAgent = controller.getUserAgent();
    const chromeVersion = extractChromeVersion(defaultUserAgent);
    const androidUserAgent = buildAndroidChromeUserAgent(chromeVersion);
    configureAndroidUserAgentMetadata(controller, androidUserAgent, chromeVersion);
    controller.setCustomUserAgent(androidUserAgent);
    console.info(LOG_TAG + ': Android-compatible Web user agent configured');
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(LOG_TAG + ': failed to configure Web user agent: ' + message);
  }
  try {
    controller.loadUrl(url);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(LOG_TAG + ': failed to load Web URL: ' + message);
  }
}

function configureAndroidUserAgentMetadata(controller: webview.WebviewController, userAgent: string,
  chromeVersion: string): void {
  if (deviceInfo.apiAvailable(24)) {
    const majorVersion = chromeVersion.split('.')[0];
    const chromiumBrand = createUserAgentBrand('Chromium', majorVersion, chromeVersion);
    const chromeBrand = createUserAgentBrand('Google Chrome', majorVersion, chromeVersion);
    if (chromiumBrand === null || chromeBrand === null) {
      return;
    }
    const metadata = new webview.UserAgentMetadata();
    metadata.setBrandVersionList([chromiumBrand, chromeBrand]);
    metadata.setFullVersion(chromeVersion);
    metadata.setPlatform('Android');
    metadata.setPlatformVersion(EH_ANDROID_PLATFORM_VERSION);
    metadata.setMobile(true);
    metadata.setModel(androidChromeModel());
    metadata.setFormFactors([webview.UserAgentFormFactor.MOBILE]);
    controller.setUserAgentMetadata(userAgent, metadata);
  }
}

function createUserAgentBrand(brand: string, majorVersion: string,
  fullVersion: string): webview.UserAgentBrandVersion | null {
  if (deviceInfo.apiAvailable(24)) {
    const result = new webview.UserAgentBrandVersion();
    result.setBrand(brand);
    result.setMajorVersion(majorVersion);
    result.setFullVersion(fullVersion);
    return result;
  }
  return null;
}

const ANDROID_MODEL: string = 'K';

export const EH_ANDROID_CHROME_FALLBACK_VERSION: string = '132.0.0.0';
export const EH_ANDROID_PLATFORM_VERSION: string = '10.0.0';

export function extractChromeVersion(userAgent: string): string {
  const match = userAgent.match(/Chrome\/([0-9.]+)/);
  if (match === null || match.length < 2 || match[1].length === 0) {
    return EH_ANDROID_CHROME_FALLBACK_VERSION;
  }
  return match[1];
}

export function buildAndroidChromeUserAgent(chromeVersion: string): string {
  return 'Mozilla/5.0 (Linux; Android 10; ' + ANDROID_MODEL + ') AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/' + chromeVersion + ' Mobile Safari/537.36';
}

export function buildAndroidChromeBrandHeader(chromeVersion: string): string {
  const majorVersion = chromeVersion.split('.')[0];
  return '"Chromium";v="' + majorVersion + '", "Google Chrome";v="' + majorVersion + '"';
}

export function androidChromeModel(): string {
  return ANDROID_MODEL;
}
