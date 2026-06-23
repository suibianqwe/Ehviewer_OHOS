import { fileIo as fs } from '@kit.CoreFileKit';

export function stripFileScheme(path: string): string {
  return path.indexOf('file://') === 0 ? path.substring('file://'.length) : path;
}

export function readerImageFileName(index: number, sourcePath: string, sourceUrl: string): string {
  const ext = readerImageExtension(sourcePath.length > 0 ? sourcePath : sourceUrl);
  return 'ehviewer_page_' + (index + 1).toString() + ext;
}

export function readerImageExtension(value: string): string {
  const lower = value.toLowerCase();
  const queryIndex = lower.indexOf('?');
  const clean = queryIndex >= 0 ? lower.substring(0, queryIndex) : lower;
  const slash = clean.lastIndexOf('/');
  const dot = clean.lastIndexOf('.');
  if (dot > slash && dot >= 0) {
    const ext = clean.substring(dot);
    if (ext === '.jpg' || ext === '.jpeg' || ext === '.png' || ext === '.webp' || ext === '.gif') {
      return ext;
    }
  }
  return '.jpg';
}

export function albumImageFileType(sourcePath: string): string {
  const extension = readerImageExtension(sourcePath);
  if (extension === '.jpeg') {
    return 'jpeg';
  }
  if (extension === '.jpg') {
    return 'jpeg';
  }
  if (extension === '.png') {
    return 'png';
  }
  if (extension === '.webp') {
    return 'webp';
  }
  if (extension === '.gif') {
    return 'gif';
  }
  return 'jpeg';
}

export function addUniquePath(paths: string[], path?: string): void {
  if (path === undefined || path.length === 0) {
    return;
  }
  const clean = stripFileScheme(path);
  if (clean.length === 0) {
    return;
  }
  for (let i = 0; i < paths.length; i++) {
    if (paths[i] === clean) {
      return;
    }
  }
  paths.push(clean);
}

export function removeFileIfExists(path: string): boolean {
  if (path.length === 0) {
    return false;
  }
  try {
    if (!fs.accessSync(path)) {
      return false;
    }
    fs.unlinkSync(path);
    return true;
  } catch (error) {
    return false;
  }
}

export function copyFileContent(sourcePath: string, targetUri: string): boolean {
  let sourceFd = -1;
  let targetFd = -1;
  try {
    const sourceFile = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY);
    sourceFd = sourceFile.fd;
    const stat = fs.statSync(sourceFd);
    const buffer = new ArrayBuffer(stat.size);
    fs.readSync(sourceFd, buffer);
    const targetFile = fs.openSync(targetUri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    targetFd = targetFile.fd;
    fs.writeSync(targetFd, buffer);
    return true;
  } catch (error) {
    return false;
  } finally {
    if (sourceFd >= 0) {
      try {
        fs.closeSync(sourceFd);
      } catch (error) {
      }
    }
    if (targetFd >= 0) {
      try {
        fs.closeSync(targetFd);
      } catch (error) {
      }
    }
  }
}
