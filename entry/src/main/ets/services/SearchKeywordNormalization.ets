const EXACT_TAG_PATTERN: RegExp = /([A-Za-z0-9_]+:[^$]+?\$)/g;
const QUOTED_TAG_PATTERN: RegExp = /(^|\s)([A-Za-z0-9_]+):"([^"]+)"\$?(?=\s|$)/g;
const SUBMITTED_TAG_PATTERN: RegExp =
  /(^|\s)([A-Za-z0-9_]+)\s*[:：]\s*(?:"([^"]+)"|“([^”]+)”|＂([^＂]+)＂|([^$\s]+))\$?(?=\s|$)/g;

const TAG_NAMESPACES: string[] = [
  'artist', 'group', 'parody', 'character', 'female', 'male', 'mixed', 'language', 'cosplayer', 'other',
  'location', 'rows', 'reclass'
];

const LEGACY_TAG_NAMESPACE_ALIASES: Record<string, string> = {
  'a': 'artist',
  'c': 'character',
  'cos': 'cosplayer',
  'f': 'female',
  'g': 'group',
  'l': 'language',
  'm': 'male',
  'n': 'rows',
  'o': 'other',
  'p': 'parody',
  'r': 'reclass',
  'x': 'mixed'
};

function fullTagNamespace(namespace: string): string {
  const normalized = namespace.trim().toLowerCase();
  const aliased = LEGACY_TAG_NAMESPACE_ALIASES[normalized];
  return aliased === undefined ? normalized : aliased;
}

function isKnownTagNamespace(namespace: string): boolean {
  return TAG_NAMESPACES.indexOf(fullTagNamespace(namespace)) >= 0;
}

function normalizeExactSearchTagToken(token: string): string {
  const colon = token.indexOf(':');
  if (colon <= 0) {
    return token;
  }
  return fullTagNamespace(token.substring(0, colon)) + token.substring(colon);
}

function normalizeExactSearchTags(keyword: string): string {
  const parts: string[] = [];
  let offset = 0;
  EXACT_TAG_PATTERN.lastIndex = 0;
  let match: RegExpExecArray | null = EXACT_TAG_PATTERN.exec(keyword);
  while (match !== null) {
    parts.push(keyword.substring(offset, match.index));
    parts.push(normalizeExactSearchTagToken(match[1]));
    offset = match.index + match[0].length;
    match = EXACT_TAG_PATTERN.exec(keyword);
  }
  EXACT_TAG_PATTERN.lastIndex = 0;
  parts.push(keyword.substring(offset));
  return parts.join('');
}

export function normalizeLegacySearchKeywordValue(keyword: string): string {
  QUOTED_TAG_PATTERN.lastIndex = 0;
  let normalized = keyword.replace(QUOTED_TAG_PATTERN,
    (_all: string, leading: string, namespace: string, rawTag: string): string => {
      const tag = rawTag.trim().replace(/\$+$/, '').trim();
      if (tag.length === 0) {
        return _all;
      }
      return leading + fullTagNamespace(namespace) + ':' + tag + '$';
    });
  QUOTED_TAG_PATTERN.lastIndex = 0;
  normalized = normalizeExactSearchTags(normalized);
  return normalized.replace(/\s+/g, ' ').trim();
}

export function normalizeSubmittedSearchKeywordValue(keyword: string): string {
  SUBMITTED_TAG_PATTERN.lastIndex = 0;
  const normalized = keyword.replace(SUBMITTED_TAG_PATTERN,
    (_all: string, leading: string, namespace: string, quotedTag: string, curvedQuotedTag: string,
      fullWidthQuotedTag: string, unquotedTag: string): string => {
      if (!isKnownTagNamespace(namespace)) {
        return _all;
      }
      const rawTag = quotedTag || curvedQuotedTag || fullWidthQuotedTag || unquotedTag || '';
      const tag = rawTag.trim().replace(/\$+$/, '').trim();
      if (tag.length === 0) {
        return _all;
      }
      return leading + fullTagNamespace(namespace) + ':' + tag + '$';
    });
  SUBMITTED_TAG_PATTERN.lastIndex = 0;
  return normalizeLegacySearchKeywordValue(normalized);
}
