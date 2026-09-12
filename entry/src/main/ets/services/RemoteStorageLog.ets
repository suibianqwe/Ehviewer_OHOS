import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { getAbilityContext } from '../shared/EhShared';
import { ehAppLog } from './EhAppLog';

const DOMAIN: number = 0x0000;
const TAG: string = 'RemoteStorage';

export function logRemoteStorageInfo(message: string): void {
  hilog.info(DOMAIN, TAG, message);
  const context: common.UIAbilityContext | undefined = getAbilityContext();
  if (context !== undefined) {
    ehAppLog.info(context, TAG, message);
  }
}

export function logRemoteStorageWarn(message: string): void {
  hilog.warn(DOMAIN, TAG, message);
  const context: common.UIAbilityContext | undefined = getAbilityContext();
  if (context !== undefined) {
    ehAppLog.warn(context, TAG, message);
  }
}

export function logRemoteStorageError(message: string): void {
  hilog.error(DOMAIN, TAG, message);
  const context: common.UIAbilityContext | undefined = getAbilityContext();
  if (context !== undefined) {
    ehAppLog.error(context, TAG, message);
  }
}
