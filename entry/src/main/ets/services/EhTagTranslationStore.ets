import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { EH_APP_VERSION_NAME } from './EhBuildInfo';
import {
  applyEhNetworkOptions,
  createEhRequestPlan,
  EhRequestPlan,
  ensureEhHostRules,
  recordEhRequestOutcome
} from './EhNetworkConfig';

export interface EhTagSuggestion {
  namespace: string;
  tag: string;
  translated: string;
  searchText: string;
}

export interface EhTagTranslationUpdateResult {
  updated: boolean;
  count: number;
  sha: string;
}

interface TagDatabaseMetadata {
  sha?: string;
  sourceUpdatedAt?: number;
  installedAt?: number;
  count?: number;
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

interface ParsedTagDatabase {
  entries: EhTagSuggestion[];
  sha: string;
  sourceUpdatedAt: number;
}

const TAG_TRANSLATION_RAWFILE: string = 'ehtag_translations.tsv';
const TAG_TRANSLATION_DIRECTORY: string = 'tag-translations';
const TAG_TRANSLATION_OVERRIDE_FILE: string = 'ehtag_translations.tsv';
const TAG_TRANSLATION_METADATA_FILE: string = 'metadata.json';
const TAG_TRANSLATION_LATEST_SHA_URL: string =
  'https://github.com/EhTagTranslation/Database/releases/latest/download/sha';
const TAG_TRANSLATION_LATEST_DATA_URL: string =
  'https://github.com/EhTagTranslation/Database/releases/latest/download/db.text.json';
const BUNDLED_DATABASE_SHA: string = '900aeb9c8f91cbc3de80a78e0f5d84520be1238a';
const BUNDLED_DATABASE_SOURCE_UPDATED_AT: number = 1784012135000;
const TAG_DATABASE_MINIMUM_ENTRY_COUNT: number = 10000;
const TAG_DATABASE_REQUEST_TIMEOUT_MS: number = 30000;
const TAG_DATABASE_RESPONSE_LIMIT: number = 8 * 1024 * 1024;

class EhTagTranslationStore {
  private loaded: boolean = false;
  private entries: EhTagSuggestion[] = [];
  private translations: Map<string, string> = new Map<string, string>();
  private pendingUpdate: Promise<EhTagTranslationUpdateResult> | null = null;

  suggest(keyword: string, limit: number = 0, namespaces: string[] = []): EhTagSuggestion[] {
    const normalized = keyword.trim().toLowerCase();
    if (normalized.length === 0) {
      return [];
    }
    this.ensureLoaded();
    const filter = normalizeNamespaces(namespaces);
    const result: EhTagSuggestion[] = [];
    const unlimited = limit <= 0;
    for (let i = 0; i < this.entries.length && (unlimited || result.length < limit); i++) {
      const entry = this.entries[i];
      if (filter.length > 0 && filter.indexOf(entry.namespace) < 0) {
        continue;
      }
      if (entry.searchText.indexOf(normalized) >= 0) {
        result.push(cloneSuggestion(entry));
      }
    }
    return result;
  }

  translate(namespace: string, tag: string): string {
    this.ensureLoaded();
    const key = normalizeFullTag(namespace, tag);
    const translated = this.translations.get(key);
    return translated === undefined ? '' : translated;
  }

  async update(context: common.UIAbilityContext): Promise<EhTagTranslationUpdateResult> {
    if (this.pendingUpdate !== null) {
      return this.pendingUpdate;
    }
    this.pendingUpdate = this.updateInternal(context);
    try {
      return await this.pendingUpdate;
    } finally {
      this.pendingUpdate = null;
    }
  }

  private async updateInternal(context: common.UIAbilityContext): Promise<EhTagTranslationUpdateResult> {
    const latestSha = (await requestTagDatabaseText(TAG_TRANSLATION_LATEST_SHA_URL, 'text/plain')).trim().toLowerCase();
    if (!isValidSha(latestSha)) {
      throw new Error('invalid database version');
    }
    const currentSha = this.currentDatabaseSha(context);
    if (currentSha === latestSha) {
      this.loadFromContext(context);
      return {
        updated: false,
        count: this.entries.length,
        sha: latestSha
      };
    }
    const body = await requestTagDatabaseText(TAG_TRANSLATION_LATEST_DATA_URL, 'application/json');
    const parsed = this.parseDatabaseDocument(body, latestSha);
    this.saveOverride(context, parsed);
    this.entries = parsed.entries;
    this.rebuildTranslationMap();
    this.loaded = true;
    return {
      updated: true,
      count: parsed.entries.length,
      sha: parsed.sha
    };
  }

