import { AbilityConstant, common, errorManager } from '@kit.AbilityKit';
import { hiAppEvent } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { ehSettingsStore } from './EhSettingsStore';
import { ehAppLog } from './EhAppLog';
import { readDiagnosticFile, writeDiagnosticFile } from './DiagnosticLogFile';
import { isAbnormalExit } from './DiagnosticLogSupport';
import { redactDiagnosticExportTask } from './DiagnosticExportTask';

interface FaultParams {
  time?: number;
  bundle_name?: string;
  external_log?: string[];
  log_over_limit?: boolean;
}

interface SavedFault {
  time: number;
  identity: string;
  content: string;
}

const FAULT_DIRECTORY: string = '/data/storage/el2/log/hiappevent';
const FAULT_LIMIT: number = 6 * 1024 * 1024;

export class EhFaultLogStore {
  private context: common.UIAbilityContext | undefined = undefined;
  private pending: Promise<void> = Promise.resolve();
  private latest: SavedFault = { time: 0, identity: '', content: '' };
  private status: string = '';
  private subscriptionStatus: string = '';
  private lastExit: string = '';
  private abnormalExit: boolean = false;

  initialize(context: common.UIAbilityContext, launch?: AbilityConstant.LaunchParam): void {
    if (this.context !== undefined) return;
    this.context = context;
    this.pending = this.load(context);
    if (launch !== undefined) {
      this.abnormalExit = isAbnormalExit(launch.lastExitReason);
      this.lastExit = 'Observed at ' + new Date().toISOString() + '\nReason ' + launch.lastExitReason.toString() +
        '\nMessage ' + launch.lastExitMessage;
      if (this.abnormalExit) this.lastExit += '\nSystem reported an abnormal previous exit.';
    }
    // Register once per process, independently of the run-log setting. The
    // system must observe the fault before it can supply its attachment.
    try {
      const holder = hiAppEvent.addWatcher({ name: 'EhViewerFaults', appEventFilters: [{ domain: hiAppEvent.domain.OS,
        names: [hiAppEvent.event.APP_CRASH, hiAppEvent.event.APP_FREEZE] }],
        onReceive: (_domain: string, groups: hiAppEvent.AppEventGroup[]) => {
          for (const group of groups) {
            for (const event of group.appEventInfos) this.enqueue(event);
          }
        } });
      this.subscriptionStatus = holder === null ? 'System fault subscription unavailable' :
        'System fault subscription active since ' + new Date().toISOString();
    } catch (error) { this.subscriptionStatus = 'System fault subscription failed ' + String(error); }
    try {
      errorManager.on('error', { onUnhandledException: (message: string): void => {
        ehSettingsStore.ensureLoaded(context).then(() => {
          ehAppLog.error(context, 'AppCrash', message);
        }).catch(() => {});
      } });
    } catch (error) { this.status += '\nException observer failed ' + String(error); }
    this.pending = this.pending.then(() => this.recoverFiles()).catch((error: Error) => {
      this.status += '\nFault recovery failed ' + String(error);
    });
  }

  read(): Promise<string> {
    const result = this.pending.then(async () => {
      // The system may finish writing an attachment after startup recovery.
      try { await this.recoverFiles(); } catch (error) {
        this.status = 'Fault recovery failed ' + String(error);
      }
      let missing = 'No captured fault attachment.';
      if (this.latest.identity === 'cleared') missing += '\nSaved faults cleared at ' + new Date(this.latest.time).toISOString();
      if (this.abnormalExit) missing += '\nThe system reported an abnormal previous exit. Its attachment is unavailable.';
      missing += '\nAttachments require subscription before the fault and a subsequent app start.' +
        '\nSystem fault reports can arrive later. Export again after about two minutes if a fault just occurred.' +
        '\nAn active subscription confirms registration only. An empty report cannot exclude an earlier fault.';
      return '[Previous process exit]\n' + (this.lastExit || '(unavailable)') +
        '\n\n[Most recent system fault]\n' + (this.latest.content || missing) +
        '\n\n[Fault collection status]\n' + this.subscriptionStatus + (this.status ? '\n' + this.status : '');
    });
    this.pending = result.then(() => {}).catch(() => {});
    return result;
  }

  clear(): Promise<void> {
    const result = this.pending.then(async () => {
      // A timestamp tombstone prevents delayed old events from restoring a
      // fault that the user cleared.
      await this.save({ time: Date.now(), identity: 'cleared', content: '' });
    });
    this.pending = result.catch((error: Error) => { this.status = 'Clear fault failed ' + String(error); });
    return result;
  }

  private async load(context: common.UIAbilityContext): Promise<void> {
    try {
      const raw = await readDiagnosticFile(context.filesDir + '/ehviewer_latest_fault.json', FAULT_LIMIT * 2);
      if (raw.length > 0) {
        const saved = JSON.parse(raw) as SavedFault;
        if (Number.isFinite(saved.time) && typeof saved.identity === 'string' && typeof saved.content === 'string') {
          this.latest = saved;
        }
      }
    } catch (error) { this.status = 'Saved fault unavailable ' + String(error); }
  }

