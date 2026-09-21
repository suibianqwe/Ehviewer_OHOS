const TAG_NAMESPACE_TOKEN_PATTERN: RegExp = /(^|\s)([A-Za-z0-9_]+)\s*[:：]\s*/g;
// Android 版书签常用 "$" 直接分隔两个标签（如 artist:foo$parody:x），先补一个空格再分词。
const DOLLAR_BEFORE_NAMESPACE_PATTERN: RegExp = /\$+(?=[A-Za-z0-9_]+\s*[:：])/g;

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

interface TagToken {
  start: number;
  contentStart: number;
  namespace: string;
}

function fullTagNamespace(namespace: string): string {
  const normalized = namespace.trim().toLowerCase();
  const aliased = LEGACY_TAG_NAMESPACE_ALIASES[normalized];
  return aliased === undefined ? normalized : aliased;
}

function isKnownTagNamespace(namespace: string): boolean {
  return TAG_NAMESPACES.indexOf(fullTagNamespace(namespace)) >= 0;
}

function collectTagTokens(keyword: string): TagToken[] {
  const tokens: TagToken[] = [];
  TAG_NAMESPACE_TOKEN_PATTERN.lastIndex = 0;
  let match: RegExpExecArray | null = TAG_NAMESPACE_TOKEN_PATTERN.exec(keyword);
  while (match !== null) {
    if (isKnownTagNamespace(match[2])) {
      tokens.push({
        start: match.index + match[1].length,
        contentStart: match.index + match[0].length,
        namespace: match[2]
      });
    }
    match = TAG_NAMESPACE_TOKEN_PATTERN.exec(keyword);
  }
  TAG_NAMESPACE_TOKEN_PATTERN.lastIndex = 0;
  return tokens;
}

function stripTagQuotes(value: string): string {
  const trimmed = value.trim();
  if (trimmed.length >= 2) {
    const first = trimmed.charAt(0);
    const last = trimmed.charAt(trimmed.length - 1);
    if ((first === '"' && last === '"') || (first === '“' && last === '”') ||
      (first === '＂' && last === '＂')) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
  }
  return trimmed;
}

// 以已知的 “命名空间:” 作为标签边界：作者/社团名里的空格会保留在同一个标签内，
// 直到下一个命名空间或 "$" 结束符为止。没有命名空间的普通关键词保持原样。
function normalizeSearchTags(keyword: string): string {
  const spaced = keyword.replace(DOLLAR_BEFORE_NAMESPACE_PATTERN, '$ ');
  const tokens = collectTagTokens(spaced);
  if (tokens.length === 0) {
    return spaced.replace(/\s+/g, ' ').trim();
  }
  let result = '';
  let cursor = 0;
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (token.start < cursor) {
      continue;
    }
    result += spaced.substring(cursor, token.start);
    let nextStart = spaced.length;
    if (i + 1 < tokens.length) {
      nextStart = tokens[i + 1].start;
    }
    const dollar = spaced.indexOf('$', token.contentStart);
    let end = nextStart;
    let skipTo = nextStart;
    if (dollar >= 0 && dollar < nextStart) {
      end = dollar;
      skipTo = dollar + 1;
    }
    const tag = stripTagQuotes(spaced.substring(token.contentStart, end)).replace(/\$+$/, '').trim();
    if (tag.length > 0) {
      result += fullTagNamespace(token.namespace) + ':' + tag + '$';
    }
    cursor = skipTo;
  }
  result += spaced.substring(cursor);
  return result.replace(/\s+/g, ' ').trim();
}

export function normalizeLegacySearchKeywordValue(keyword: string): string {
  return normalizeSearchTags(keyword);
}

export function normalizeSubmittedSearchKeywordValue(keyword: string): string {
  return normalizeSearchTags(normalizeSearchTags(keyword));
}
