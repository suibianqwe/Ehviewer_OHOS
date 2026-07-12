import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { uiText } from '../shared/EhShared';
import { ehSettingsStore } from './EhSettingsStore';

let notificationPermissionRequest: Promise<boolean> | null = null;
export const DOWNLOAD_NOTIFICATION_OPEN_DIRECTORY_KEY: string = 'ehviewer_open_download_directory';

export interface DownloadNotificationText {
  title: string;
  fileName: string;
}

export function downloadNotificationText(fileName: string, status: string = 'Downloading',
  speedText: string = ''): DownloadNotificationText {
  let visibleFileName = ehSettingsStore.getValue('enable_secure', 'Off') === 'On' ?
    uiText('EhViewer download') : fileName;
  if (speedText.length > 0) {
    visibleFileName += ' · ' + speedText;
  }
  return {
    title: uiText(status),
    fileName: visibleFileName
  };
}

export async function publishDownloadResultNotification(context: common.UIAbilityContext, id: number,
  fileName: string, status: string, directory: string = ''): Promise<void> {
  try {
    const text = downloadNotificationText(fileName, status);
    const request: notificationManager.NotificationRequest = {
      id: id,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: text.title,
          text: text.fileName,
          additionalText: ''
        }
      },
      notificationSlotType: notificationManager.SlotType.OTHER_TYPES,
      isOngoing: false
    };
    if (directory.length > 0) {
      request.wantAgent = await createOpenDownloadDirectoryAgent(directory, id);
    }
    await notificationManager.addSlot(notificationManager.SlotType.OTHER_TYPES).catch(() => {});
    await notificationManager.publish(request);
  } catch (error) {
  }
}

async function createOpenDownloadDirectoryAgent(directory: string, requestCode: number): Promise<WantAgent> {
  const parameters: Record<string, Object> = {};
  parameters[DOWNLOAD_NOTIFICATION_OPEN_DIRECTORY_KEY] = directory;
  const info: wantAgent.WantAgentInfo = {
    wants: [
      {
        bundleName: 'yt.ehviewer.huawei',
        moduleName: 'entry',
        abilityName: 'EntryAbility',
        parameters: parameters
      }
    ],
    actionType: wantAgent.OperationType.START_ABILITY,
    requestCode: requestCode,
    actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
  };
  try {
    return await wantAgent.getWantAgent(info);
  } catch (error) {
    throw new Error(String(error));
  }
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
