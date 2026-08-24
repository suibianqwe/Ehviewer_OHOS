const TERMINATED_TAG_PATTERN: RegExp =
  /(^|\s)([A-Za-z0-9_]+)\s*[:：]\s*([^$]+?)\$(?=\s|$)/g;
const QUOTED_TAG_PATTERN: RegExp =
  /(^|\s)([A-Za-z0-9_]+)\s*[:：]\s*(?:"([^"]+)"|“([^”]+)”|＂([^＂]+)＂)\$?(?=\s|$)/g;
const TRAILING_PLAIN_TAG_PATTERN: RegExp =
  /(^|\s)([A-Za-z0-9_]+)\s*[:：]\s*([^$\s"“”＂]+)$/g;

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

function normalizeTerminatedSearchTags(keyword: string): string {
  TERMINATED_TAG_PATTERN.lastIndex = 0;
  const normalized = keyword.replace(TERMINATED_TAG_PATTERN,
    (_all: string, leading: string, namespace: string, rawTag: string): string => {
      if (!isKnownTagNamespace(namespace)) {
        return _all;
      }
      const tag = rawTag.trim();
      if (tag.length === 0) {
        return _all;
      }
      return leading + fullTagNamespace(namespace) + ':' + tag + '$';
    });
  TERMINATED_TAG_PATTERN.lastIndex = 0;
  return normalized;
}

export function normalizeLegacySearchKeywordValue(keyword: string): string {
  QUOTED_TAG_PATTERN.lastIndex = 0;
  let normalized = keyword.replace(QUOTED_TAG_PATTERN,
    (_all: string, leading: string, namespace: string, quotedTag: string, curvedQuotedTag: string,
      fullWidthQuotedTag: string): string => {
      if (!isKnownTagNamespace(namespace)) {
        return _all;
      }
      const rawTag = quotedTag || curvedQuotedTag || fullWidthQuotedTag || '';
      const tag = rawTag.trim().replace(/\$+$/, '').trim();
      if (tag.length === 0) {
        return _all;
      }
      return leading + fullTagNamespace(namespace) + ':' + tag + '$';
    });
  QUOTED_TAG_PATTERN.lastIndex = 0;
  normalized = normalizeTerminatedSearchTags(normalized);
  return normalized.replace(/\s+/g, ' ').trim();
}

export function normalizeSubmittedSearchKeywordValue(keyword: string): string {
  const legacyNormalized = normalizeLegacySearchKeywordValue(keyword);
  TRAILING_PLAIN_TAG_PATTERN.lastIndex = 0;
  const normalized = legacyNormalized.replace(TRAILING_PLAIN_TAG_PATTERN,
    (_all: string, leading: string, namespace: string, rawTag: string): string => {
      if (!isKnownTagNamespace(namespace)) {
        return _all;
      }
      const tag = rawTag.trim().replace(/\$+$/, '').trim();
      if (tag.length === 0) {
        return _all;
      }
      return leading + fullTagNamespace(namespace) + ':' + tag + '$';
    });
  TRAILING_PLAIN_TAG_PATTERN.lastIndex = 0;
  return normalizeLegacySearchKeywordValue(normalized);
}
