import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

const FILE_NAME: string = 'ehviewer_search_history.json';
const SEARCH_HISTORY_MAX_SIZE: number = 100;

interface SearchHistoryFile {
  version?: number;
  keywords?: string[];
}

export class EhSearchHistoryStore {
  private keywords: string[] = [];
  private context: common.UIAbilityContext | undefined = undefined;
  private loaded: boolean = false;
  private loadPromise: Promise<void> | null = null;
  private saveChain: Promise<void> = Promise.resolve();

  getKeywords(): string[] {
    return this.keywords.slice();
  }

  importKeywords(keywords: string[]): number {
    if (!Array.isArray(keywords)) {
      return 0;
    }
    const imported: string[] = [];
    for (let i = 0; i < keywords.length && imported.length < SEARCH_HISTORY_MAX_SIZE; i++) {
      if (typeof keywords[i] !== 'string') {
        continue;
      }
      const trimmed = keywords[i].trim();
      if (trimmed.length > 0 && imported.indexOf(trimmed) < 0) {
        imported.push(trimmed);
      }
    }
    const importedCount = imported.length;
    for (let i = 0; i < this.keywords.length && imported.length < SEARCH_HISTORY_MAX_SIZE; i++) {
      if (imported.indexOf(this.keywords[i]) < 0) {
        imported.push(this.keywords[i]);
      }
    }
    this.keywords = imported;
    this.queueSave();
    return importedCount;
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    if (this.loaded) {
      return;
    }
    if (this.loadPromise !== null) {
      await this.loadPromise;
      return;
    }
    this.loadPromise = this.loadNow(context);
    try {
      await this.loadPromise;
    } finally {
      this.loadPromise = null;
    }
  }

  async save(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    const pending = this.saveChain.then(() => this.saveNow(context));
    this.saveChain = pending.catch(() => {});
    await pending;
  }

  record(keyword: string): void {
    const trimmed = keyword.trim();
    if (trimmed.length === 0) {
      return;
    }
    for (let i = this.keywords.length - 1; i >= 0; i--) {
      if (this.keywords[i] === trimmed) {
        this.keywords.splice(i, 1);
      }
    }
    this.keywords.unshift(trimmed);
    if (this.keywords.length > SEARCH_HISTORY_MAX_SIZE) {
      this.keywords.splice(SEARCH_HISTORY_MAX_SIZE);
    }
    this.queueSave();
  }

  private async loadNow(context: common.UIAbilityContext): Promise<void> {
    this.keywords = readSearchHistoryFile(context.filesDir + '/' + FILE_NAME);
    this.loaded = true;
    this.queueSave();
  }

  private queueSave(): void {
    const context = this.context;
    if (context === undefined || !this.loaded) {
      return;
    }
    this.saveChain = this.saveChain.then(() => this.saveNow(context)).catch(() => {});
  }

  private async saveNow(context: common.UIAbilityContext): Promise<void> {
    writeSearchHistoryFile(context.filesDir + '/' + FILE_NAME, this.keywords);
  }
}

function readSearchHistoryFile(path: string): string[] {
  try {
    const parsed = JSON.parse(fs.readTextSync(path)) as SearchHistoryFile;
    if (!Array.isArray(parsed.keywords)) {
      return [];
    }
    const next: string[] = [];
    for (let i = 0; i < parsed.keywords.length && next.length < SEARCH_HISTORY_MAX_SIZE; i++) {
      if (typeof parsed.keywords[i] !== 'string') {
        continue;
      }
      const trimmed = parsed.keywords[i].trim();
      if (trimmed.length > 0 && next.indexOf(trimmed) < 0) {
        next.push(trimmed);
      }
    }
    return next;
  } catch (error) {
    return [];
  }
}

function writeSearchHistoryFile(path: string, keywords: string[]): void {
  let fd = -1;
  try {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    fd = file.fd;
    const payload: SearchHistoryFile = {
      version: 1,
      keywords: keywords.slice(0, SEARCH_HISTORY_MAX_SIZE)
    };
    fs.writeSync(fd, JSON.stringify(payload));
  } catch (error) {
  } finally {
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (error) {
      }
    }
  }
}

export const ehSearchHistoryStore: EhSearchHistoryStore = new EhSearchHistoryStore();