  private ensureLoaded(): void {
    if (this.loaded) {
      return;
    }
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
    if (context === undefined) {
      return;
    }
    this.loadFromContext(context);
  }

  private loadFromContext(context: common.UIAbilityContext): void {
    if (this.loaded) {
      return;
    }
    try {
      const overridePath = this.usableOverridePath(context);
      if (overridePath.length > 0) {
        const overrideEntries = this.parseTsv(fs.readTextSync(overridePath));
        if (overrideEntries.length >= TAG_DATABASE_MINIMUM_ENTRY_COUNT) {
          this.entries = overrideEntries;
          this.rebuildTranslationMap();
          this.loaded = true;
          return;
        }
      }
      const data = context.resourceManager.getRawFileContentSync(TAG_TRANSLATION_RAWFILE);
      const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      this.entries = this.parseTsv(decoder.decodeToString(data, { stream: false }));
      this.rebuildTranslationMap();
    } catch (error) {
      this.entries = [];
      this.translations = new Map<string, string>();
    }
    this.loaded = true;
  }

  private currentDatabaseSha(context: common.UIAbilityContext): string {
    const metadata = this.readMetadata(context);
    if (this.isOverrideNewEnough(context, metadata) && typeof metadata.sha === 'string') {
      return metadata.sha.toLowerCase();
    }
    return BUNDLED_DATABASE_SHA;
  }

  private usableOverridePath(context: common.UIAbilityContext): string {
    const metadata = this.readMetadata(context);
    if (!this.isOverrideNewEnough(context, metadata)) {
      return '';
    }
    return this.overridePath(context);
  }

  private isOverrideNewEnough(context: common.UIAbilityContext, metadata: TagDatabaseMetadata): boolean {
    if (typeof metadata.sha !== 'string' || !isValidSha(metadata.sha)) {
      return false;
    }
    if (typeof metadata.sourceUpdatedAt !== 'number' ||
      metadata.sourceUpdatedAt < BUNDLED_DATABASE_SOURCE_UPDATED_AT) {
      return false;
    }
    return exists(this.overridePath(context));
  }

  private readMetadata(context: common.UIAbilityContext): TagDatabaseMetadata {
    try {
      const path = this.metadataPath(context);
      if (!exists(path)) {
        return {};
      }
      return JSON.parse(fs.readTextSync(path)) as TagDatabaseMetadata;
    } catch (error) {
      return {};
    }
  }

  private parseDatabaseDocument(body: string, expectedSha: string): ParsedTagDatabase {
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
      sourceUpdatedAt: Number.isNaN(when) ? Date.now() : when
    };
  }

