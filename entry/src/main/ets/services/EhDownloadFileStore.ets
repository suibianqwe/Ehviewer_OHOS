import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { GalleryDetail, GalleryInfo, GalleryPage } from '../model/GalleryModels';

interface GalleryMetadata {
  version: number;
  gid: number;
  token: string;
  title: string;
  titleJpn: string;
  thumb: string;
  category: number;
  posted: string;
  uploader: string;
  rating: number;
  pages: number;
  previewPages: number;
  savedAt: number;
}

export interface RestoredDownloadGallery {
  gallery: GalleryInfo;
  directory: string;
  fileSize: number;
  finished: number;
  total: number;
}

export interface DownloadDirectoryScanResult {
  directories: number;
  files: number;
  bytes: number;
}

const SUPPORTED_IMAGE_EXTENSIONS: string[] = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];

export class EhDownloadFileStore {
  galleryDirectory(context: common.UIAbilityContext, gallery: GalleryInfo): string {
    const root = this.downloadRoot(context);
    return root + '/' + sanitizePathSegment(gallery.gid.toString() + '-' + gallery.title);
  }

  prepareGallery(context: common.UIAbilityContext, detail: GalleryDetail): string {
    const root = this.downloadRoot(context);
    ensureDirectory(root);
    const directory = this.galleryDirectory(context, detail);
    ensureDirectory(directory);
    writeTextFile(directory + '/.ehviewer', JSON.stringify(createMetadata(detail)));
    return directory;
  }

  savePageImage(context: common.UIAbilityContext, detail: GalleryDetail, page: GalleryPage, index: number,
    cachedPath: string): string {
    const directory = this.galleryDirectory(context, detail);
    ensureDirectory(directory);
    const destination = directory + '/' + pageFileName(index, imageExtension(page, cachedPath));
    try {
      fs.copyFileSync(cachedPath, destination);
    } catch (error) {
      throw new Error(String(error));
    }
    return destination;
  }

  findPageImage(context: common.UIAbilityContext, detail: GalleryDetail, index: number): string {
    const directory = this.galleryDirectory(context, detail);
    for (let i = 0; i < SUPPORTED_IMAGE_EXTENSIONS.length; i++) {
      const path = directory + '/' + pageFileName(index, SUPPORTED_IMAGE_EXTENSIONS[i]);
      if (exists(path)) {
        return path;
      }
    }
    return '';
  }

  directorySize(context: common.UIAbilityContext, gallery: GalleryInfo): number {
    const directory = this.galleryDirectory(context, gallery);
    return this.directorySizeByPath(directory);
  }

  restoreDownloadedGalleries(context: common.UIAbilityContext): RestoredDownloadGallery[] {
    const root = this.downloadRoot(context);
    const restored: RestoredDownloadGallery[] = [];
    try {
      const names = fs.listFileSync(root);
      for (let i = 0; i < names.length; i++) {
        const directory = root + '/' + names[i];
        const metadata = readMetadata(directory + '/.ehviewer');
        if (metadata === null) {
          continue;
        }
        restored.push({
          gallery: metadataToGallery(metadata),
          directory: directory,
          fileSize: this.directorySizeByPath(directory),
          finished: countImageFiles(directory),
          total: Math.max(0, metadata.pages)
        });
      }
    } catch (error) {
    }
    return restored;
  }

  scanRedundantDirectories(context: common.UIAbilityContext, keepGids: number[]): DownloadDirectoryScanResult {
    const root = this.downloadRoot(context);
    let directories = 0;
    let files = 0;
    let bytes = 0;
    try {
      const names = fs.listFileSync(root);
      for (let i = 0; i < names.length; i++) {
        const directory = root + '/' + names[i];
        const metadata = readMetadata(directory + '/.ehviewer');
        if (metadata === null || containsNumber(keepGids, metadata.gid)) {
          continue;
        }
        directories++;
        files += countImageFiles(directory);
        bytes += this.directorySizeByPath(directory);
      }
    } catch (error) {
    }
    return { directories: directories, files: files, bytes: bytes };
  }

  directorySizeByPath(directory: string): number {
    let total = 0;
    try {
      const names = fs.listFileSync(directory);
      for (let i = 0; i < names.length; i++) {
        const path = directory + '/' + names[i];
        total += this.statFileSize(path);
      }
    } catch (error) {
    }
    return total;
  }

