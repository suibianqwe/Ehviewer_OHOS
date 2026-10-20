import { common } from '@kit.AbilityKit';
import { taskpool, util } from '@kit.ArkTS';
import { EhTagSuggestion, ParsedTagDatabase } from './TagTranslationProcessing';
import { parseTagTsvTask, prepareTagDatabaseTask } from './TagTranslationTasks';
import { notifyLanguageChanged } from '../shared/EhTranslations';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EH_APP_VERSION_NAME } from './EhBuildInfo';
import {
  applyEhNetworkOptions,
  createEhRequestPlan,
  EhRequestPlan,
  ensureEhHostRules,
  recordEhRequestOutcome
} from './EhNetworkConfig';
import { acquireHttpRequest, markHttpRequestVolatile, retireHttpRequest } from './HttpRequestLifecycle';

export { EhTagSuggestion } from './TagTranslationProcessing';

export interface EhTagTranslationUpdateResult {
  updated: boolean;
  count: number;
  sha: string;
}

export type EhTagTranslationUpdatePhase = 'checking' | 'downloading';
export type EhTagTranslationUpdateProgressCallback = (phase: EhTagTranslationUpdatePhase) => void;

interface TagDatabaseMetadata {
  sha?: string;
  sourceUpdatedAt?: number;
  installedAt?: number;
  count?: number;
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
  private pendingLoad: Promise<void> | null = null;
  private entries: EhTagSuggestion[] = [];
  private translations: Map<string, string> = new Map<string, string>();
  private pendingUpdate: Promise<EhTagTranslationUpdateResult> | null = null;
  private pendingUpdatePhase: EhTagTranslationUpdatePhase = 'checking';

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

  async update(context: common.UIAbilityContext, onProgress?: EhTagTranslationUpdateProgressCallback):
    Promise<EhTagTranslationUpdateResult> {
    if (this.pendingUpdate !== null) {
      if (onProgress !== undefined) {
        onProgress(this.pendingUpdatePhase);
      }
      return this.pendingUpdate;
    }
    this.reportUpdateProgress('checking', onProgress);
    this.pendingUpdate = this.updateInternal(context, onProgress);
    try {
      return await this.pendingUpdate;
    } finally {
      this.pendingUpdate = null;
    }
  }

  private async updateInternal(context: common.UIAbilityContext, onProgress?: EhTagTranslationUpdateProgressCallback):
    Promise<EhTagTranslationUpdateResult> {
    await this.preload(context);
    const latestSha = (await requestTagDatabaseText(TAG_TRANSLATION_LATEST_SHA_URL, 'text/plain')).trim().toLowerCase();
    if (!isValidSha(latestSha)) {
      throw new Error('invalid database version');
    }
    const currentSha = await this.currentDatabaseSha(context);
    if (currentSha === latestSha) {
      return {
        updated: false,
        count: this.entries.length,
        sha: latestSha
      };
    }
    this.reportUpdateProgress('downloading', onProgress);
    const body = await requestTagDatabaseText(TAG_TRANSLATION_LATEST_DATA_URL, 'application/json');
    const parsed = await taskpool.execute(prepareTagDatabaseTask, body, latestSha) as ParsedTagDatabase;
    const translations = await this.buildTranslationMap(parsed.entries);
    await this.saveOverride(context, parsed);
    this.entries = parsed.entries;
    this.translations = translations;
    this.loaded = true;
    return {
      updated: true,
      count: parsed.entries.length,
      sha: parsed.sha
    };
  }

  private reportUpdateProgress(phase: EhTagTranslationUpdatePhase,
    onProgress?: EhTagTranslationUpdateProgressCallback): void {
    this.pendingUpdatePhase = phase;
    if (onProgress !== undefined) {
      onProgress(phase);
    }
  }

  private ensureLoaded(): void {
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
    if (!this.loaded && context !== undefined) {
      this.preload(context).catch(() => {});
    }
  }

  async preload(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    if (this.pendingLoad !== null) {
      return this.pendingLoad;
    }
    const startedAt = Date.now();
    const pending = this.loadFromContext(context).then(() => {
      hilog.info(0x3210, 'TagDatabase', 'Loaded tags=%{public}d elapsedMs=%{public}d',
        this.entries.length, Date.now() - startedAt);
      notifyLanguageChanged();
    });
    this.pendingLoad = pending;
    try {
      await pending;
    } finally {
      if (this.pendingLoad === pending) {
        this.pendingLoad = null;
      }
    }
  }

  private async loadFromContext(context: common.UIAbilityContext): Promise<void> {
    let entries: EhTagSuggestion[] = [];
    const override = await this.usableOverridePath(context);
    if (override.length > 0) {
      try {
        entries = await taskpool.execute(parseTagTsvTask, await fs.readText(override)) as EhTagSuggestion[];
      } catch (_error) {
      }
    }
    if (entries.length < TAG_DATABASE_MINIMUM_ENTRY_COUNT) {
      const data = await context.resourceManager.getRawFileContent(TAG_TRANSLATION_RAWFILE);
      const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      entries = await taskpool.execute(parseTagTsvTask,
        decoder.decodeToString(data, { stream: false })) as EhTagSuggestion[];
    }
    const translations = await this.buildTranslationMap(entries);
    this.entries = entries;
    this.translations = translations;
    this.loaded = true;
  }

