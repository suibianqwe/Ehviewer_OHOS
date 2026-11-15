import { common } from '@kit.AbilityKit';
import { taskpool } from '@kit.ArkTS';
import { DiagnosticLogFile } from './DiagnosticLogFile';
import { formatAppDiagnosticLogTask } from './DiagnosticExportTask';
import { ehSettingsStore } from './EhSettingsStore';

export class EhAppLog {
  private file: DiagnosticLogFile = new DiagnosticLogFile('ehviewer_app.log', 512 * 1024);
  private remoteFile: DiagnosticLogFile = new DiagnosticLogFile('ehviewer_remote_storage.log', 128 * 1024);

  info(context: common.UIAbilityContext | undefined, tag: string, message: string): void {
    this.write(context, 'INFO', tag, message);
  }

  warn(context: common.UIAbilityContext | undefined, tag: string, message: string): void {
    this.write(context, 'WARN', tag, message);
  }

  error(context: common.UIAbilityContext | undefined, tag: string, message: string): void {
    this.write(context, 'ERROR', tag, message);
  }

  write(context: common.UIAbilityContext | undefined, level: string, tag: string, message: string): void {
    if (context === undefined || ehSettingsStore.getValue('save_crash_log', 'Off') !== 'On') return;
    const file = tag === 'RemoteStorage' ? this.remoteFile : this.file;
    file.append(context.filesDir, new Date().toISOString() + ' [' + level + '] ' + tag + ': ' + message + '\n');
  }

  async read(context: common.UIAbilityContext): Promise<string> {
    const logs = await Promise.all([
      this.file.read(context.filesDir).catch((error: Error) => '[Log read failed] ' + String(error) + '\n'),
      this.remoteFile.read(context.filesDir).catch((error: Error) => '[Log read failed] ' + String(error) + '\n')
    ]);
    return await taskpool.execute(formatAppDiagnosticLogTask, logs[0], logs[1]) as string;
  }

  async clear(context: common.UIAbilityContext): Promise<void> {
    await Promise.all([this.file.clear(context.filesDir), this.remoteFile.clear(context.filesDir)]);
  }
}

export const ehAppLog: EhAppLog = new EhAppLog();
