export interface EhTagSuggestion {
  namespace: string;
  tag: string;
  translated: string;
  searchText: string;
}

interface TagDatabaseCommitter {
  when?: string;
}

interface TagDatabaseHead {
  sha?: string;
  committer?: TagDatabaseCommitter;
}

interface TagDatabaseTextItem {
  name?: string;
}

interface TagDatabaseExample {
  raw?: string;
  name?: string;
}

interface TagDatabaseFrontMatters {
  example?: TagDatabaseExample;
}

interface TagDatabaseSection {
  namespace?: string;
  frontMatters?: TagDatabaseFrontMatters;
  data?: Record<string, TagDatabaseTextItem>;
}

interface TagDatabaseDocument {
  head?: TagDatabaseHead;
  data?: TagDatabaseSection[];
}

export interface ParsedTagDatabase {
  entries: EhTagSuggestion[];
  sha: string;
  sourceUpdatedAt: number;
  tsv: string;
}

const TAG_DATABASE_MINIMUM_ENTRY_COUNT: number = 10000;

class TagDatabaseParser {
  parseDatabaseDocument(body: string, expectedSha: string): ParsedTagDatabase {
    let document: TagDatabaseDocument;
    try {
      document = JSON.parse(body) as TagDatabaseDocument;
    } catch (error) {
      throw new Error('invalid database JSON');
    }
    const actualSha = document.head !== undefined && typeof document.head.sha === 'string' ?
      document.head.sha.trim().toLowerCase() : '';
    if (!isValidSha(actualSha) || actualSha !== expectedSha) {
      throw new Error('database version mismatch');
    }
    if (document.data === undefined || !Array.isArray(document.data)) {
      throw new Error('database has no tag data');
    }
    const sections = document.data;
    sections.sort((left: TagDatabaseSection, right: TagDatabaseSection): number => {
      const leftName = typeof left.namespace === 'string' ? left.namespace : '';
      const rightName = typeof right.namespace === 'string' ? right.namespace : '';
      return leftName < rightName ? -1 : leftName > rightName ? 1 : 0;
    });
    const entries: EhTagSuggestion[] = [];
    for (let i = 0; i < sections.length; i++) {
      this.appendDatabaseSection(entries, sections[i]);
    }
    if (entries.length < TAG_DATABASE_MINIMUM_ENTRY_COUNT) {
      throw new Error('database contains too few tags');
    }
    const when = document.head !== undefined && document.head.committer !== undefined &&
      typeof document.head.committer.when === 'string' ? Date.parse(document.head.committer.when) : Number.NaN;
    return {
      entries: entries,
      sha: actualSha,
      tsv: serializeTsv(entries),
      sourceUpdatedAt: Number.isNaN(when) ? Date.now() : when
    };
  }

  appendDatabaseSection(target: EhTagSuggestion[], section: TagDatabaseSection): void {
    const namespace = typeof section.namespace === 'string' ? cleanDatabaseField(section.namespace).toLowerCase() : '';
    if (namespace.length === 0) {
      return;
    }
    if (section.frontMatters !== undefined && section.frontMatters.example !== undefined) {
      const example = section.frontMatters.example;
      this.appendDatabaseEntry(target, namespace,
        typeof example.raw === 'string' ? example.raw : '',
        typeof example.name === 'string' ? example.name : '');
    }
    if (section.data === undefined) {
      return;
    }
    const keys = Object.keys(section.data);
    keys.sort();
    for (let i = 0; i < keys.length; i++) {
      const item = section.data[keys[i]];
      this.appendDatabaseEntry(target, namespace, keys[i],
        item !== undefined && typeof item.name === 'string' ? item.name : '');
    }
  }

  appendDatabaseEntry(target: EhTagSuggestion[], namespace: string, rawTag: string, name: string): void {
    const tag = cleanDatabaseField(rawTag);
    const translated = cleanDatabaseField(name);
    if (tag.length === 0 || translated.length === 0) {
      return;
    }
    const fullTag = namespace + ':' + tag;
    target.push({
      namespace: namespace,
      tag: fullTag,
      translated: translated,
      searchText: (fullTag + ' ' + tag + ' ' + translated).toLowerCase()
    });
  }

  parseTsv(text: string): EhTagSuggestion[] {
    const next: EhTagSuggestion[] = [];
    const lines = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      const parts = line.split('\t');
      if (parts.length < 4 || parts[0].length === 0 || parts[1].length === 0 || parts[2].length === 0) {
        continue;
      }
      next.push({
        namespace: parts[0],
        tag: parts[1],
        translated: parts[2],
        searchText: parts[3]
      });
    }
    return next;
  }
}

function cleanDatabaseField(value: string): string {
  return value.replace(/\t/g, ' ').replace(/\r/g, ' ').replace(/\n/g, ' ').trim();
}

function serializeTsv(entries: EhTagSuggestion[]): string {
  const lines: string[] = [];
  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i];
    lines.push(entry.namespace + '\t' + entry.tag + '\t' + entry.translated + '\t' + entry.searchText);
  }
  return lines.join('\n') + '\n';
}

function isValidSha(value: string): boolean {
  return /^[0-9a-f]{40}$/i.test(value.trim());
}

export function parseTagTsv(text: string): EhTagSuggestion[] {
  return new TagDatabaseParser().parseTsv(text);
}

export function prepareTagDatabase(body: string, expectedSha: string): ParsedTagDatabase {
  return new TagDatabaseParser().parseDatabaseDocument(body, expectedSha);
}

