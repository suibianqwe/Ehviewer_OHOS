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
