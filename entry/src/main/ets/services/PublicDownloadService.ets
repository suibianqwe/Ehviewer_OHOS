import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ehCookieStore } from './EhCookieStore';
import { ehAppLog } from './EhAppLog';
import {
  DownloadNotificationText,
  downloadNotificationText,
  ensureDownloadNotificationEnabled,
  publishDownloadResultNotification
} from './DownloadNotificationSupport';

const DOWNLOAD_USER_AGENT: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36';
const PUBLIC_DOWNLOAD_CACHE_DIRECTORY: string = 'public_downloads';
const ACTIVE_PUBLIC_DOWNLOAD_TASKS: request.agent.Task[] = [];
const ARCHIVE_NOTIFICATION_ID_BASE: number = 9000;
let nextArchiveNotificationId: number = ARCHIVE_NOTIFICATION_ID_BASE;

export interface PublicDownloadStartResult {
  taskId: string;
  path: string;
}

export async function startPublicDownload(context: common.UIAbilityContext, url: string, referer: string,
  directory: string, fileName: string, title: string): Promise<PublicDownloadStartResult> {
  try {
    ensureDirectory(directory);
    const path = uniqueDownloadPath(directory, sanitizeFileName(fileName));
    const cacheDirectory = context.cacheDir + '/' + PUBLIC_DOWNLOAD_CACHE_DIRECTORY;
    ensureDirectory(cacheDirectory);
    const cachePath = uniqueDownloadPath(cacheDirectory, Date.now().toString() + '_' + sanitizeFileName(fileName));
    const headers: Record<string, string> = {};
    headers['Referer'] = referer;
    headers['Cookie'] = ehCookieStore.getCookieHeaderForUrl(url);
    headers['User-Agent'] = DOWNLOAD_USER_AGENT;
    headers['Accept'] = '*/*';
    await ensureDownloadNotificationEnabled(context);
    const displayName = title.length > 0 ? title : sanitizeFileName(fileName);
    const notificationText: DownloadNotificationText = downloadNotificationText(displayName, 'Downloading');
    const notificationId = allocateArchiveNotificationId();

    const config: request.agent.Config = {
      action: request.agent.Action.DOWNLOAD,
      url: url,
      title: notificationText.fileName,
      description: 'EhViewer archive download',
      mode: request.agent.Mode.BACKGROUND,
      overwrite: false,
      method: 'GET',
      headers: headers,
      saveas: cachePath,
      network: request.agent.Network.ANY,
      metered: true,
      roaming: true,
      gauge: true,
      notification: {
        title: notificationText.title,
        text: notificationText.fileName,
        visibility: request.agent.VISIBILITY_PROGRESS
      }
    };
    const task = await request.agent.create(context, config);
    const completed = (_progress: request.agent.Progress): void => {
      const saved = finishPublicDownload(context, task, cachePath, path, completed, failed);
      publishDownloadResultNotification(context, notificationId, displayName,
        saved ? 'Download completed' : 'Download failed', saved ? directory : '').catch(() => {});
    };
    const failed = (_progress: request.agent.Progress): void => {
      ehAppLog.error(context, 'PublicDownload', 'Download task failed tid=' + task.tid + ', target=' + path);
      removeFileQuietly(cachePath);
      releasePublicDownloadTask(task, completed, failed);
      publishDownloadResultNotification(context, notificationId, displayName, 'Download failed').catch(() => {});
    };
    task.on('completed', completed);
    task.on('failed', failed);
    ACTIVE_PUBLIC_DOWNLOAD_TASKS.push(task);
    try {
      await task.start();
    } catch (error) {
      releasePublicDownloadTask(task, completed, failed);
      removeFileQuietly(cachePath);
      throw new Error(String(error));
    }
    return { taskId: task.tid, path: path };
  } catch (error) {
    throw new Error(String(error));
  }
}

function finishPublicDownload(context: common.UIAbilityContext, task: request.agent.Task, cachePath: string,
  targetPath: string, completed: (progress: request.agent.Progress) => void,
  failed: (progress: request.agent.Progress) => void): boolean {
  const partPath = targetPath + '.part';
  let saved = false;
  try {
    removeFileQuietly(partPath);
    fs.copyFileSync(cachePath, partPath);
    fs.moveFileSync(partPath, targetPath);
    saved = true;
    ehAppLog.info(context, 'PublicDownload', 'Saved download tid=' + task.tid + ', target=' + targetPath);
  } catch (error) {
    removeFileQuietly(partPath);
    ehAppLog.error(context, 'PublicDownload', 'Saving public download failed tid=' + task.tid + ', target=' +
      targetPath + ': ' + String(error));
  } finally {
    removeFileQuietly(cachePath);
    releasePublicDownloadTask(task, completed, failed);
  }
  return saved;
}

function allocateArchiveNotificationId(): number {
  nextArchiveNotificationId++;
  if (nextArchiveNotificationId > 9999) {
    nextArchiveNotificationId = ARCHIVE_NOTIFICATION_ID_BASE + 1;
  }
  return nextArchiveNotificationId;
}

function releasePublicDownloadTask(task: request.agent.Task,
  completed: (progress: request.agent.Progress) => void,
  failed: (progress: request.agent.Progress) => void): void {
  try {
    task.off('completed', completed);
  } catch (error) {
  }
  try {
    task.off('failed', failed);
  } catch (error) {
  }
  const index = ACTIVE_PUBLIC_DOWNLOAD_TASKS.indexOf(task);
  if (index >= 0) {
    ACTIVE_PUBLIC_DOWNLOAD_TASKS.splice(index, 1);
  }
  request.agent.remove(task.tid).catch((_error: Error) => {
  });
}

function removeFileQuietly(path: string): void {
  try {
    fs.unlinkSync(path);
  } catch (error) {
  }
}

function ensureDirectory(path: string): void {
  try {
    if (!fs.accessSync(path)) {
      fs.mkdirSync(path, true);
    }
  } catch (error) {
    throw new Error(String(error));
  }
}

function uniqueDownloadPath(directory: string, fileName: string): string {
  const dot = fileName.lastIndexOf('.');
  const stem = dot > 0 ? fileName.substring(0, dot) : fileName;
  const extension = dot > 0 ? fileName.substring(dot) : '';
  let path = directory + '/' + fileName;
  let suffix = 2;
  while (pathExists(path)) {
    path = directory + '/' + stem + ' (' + suffix.toString() + ')' + extension;
    suffix++;
  }
  return path;
}

function pathExists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (error) {
    return false;
  }
}

function sanitizeFileName(value: string): string {
  let result = value.replace(/[\\/:*?"<>|]/g, '_').replace(/\s+/g, ' ').trim();
  if (result.length === 0) {
    result = 'EhViewer_archive.zip';
  }
  if (result.length > 180) {
    const dot = result.lastIndexOf('.');
    const extension = dot > 0 ? result.substring(dot) : '';
    result = result.substring(0, Math.max(1, 180 - extension.length)).trim() + extension;
  }
  return result;
}