  private async currentDatabaseSha(context: common.UIAbilityContext): Promise<string> {
    const metadata = await this.readMetadata(context);
    return await this.isOverrideNewEnough(context, metadata) && typeof metadata.sha === 'string' ?
      metadata.sha.toLowerCase() : BUNDLED_DATABASE_SHA;
  }

  private async usableOverridePath(context: common.UIAbilityContext): Promise<string> {
    return await this.isOverrideNewEnough(context, await this.readMetadata(context)) ? this.overridePath(context) : '';
  }

  private async isOverrideNewEnough(context: common.UIAbilityContext, metadata: TagDatabaseMetadata): Promise<boolean> {
    if (typeof metadata.sha !== 'string' || !isValidSha(metadata.sha) ||
      typeof metadata.sourceUpdatedAt !== 'number' || metadata.sourceUpdatedAt < BUNDLED_DATABASE_SOURCE_UPDATED_AT) {
      return false;
    }
    try {
      return await fs.access(this.overridePath(context));
    } catch (_error) {
      return false;
    }
  }

  private async readMetadata(context: common.UIAbilityContext): Promise<TagDatabaseMetadata> {
    try {
      return JSON.parse(await fs.readText(this.metadataPath(context))) as TagDatabaseMetadata;
    } catch (_error) {
      return {};
    }
  }




  private async saveOverride(context: common.UIAbilityContext, parsed: ParsedTagDatabase): Promise<void> {
    const directory = this.databaseDirectory(context);
    try {
      await fs.mkdir(directory, true);
    } catch (error) {
      if (!await fs.access(directory)) {
        throw new Error('create database directory failed: ' + String(error));
      }
    }
    const overridePath = this.overridePath(context);
    const metadataPath = this.metadataPath(context);
    const overrideTempPath = overridePath + '.tmp';
    const metadataTempPath = metadataPath + '.tmp';
    const backupPath = overridePath + '.backup';
    let hasBackup = false;
    let replaced = false;
    let preserveBackup = false;
    try {
      await writeTextFile(overrideTempPath, parsed.tsv);
      const metadata: TagDatabaseMetadata = { sha: parsed.sha, sourceUpdatedAt: parsed.sourceUpdatedAt,
        installedAt: Date.now(), count: parsed.entries.length };
      await writeTextFile(metadataTempPath, JSON.stringify(metadata));
      if (await fs.access(overridePath)) {
        await fs.copyFile(overridePath, backupPath);
        hasBackup = true;
      }
      await fs.rename(overrideTempPath, overridePath);
      replaced = true;
      await fs.rename(metadataTempPath, metadataPath);
    } catch (error) {
      if (replaced) {
        if (hasBackup) {
          try {
            await fs.rename(backupPath, overridePath);
          } catch (rollbackError) {
            preserveBackup = true;
            throw new Error('database rollback failed; previous database preserved at backup: ' + String(rollbackError));
          }
        } else {
          await removeFileQuietly(overridePath);
        }
      }
      throw new Error('database save failed: ' + String(error));
    } finally {
      await removeFileQuietly(overrideTempPath);
      await removeFileQuietly(metadataTempPath);
      if (!preserveBackup) {
        await removeFileQuietly(backupPath);
      }
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


  private async buildTranslationMap(entries: EhTagSuggestion[]): Promise<Map<string, string>> {
    const next: Map<string, string> = new Map<string, string>();
    for (let i = 0; i < entries.length; i++) {
      next.set(entries[i].tag.toLowerCase(), entries[i].translated);
      if ((i + 1) % 512 === 0) {
        await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 0); });
      }
    }
    return next;
  }
}

export const ehTagTranslationStore = new EhTagTranslationStore();

async function requestTagDatabaseText(url: string, accept: string): Promise<string> {
  const request = acquireHttpRequest();
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
    if (plan.fronted) {
      markHttpRequestVolatile(request);
    }
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
    retireHttpRequest(request);
  }
}

function buildRequestHeaders(plan: EhRequestPlan, accept: string): Record<string, string> {
  return {
    'Host': plan.host,
    'User-Agent': 'EhViewerHarmony/' + EH_APP_VERSION_NAME,
    'Accept': accept,
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Cache-Control': 'no-cache'
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



function isValidSha(value: string): boolean {
  return /^[0-9a-f]{40}$/i.test(value.trim());
}

async function writeTextFile(path: string, value: string): Promise<void> {
  const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
  try {
    await fs.write(file.fd, value);
  } finally {
    await fs.close(file);
  }
}

async function removeFileQuietly(path: string): Promise<void> {
  try {
    await fs.unlink(path);
  } catch (_error) {
  }
}

function errorMessage(error: Object): string {
  let message = String(error);
  if (message.indexOf('Error: ') === 0) {
    message = message.substring(7);
  }
  return message.length > 0 ? message : 'network request failed';
}