  statFileSize(path: string): number {
    try {
      return fs.statSync(path).size;
    } catch (error) {
      return 0;
    }
  }

  private downloadRoot(context: common.UIAbilityContext): string {
    return context.filesDir + '/downloads';
  }
}

function createMetadata(detail: GalleryDetail): GalleryMetadata {
  return {
    version: 1,
    gid: detail.gid,
    token: detail.token,
    title: detail.title,
    titleJpn: detail.titleJpn === undefined ? '' : detail.titleJpn,
    thumb: detail.thumb === undefined ? '' : detail.thumb,
    category: detail.category,
    posted: detail.posted === undefined ? '' : detail.posted,
    uploader: detail.uploader === undefined ? '' : detail.uploader,
    rating: detail.rating,
    pages: detail.pages,
    previewPages: detail.previewPages,
    savedAt: Date.now()
  };
}

function readMetadata(path: string): GalleryMetadata | null {
  try {
    const parsed = JSON.parse(fs.readTextSync(path)) as GalleryMetadata;
    if (parsed.gid <= 0 || parsed.token === undefined || parsed.token.length === 0 ||
      parsed.title === undefined || parsed.title.length === 0) {
      return null;
    }
    return parsed;
  } catch (error) {
    return null;
  }
}

function metadataToGallery(metadata: GalleryMetadata): GalleryInfo {
  return {
    gid: metadata.gid,
    token: metadata.token,
    title: metadata.title,
    titleJpn: metadata.titleJpn,
    thumb: metadata.thumb,
    category: metadata.category,
    posted: metadata.posted,
    uploader: metadata.uploader,
    rating: metadata.rating,
    rated: false,
    pages: metadata.pages,
    thumbWidth: 0,
    thumbHeight: 0,
    favoriteSlot: -1,
    favoriteName: ''
  };
}

function countImageFiles(directory: string): number {
  let count = 0;
  try {
    const names = fs.listFileSync(directory);
    for (let i = 0; i < names.length; i++) {
      if (isSupportedImageFile(names[i])) {
        count++;
      }
    }
  } catch (error) {
  }
  return count;
}

function isSupportedImageFile(name: string): boolean {
  const lower = name.toLowerCase();
  for (let i = 0; i < SUPPORTED_IMAGE_EXTENSIONS.length; i++) {
    if (lower.endsWith(SUPPORTED_IMAGE_EXTENSIONS[i])) {
      return true;
    }
  }
  return false;
}

function containsNumber(values: number[], value: number): boolean {
  for (let i = 0; i < values.length; i++) {
    if (values[i] === value) {
      return true;
    }
  }
  return false;
}

function sanitizePathSegment(value: string): string {
  let result = value
    .replace(/[\\/:*?"<>|]/g, '_')
    .replace(/\s+/g, ' ')
    .trim();
  if (result.length === 0) {
    result = 'gallery';
  }
  if (result.length > 120) {
    result = result.substring(0, 120).trim();
  }
  return result;
}

function pageFileName(index: number, extension: string): string {
  let value = Math.max(0, index + 1).toString();
  while (value.length < 8) {
    value = '0' + value;
  }
  return value + extension;
}

function imageExtension(page: GalleryPage, cachedPath: string): string {
  const source = cachedPath.length > 0 ? cachedPath : (page.originImageUrl.length > 0 ? page.originImageUrl : page.imageUrl);
  const clean = source.split('?')[0].toLowerCase();
  const dot = clean.lastIndexOf('.');
  if (dot >= 0) {
    const extension = clean.substring(dot);
    for (let i = 0; i < SUPPORTED_IMAGE_EXTENSIONS.length; i++) {
      if (extension === SUPPORTED_IMAGE_EXTENSIONS[i]) {
        return extension;
      }
    }
  }
  return '.jpg';
}

function ensureDirectory(path: string): void {
  if (exists(path)) {
    return;
  }
  try {
    fs.mkdirSync(path);
  } catch (error) {
  }
}

function writeTextFile(path: string, value: string): void {
  let fd = -1;
  try {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    fd = file.fd;
    fs.writeSync(fd, value);
  } catch (error) {
    throw new Error(String(error));
  } finally {
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (error) {
      }
    }
  }
}

function exists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (error) {
    return false;
  }
}

export const ehDownloadFileStore: EhDownloadFileStore = new EhDownloadFileStore();
