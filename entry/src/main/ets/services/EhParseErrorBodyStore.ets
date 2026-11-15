import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { taskpool } from '@kit.ArkTS';
import { ehSettingsStore } from './EhSettingsStore';
import { ehAppLog } from './EhAppLog';
import { writeDiagnosticFile } from './DiagnosticLogFile';
import { redactDiagnosticExportTask } from './DiagnosticExportTask';

const MAX_PARSE_ERROR_FILES: number = 20;
const MAX_PARSE_ERROR_BYTES: number = 10 * 1024 * 1024;

export interface ParseErrorBodyEntry {
  name: string;
  path: string;
  size: number;
  modifiedTime: number;
}

export class EhParseErrorBodyStore {
  private pending: Promise<void> = Promise.resolve();
  private sequence: number = 0;

  save(source: string, url: string, statusCode: number, message: string, body: string): void {
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext');
    if (context === undefined || ehSettingsStore.getValue('save_parse_error_body', 'Off') !== 'On') return;
    const time = Date.now();
    this.sequence++;
    const name = time.toString() + '_' + this.sequence.toString() + '_' +
      source.replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 48) + '.html';
    this.pending = this.pending.then(async () => {
      const directory = this.directoryPath(context);
      try { await fs.mkdir(directory); } catch (error) {
        if ((error as BusinessError).code !== 13900015) throw new Error(String(error));
      }
      const path = directory + '/' + name;
      const limitedBody = body.length > 1024 * 1024 ? body.slice(0, 1024 * 1024) + '\n[Body truncated]' : body;
      const content = '<!--\nTime ' + new Date(time).toISOString() + '\nSource ' + source + '\nURL ' + url +
        '\nStatus ' + statusCode.toString() + '\nMessage ' + message.replace(/-->/g, '-- >') + '\n-->\n' + limitedBody;
      const safe = await taskpool.execute(redactDiagnosticExportTask, content) as string;
      await writeDiagnosticFile(path + '.tmp', safe);
      await fs.rename(path + '.tmp', path);
      const entries = await this.listFiles(context);
      let bytes = entries.reduce((total: number, entry: ParseErrorBodyEntry) => total + entry.size, 0);
      while (entries.length > MAX_PARSE_ERROR_FILES || bytes > MAX_PARSE_ERROR_BYTES) {
        const oldest = entries.pop();
        if (oldest === undefined) break;
        await fs.unlink(oldest.path);
        bytes -= oldest.size;
      }
      ehAppLog.warn(context, 'ParseErrorBody', 'Saved ' + source + ' parse body ' + name);
    }).catch((error: Error) => { ehAppLog.error(context, 'ParseErrorBody', 'Save failed ' + String(error)); });
  }

  list(context: common.UIAbilityContext): Promise<ParseErrorBodyEntry[]> {
    const result = this.pending.then(() => this.listFiles(context));
    this.pending = result.then(() => {}).catch(() => {});
    return result;
  }

  clear(context: common.UIAbilityContext): Promise<void> {
    const result = this.pending.then(async () => {
      for (const entry of await this.listFiles(context)) await fs.unlink(entry.path);
    });
    this.pending = result.catch(() => {});
    return result;
  }

  directoryPath(context: common.UIAbilityContext): string {
    return context.filesDir + '/parse_error_bodies';
  }

  private async listFiles(context: common.UIAbilityContext): Promise<ParseErrorBodyEntry[]> {
    let names: string[];
    const directory = this.directoryPath(context);
    try { names = await fs.listFile(directory); } catch (error) {
      if ((error as BusinessError).code === 13900002) return [];
      throw new Error(String(error));
    }
    const entries: ParseErrorBodyEntry[] = [];
    for (const name of names) {
      if (!name.endsWith('.html')) continue;
      const path = directory + '/' + name;
      const stat = await fs.stat(path);
      if (!stat.isDirectory()) entries.push({ name: name, path: path, size: stat.size, modifiedTime: stat.mtime });
    }
    entries.sort((a: ParseErrorBodyEntry, b: ParseErrorBodyEntry) => b.modifiedTime - a.modifiedTime);
    return entries;
  }
}

export const ehParseErrorBodyStore: EhParseErrorBodyStore = new EhParseErrorBodyStore();
