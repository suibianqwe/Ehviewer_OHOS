import { common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { uiText } from '../shared/EhShared';
import { ehSettingsStore } from './EhSettingsStore';

let notificationPermissionRequest: Promise<boolean> | null = null;

export interface DownloadNotificationText {
  title: string;
  fileName: string;
}

export function downloadNotificationText(fileName: string, speedText: string = ''): DownloadNotificationText {
  let visibleFileName = ehSettingsStore.getValue('enable_secure', 'Off') === 'On' ? uiText('Downloading') : fileName;
  if (speedText.length > 0) {
    visibleFileName += ' · ' + speedText;
  }
  return {
    title: uiText('EhViewer download'),
    fileName: visibleFileName
  };
}

export async function ensureDownloadNotificationEnabled(context: common.UIAbilityContext): Promise<boolean> {
  if (notificationPermissionRequest !== null) {
    return notificationPermissionRequest;
  }
  notificationPermissionRequest = requestDownloadNotificationPermission(context);
  try {
    return await notificationPermissionRequest;
  } finally {
    notificationPermissionRequest = null;
  }
}

async function requestDownloadNotificationPermission(context: common.UIAbilityContext): Promise<boolean> {
  try {
    if (await notificationManager.isNotificationEnabled()) {
      return true;
    }
    await notificationManager.requestEnableNotification(context);
    return await notificationManager.isNotificationEnabled();
  } catch (error) {
    return false;
  }
}
