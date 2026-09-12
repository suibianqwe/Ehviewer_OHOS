const TERMINATED_TAG_PATTERN: RegExp =
  /(^|\s)([A-Za-z0-9_]+)\s*[:：]\s*([^$]+?)\$(?=\s|$)/g;
const QUOTED_TAG_PATTERN: RegExp =
  /(^|\s)([A-Za-z0-9_]+)\s*[:：]\s*(?:"([^"]+)"|“([^”]+)”|＂([^＂]+)＂)\$?(?=\s|$)/g;
const BARE_TAG_PATTERN: RegExp =
  /(^|\s)([A-Za-z0-9_]+)\s*[:：]\s*([^$\s"“”＂]+)(?=\s|$)/g;
const TERMINATED_TAG_SPAN_PATTERN: RegExp =
  /(^|\s)([A-Za-z0-9_]+:[^$]+?\$)(?=\s|$)/g;

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

function normalizeBareSearchTags(keyword: string): string {
  BARE_TAG_PATTERN.lastIndex = 0;
  const normalized = keyword.replace(BARE_TAG_PATTERN,
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
  BARE_TAG_PATTERN.lastIndex = 0;
  return normalized;
}

// Terminates every known bare tag, not just the trailing one. Quoted or already-terminated tags
// can contain spaces (parody:genshin impact$), so their spans are protected from the bare pass.
function normalizeBareTagsOutsideTerminatedTags(keyword: string): string {
  TERMINATED_TAG_SPAN_PATTERN.lastIndex = 0;
  let result = '';
  let cursor = 0;
  let match: RegExpExecArray | null = TERMINATED_TAG_SPAN_PATTERN.exec(keyword);
  while (match !== null) {
    const spanStart = match.index + match[1].length;
    const spanEnd = match.index + match[0].length;
    result += normalizeBareSearchTags(keyword.substring(cursor, spanStart));
    result += keyword.substring(spanStart, spanEnd);
    cursor = spanEnd;
    match = TERMINATED_TAG_SPAN_PATTERN.exec(keyword);
  }
  result += normalizeBareSearchTags(keyword.substring(cursor));
  return result.replace(/\s+/g, ' ').trim();
}

export function normalizeSubmittedSearchKeywordValue(keyword: string): string {
  const legacyNormalized = normalizeLegacySearchKeywordValue(keyword);
  const normalized = normalizeBareTagsOutsideTerminatedTags(legacyNormalized);
  return normalizeLegacySearchKeywordValue(normalized);
}
