import { common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';

let notificationPermissionRequest: Promise<boolean> | null = null;

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
