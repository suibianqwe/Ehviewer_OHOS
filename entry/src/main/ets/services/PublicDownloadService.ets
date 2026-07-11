import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ehCookieStore } from './EhCookieStore';

const DOWNLOAD_USER_AGENT: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36';

export interface PublicDownloadStartResult {
  taskId: string;
  path: string;
}

export async function startPublicDownload(context: common.UIAbilityContext, url: string, referer: string,
  directory: string, fileName: string, title: string): Promise<PublicDownloadStartResult> {
  try {
    ensureDirectory(directory);
    const path = uniqueDownloadPath(directory, sanitizeFileName(fileName));
    const headers: Record<string, string> = {};
    headers['Referer'] = referer;
    headers['Cookie'] = ehCookieStore.getCookieHeaderForUrl(url);
    headers['User-Agent'] = DOWNLOAD_USER_AGENT;
    headers['Accept'] = '*/*';

    const config: request.agent.Config = {
      action: request.agent.Action.DOWNLOAD,
      url: url,
      title: title,
      description: 'EhViewer archive download',
      mode: request.agent.Mode.BACKGROUND,
      overwrite: false,
      method: 'GET',
      headers: headers,
      saveas: path,
      network: request.agent.Network.ANY,
      metered: true,
      roaming: true
    };
    const task = await request.agent.create(context, config);
    await task.start();
    return { taskId: task.tid, path: path };
  } catch (error) {
    throw new Error(String(error));
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