  private enqueue(event: hiAppEvent.AppEventInfo): void {
    if (event.name !== hiAppEvent.event.APP_CRASH && event.name !== hiAppEvent.event.APP_FREEZE) return;
    const params = event.params as FaultParams;
    if (params.bundle_name !== undefined && params.bundle_name !== 'yt.ehviewer.huawei') return;
    const time = params.time;
    if (time === undefined || !Number.isFinite(time) || time <= 0) return;
    this.pending = this.pending.then(async () => {
      const metadata = JSON.stringify(event.params, null, 2);
      await this.capture(time, event.name, metadata.length > 512 * 1024 ?
        metadata.slice(0, 512 * 1024) + '\n[Additional event metadata omitted]' : metadata, params.external_log ?? []);
    }).catch((error: Error) => { this.status = 'Fault capture failed ' + String(error); });
  }

  private async capture(time: number, name: string, metadata: string, paths: string[]): Promise<void> {
    const identity = name + ':' + time.toString();
    if (time < this.latest.time || (time === this.latest.time && this.latest.identity === 'cleared')) {
      await this.removeAttachments(paths);
      return;
    }
    // Timestamp formatting runs once per captured fault.
    // eslint-disable-next-line @performance/reuse-date-instances-check
    let content = 'Event ' + name + '\nTime ' + new Date(time).toISOString() + '\n' + metadata;
    const retainedAttachment = this.latest.content.indexOf('\n\n[System fault attachment]\n');
    if (identity === this.latest.identity && retainedAttachment >= 0) {
      // Recovery may copy and remove the system file before onReceive brings
      // its structured event. Enrich the metadata while retaining that copy.
      if (metadata !== '[Recovered system attachment]') {
        content += this.latest.content.substring(retainedAttachment);
        content = await taskpool.execute(redactDiagnosticExportTask, content) as string;
        await this.save({ time: time, identity: identity, content: content });
      }
      return;
    }
    let remaining = FAULT_LIMIT;
    const capturedPaths: string[] = [];
    for (const path of paths) {
      if (!this.isFaultPath(path) || remaining <= 0) continue;
      try {
        const text = await readDiagnosticFile(path, remaining);
        if (text.length === 0) {
          content += '\n[Fault attachment unavailable] ' + path;
        } else {
          content += '\n\n[System fault attachment]\n' + text;
          capturedPaths.push(path);
          remaining = Math.max(0, remaining - text.length * 4);
        }
      } catch (error) { content += '\n[Fault attachment read failed] ' + String(error); }
    }
    if (paths.length === 0) content += '\n[No external fault attachment supplied by the system]';
    // Do not let a duplicate event with a missing/deleted attachment replace
    // the complete copy already retained on disk.
    if (identity === this.latest.identity && content.length <= this.latest.content.length) return;
    content = await taskpool.execute(redactDiagnosticExportTask, content) as string;
    await this.save({ time: time, identity: identity, content: content });
    if (this.status.startsWith('Fault capture failed') || this.status.startsWith('Fault recovery failed')) {
      this.status = 'Previous fault collection failure recovered';
    }
    await this.removeAttachments(capturedPaths);
  }

  private async save(fault: SavedFault): Promise<void> {
    const context = this.context;
    if (context === undefined) return;
    const path = context.filesDir + '/ehviewer_latest_fault.json';
    await writeDiagnosticFile(path + '.tmp', JSON.stringify(fault));
    await fs.rename(path + '.tmp', path);
    this.latest = fault;
  }

  private isFaultPath(path: string): boolean {
    return /^\/data\/storage\/el2\/log\/hiappevent\/(APP_CRASH|APP_FREEZE)_\d+_[^/]+\.log$/.test(path);
  }

  private async removeAttachments(paths: string[]): Promise<void> {
    for (const path of paths) {
      if (this.isFaultPath(path)) {
        try { await fs.unlink(path); } catch (_error) {}
      }
    }
  }

  private async recoverFiles(): Promise<void> {
    let names: string[];
    try { names = await fs.listFile(FAULT_DIRECTORY); } catch (error) {
      if ((error as BusinessError).code === 13900002) return;
      throw new Error(String(error));
    }
    names.sort();
    for (const name of names) {
      const match = /^(APP_CRASH|APP_FREEZE)_(\d+)_[^/]+\.log$/.exec(name);
      if (match !== null) {
        await this.capture(Number(match[2]), match[1], '[Recovered system attachment]', [FAULT_DIRECTORY + '/' + name]);
      }
    }
  }
}

export const ehFaultLogStore: EhFaultLogStore = new EhFaultLogStore();
