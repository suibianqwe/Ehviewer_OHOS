import { TorrentInfo } from '../model/GalleryModels';

const FORM_PATTERN: RegExp = /<form\b[^>]*>[\s\S]*?<\/form>/gi;
const TORRENT_PATTERN: RegExp = /<a\b[^>]*href=["']([^"']*\/torrent\/[^"']+\.torrent(?:\?[^"']*)?)["'][^>]*>([\s\S]*?)<\/a>/i;

export function parseTorrentList(body: string): TorrentInfo[] {
  FORM_PATTERN.lastIndex = 0;
  const torrents: TorrentInfo[] = [];
  let formMatch: RegExpExecArray | null = FORM_PATTERN.exec(body);
  while (formMatch !== null) {
    const block = formMatch[0];
    const torrentMatch = TORRENT_PATTERN.exec(block);
    if (torrentMatch !== null) {
      const url = stripPrivatePasskey(decodeHtml(torrentMatch[1]).trim());
      const name = cleanText(torrentMatch[2]);
      const hash = torrentHash(url);
      if (hash.length > 0) {
        torrents.push({
          url: url,
          magnetUrl: 'magnet:?xt=urn:btih:' + hash + '&dn=' + encodeURIComponent(name),
          name: name,
          posted: parseTextField(block, 'Posted'),
          size: parseTextField(block, 'Size'),
          seeds: parseNumberField(block, 'Seeds'),
          peers: parseNumberField(block, 'Peers'),
          downloads: parseNumberField(block, 'Downloads')
        });
      }
    }
    formMatch = FORM_PATTERN.exec(body);
  }
  return torrents;
}

function parseTextField(block: string, label: string): string {
  const pattern = new RegExp('<span[^>]*>\\s*' + label + ':\\s*<\\/span>\\s*(?:<span[^>]*>)?([^<]+)', 'i');
  const match = pattern.exec(block);
  return match === null ? '' : cleanText(match[1]);
}

function parseNumberField(block: string, label: string): number {
  const value = parseTextField(block, label).replace(/,/g, '');
  const parsed = Number.parseInt(value);
  return Number.isNaN(parsed) ? 0 : parsed;
}

function torrentHash(url: string): string {
  const match = /\/([a-f0-9]{40})\.torrent(?:\?|$)/i.exec(url);
  return match === null ? '' : match[1].toLowerCase();
}

function stripPrivatePasskey(url: string): string {
  const index = url.indexOf('?p=');
  return index < 0 ? url : url.substring(0, index);
}

function cleanText(value: string): string {
  return decodeHtml(value.replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
}

function decodeHtml(value: string): string {
  return value
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, '\'')
    .replace(/&nbsp;/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}