  private appendDatabaseSection(target: EhTagSuggestion[], section: TagDatabaseSection): void {
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

  private appendDatabaseEntry(target: EhTagSuggestion[], namespace: string, rawTag: string, name: string): void {
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

  private saveOverride(context: common.UIAbilityContext, parsed: ParsedTagDatabase): void {
    const directory = this.databaseDirectory(context);
    ensureDirectory(directory);
    const overridePath = this.overridePath(context);
    const metadataPath = this.metadataPath(context);
    const overrideTempPath = overridePath + '.tmp';
    const metadataTempPath = metadataPath + '.tmp';
    removeFileQuietly(overrideTempPath);
    removeFileQuietly(metadataTempPath);
    try {
      writeTextFile(overrideTempPath, serializeTsv(parsed.entries));
      const metadata: TagDatabaseMetadata = {
        sha: parsed.sha,
        sourceUpdatedAt: parsed.sourceUpdatedAt,
        installedAt: Date.now(),
        count: parsed.entries.length
      };
      writeTextFile(metadataTempPath, JSON.stringify(metadata));
      replaceFile(overrideTempPath, overridePath);
      replaceFile(metadataTempPath, metadataPath);
    } catch (error) {
      removeFileQuietly(overrideTempPath);
      removeFileQuietly(metadataTempPath);
      throw new Error('database save failed: ' + errorMessage(error as Object));
    }
  }

  private databaseDirectory(context: common.UIAbilityContext): string {
    return context.filesDir + '/' + TAG_TRANSLATION_DIRECTORY;
  }

  private overridePath(context: common.UIAbilityContext): string {
    return this.databaseDirectory(context) + '/' + TAG_TRANSLATION_OVERRIDE_FILE;
  }

  private metadataPath(context: common.UIAbilityContext): string {
    return this.databaseDirectory(context) + '/' + TAG_TRANSLATION_METADATA_FILE;
  }

  private parseTsv(text: string): EhTagSuggestion[] {
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

  private rebuildTranslationMap(): void {
    const next: Map<string, string> = new Map<string, string>();
    for (let i = 0; i < this.entries.length; i++) {
      const entry = this.entries[i];
      next.set(entry.tag.toLowerCase(), entry.translated);
    }
    this.translations = next;
  }
}

export const ehTagTranslationStore = new EhTagTranslationStore();

async function requestTagDatabaseText(url: string, accept: string): Promise<string> {
  const request = http.createHttp();
  const plan = createEhRequestPlan(url);
  const startedAt = Date.now();
  let outcomeRecorded = false;
  try {
    await ensureEhHostRules();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: buildRequestHeaders(plan, accept),
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      maxLimit: TAG_DATABASE_RESPONSE_LIMIT,
      connectTimeout: TAG_DATABASE_REQUEST_TIMEOUT_MS,
      readTimeout: TAG_DATABASE_REQUEST_TIMEOUT_MS
    };
    applyEhNetworkOptions(options, plan);
    const response = await request.request(plan.url, options);
    const statusCode = Number(response.responseCode);
    recordEhRequestOutcome(plan, statusCode >= 200 && statusCode < 500, Date.now() - startedAt);
    outcomeRecorded = true;
    if (statusCode < 200 || statusCode >= 300) {
      throw new Error('HTTP ' + statusCode.toString());
    }
    return response.result as string;
  } catch (error) {
    if (!outcomeRecorded) {
      recordEhRequestOutcome(plan, false, Date.now() - startedAt);
    }
    throw new Error(errorMessage(error as Object));
  } finally {
    try {
      request.destroy();
    } catch (error) {
    }
  }
}

function buildRequestHeaders(plan: EhRequestPlan, accept: string): Record<string, string> {
  return {
    'Host': plan.host,
    'User-Agent': 'EhViewerHarmony/' + EH_APP_VERSION_NAME,
    'Accept': accept,
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Cache-Control': 'no-cache',
    'Connection': plan.fronted ? 'close' : 'keep-alive'
  };
}

function cloneSuggestion(entry: EhTagSuggestion): EhTagSuggestion {
  return {
    namespace: entry.namespace,
    tag: entry.tag,
    translated: entry.translated,
    searchText: entry.searchText
  };
}

function normalizeNamespaces(namespaces: string[]): string[] {
  const next: string[] = [];
  for (let i = 0; i < namespaces.length; i++) {
    const value = namespaces[i].trim().toLowerCase();
    if (value.length > 0 && next.indexOf(value) < 0) {
      next.push(value);
    }
  }
  return next;
}

function normalizeFullTag(namespace: string, tag: string): string {
  const normalizedNamespace = namespace.trim().toLowerCase();
  const normalizedTag = tag.trim().toLowerCase();
  if (normalizedTag.indexOf(':') >= 0) {
    return normalizedTag;
  }
  return normalizedNamespace.length === 0 ? normalizedTag : normalizedNamespace + ':' + normalizedTag;
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

function ensureDirectory(path: string): void {
  if (exists(path)) {
    return;
  }
  try {
    fs.mkdirSync(path, true);
  } catch (error) {
    throw new Error('create database directory failed: ' + errorMessage(error as Object));
  }
}

function writeTextFile(path: string, value: string): void {
  let fd = -1;
  try {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    fd = file.fd;
    fs.writeSync(fd, value);
  } catch (error) {
    throw new Error('write database file failed: ' + errorMessage(error as Object));
  } finally {
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (error) {
      }
    }
  }
}

function replaceFile(source: string, target: string): void {
  removeFileQuietly(target);
  try {
    fs.moveFileSync(source, target);
  } catch (error) {
    throw new Error('replace database file failed: ' + errorMessage(error as Object));
  }
}

function removeFileQuietly(path: string): void {
  try {
    if (exists(path)) {
      fs.unlinkSync(path);
    }
  } catch (error) {
  }
}

function exists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (error) {
    return false;
  }
}

function errorMessage(error: Object): string {
  let message = String(error);
  if (message.indexOf('Error: ') === 0) {
    message = message.substring(7);
  }
  return message.length > 0 ? message : 'network request failed';
}
