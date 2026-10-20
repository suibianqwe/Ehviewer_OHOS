import { EH_REPOSITORY_URL } from './EhBuildInfo';
import { decodeHtmlEntities } from '../shared/HtmlEntitySupport';

export interface ReleaseInfo {
  tagName: string;
  name: string;
  body: string;
  htmlUrl: string;
  hapDownloadUrl: string;
}

interface GitHubReleaseAssetJson {
  name?: string;
  browser_download_url?: string;
}

interface GitHubReleaseJson {
  tag_name?: string;
  name?: string;
  body?: string;
  assets?: GitHubReleaseAssetJson[];
  draft?: boolean;
  prerelease?: boolean;
}

function isStableReleaseTag(tag: string): boolean {
  return /^v?\d+(?:\.\d+){1,3}$/.test(tag);
}

export function parseGitHubRelease(body: string): ReleaseInfo | null {
  try {
    const parsed = JSON.parse(body) as GitHubReleaseJson;
    const tagName = typeof parsed.tag_name === 'string' ? parsed.tag_name.trim() : '';
    if (!isStableReleaseTag(tagName) || parsed.draft === true || parsed.prerelease === true) {
      return null;
    }
    const htmlUrl = EH_REPOSITORY_URL + '/releases/tag/' + encodeURIComponent(tagName);
    let hapDownloadUrl = htmlUrl;
    if (Array.isArray(parsed.assets)) {
      for (let i = 0; i < parsed.assets.length; i++) {
        const asset = parsed.assets[i];
        const url = typeof asset.browser_download_url === 'string' ? asset.browser_download_url : '';
        if (typeof asset.name === 'string' && asset.name.toLowerCase().endsWith('.hap') &&
          isReleaseHapUrl(url, tagName)) {
          hapDownloadUrl = url;
          break;
        }
      }
    }
    return {
      tagName: tagName,
      name: typeof parsed.name === 'string' && parsed.name.length > 0 ? parsed.name : tagName,
      body: typeof parsed.body === 'string' ? parsed.body.trim() : '',
      htmlUrl: htmlUrl,
      hapDownloadUrl: hapDownloadUrl
    };
  } catch (_error) {
    return null;
  }
}

// /releases/latest resolves to the stable release selected by GitHub, not a branch or a feed entry.
export function parseGitHubReleasePage(html: string): ReleaseInfo | null {
  const head = /<head\b[^>]*>([\s\S]*?)<\/head>/i.exec(html);
  if (head === null) {
    return null;
  }
  const url = absoluteGitHubUrl(metaContent(head[1], 'og:url'));
  const prefix = EH_REPOSITORY_URL + '/releases/tag/';
  if (!url.startsWith(prefix)) {
    return null;
  }
  const tagName = url.substring(prefix.length);
  if (!isStableReleaseTag(tagName)) {
    return null;
  }
  const title = metaContent(head[1], 'og:title').split(' · ')[0].replace(/^Release\s+/, '').trim();
  return {
    tagName: tagName,
    name: title.length > 0 ? title : tagName,
    body: releaseNotesText(html),
    htmlUrl: url,
    hapDownloadUrl: findGitHubHapLink(html, tagName, url)
  };
}

export function findGitHubHapLink(html: string, tagName: string, fallbackUrl: string): string {
  const links = html.match(/<a\b[^>]*>/gi) ?? [];
  for (let i = 0; i < links.length; i++) {
    const url = absoluteGitHubUrl(htmlAttribute(links[i], 'href'));
    if (isReleaseHapUrl(url, tagName)) {
      return url;
    }
  }
  return fallbackUrl;
}

function isReleaseHapUrl(url: string, tagName: string): boolean {
  const prefix = EH_REPOSITORY_URL + '/releases/download/' + encodeURIComponent(tagName) + '/';
  if (!url.startsWith(prefix)) {
    return false;
  }
  try {
    const fileName = decodeURIComponent(url.substring(prefix.length));
    return /^[^/\\?#]+\.hap$/i.test(fileName);
  } catch (_error) {
    return false;
  }
}

function absoluteGitHubUrl(url: string): string {
  return url.startsWith('/') && !url.startsWith('//') ? 'https://github.com' + url : url;
}

function htmlAttribute(tag: string, name: string): string {
  const match = new RegExp('\\s' + name + '\\s*=\\s*(["\x27])([\\s\\S]*?)\\1', 'i').exec(tag);
  return match === null ? '' : decodeHtmlEntities(match[2]);
}

function metaContent(head: string, property: string): string {
  const tags = head.match(/<meta\b[^>]*>/gi) ?? [];
  for (let i = 0; i < tags.length; i++) {
    if (htmlAttribute(tags[i], 'property') === property) {
      return htmlAttribute(tags[i], 'content');
    }
  }
  return '';
}

function releaseNotesText(html: string): string {
  const opening = /<div\b[^>]*\bclass\s*=\s*["'][^"']*\bmarkdown-body\b[^"']*["'][^>]*>/i.exec(html);
  if (opening === null) {
    return '';
  }
  const start = opening.index + opening[0].length;
  const divs = /<\/?div\b[^>]*>/gi;
  divs.lastIndex = start;
  let depth = 1;
  let match: RegExpExecArray | null = divs.exec(html);
  while (match !== null) {
    depth += match[0].startsWith('</') ? -1 : 1;
    if (depth === 0) {
      const notes = html.substring(start, match.index)
        .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '')
        .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, '')
        .replace(/<li\b[^>]*>/gi, '• ')
        .replace(/<br\s*\/?\s*>|<\/(?:p|li|h[1-6]|pre|blockquote|div)>/gi, '\n')
        .replace(/<[^>]*>/g, '');
      return decodeHtmlEntities(notes).replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
    }
    match = divs.exec(html);
  }
  return '';
}
