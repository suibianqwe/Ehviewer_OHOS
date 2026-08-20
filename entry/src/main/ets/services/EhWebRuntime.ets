import { webview } from '@kit.ArkWeb';
import { deviceInfo } from '@kit.BasicServicesKit';
import {
  androidChromeModel,
  buildAndroidChromeUserAgent,
  EH_ANDROID_PLATFORM_VERSION,
  extractChromeVersion
} from './EhBrowserCompatibility';
import { currentDnsOverHttpsUrl } from './EhNetworkConfig';

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
  if (!deviceInfo.apiAvailable(24)) {
    return;
  }
  const majorVersion = chromeVersion.split('.')[0];
  const chromiumBrand = createUserAgentBrand('Chromium', majorVersion, chromeVersion);
  const chromeBrand = createUserAgentBrand('Google Chrome', majorVersion, chromeVersion);
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

function createUserAgentBrand(brand: string, majorVersion: string,
  fullVersion: string): webview.UserAgentBrandVersion {
  const result = new webview.UserAgentBrandVersion();
  result.setBrand(brand);
  result.setMajorVersion(majorVersion);
  result.setFullVersion(fullVersion);
  return result;
}
