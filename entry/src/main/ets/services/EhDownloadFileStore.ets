import { common } from '@kit.AbilityKit';
import { zlib } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { GalleryDetail, GalleryInfo, GalleryPage, GalleryPreview, GalleryTagGroup } from '../model/GalleryModels';
import { parseGalleryPageUrl } from './GalleryPageUrlParser';
import { ehSettingsStore } from './EhSettingsStore';

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
  simpleLanguage?: string;
  simpleTags?: string[];
  tagList?: string[];
  detailTags?: GalleryTagGroup[];
  detailLanguage?: string;
  language?: string;
  previewSet?: GalleryPreview[];
}

interface AndroidSpiderInfo {
  gid: number;
  token: string;
  pages: number;
  previewPages: number;
  previewPerPage: number;
}

interface RestoredGalleryData {
  gallery: GalleryInfo;
  total: number;
}

export interface RestoredDownloadGallery {
  gallery: GalleryInfo;
  directory: string;
  sourceDirectory?: string;
  fileSize: number;
  finished: number;
  total: number;
  migrated?: boolean;
}

export interface DownloadDirectoryScanResult {
  directories: number;
  files: number;
  bytes: number;
}

export interface DownloadZipExportResult {
  path: string;
  folders: number;
  files: number;
  bytes: number;
}

export const DOWNLOAD_LOCATION_APP_FILES: string = 'App files';
export const DOWNLOAD_LOCATION_DOWNLOADS: string = 'Downloads';

const SUPPORTED_IMAGE_EXTENSIONS: string[] = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];
const ANDROID_SPIDER_INFO_FILENAME: string = '.ehviewer';
const OHOS_METADATA_FILENAME: string = '.ehviewer.json';

export class EhDownloadFileStore {
  appDownloadRoot(context: common.UIAbilityContext): string {
    return context.filesDir + '/downloads';
  }

  rootForLocation(context: common.UIAbilityContext, location: string): string {
    if (normalizeDownloadLocation(location) === DOWNLOAD_LOCATION_DOWNLOADS) {
      return this.publicDownloadRoot(context);
    }
    return this.appDownloadRoot(context);
  }

  publicDownloadRoot(_context: common.UIAbilityContext): string {
    const pickedRoot = ehSettingsStore.getValue('download_public_root_path', '');
    if (pickedRoot.length > 0) {
      return pickedRoot;
    }
    throw new Error('Download directory access needs picker selection');
  }

  rememberPublicDownloadRoot(root: string): void {
    const normalized = normalizePath(root);
    if (normalized.length > 0) {
      ehSettingsStore.setValue('download_public_root_path', normalized);
    }
  }

  canUseLocation(context: common.UIAbilityContext, location: string): boolean {
    try {
      ensureDirectory(this.rootForLocation(context, location));
      return true;
    } catch (error) {
      return false;
    }
  }

  migrateDownloadLocation(context: common.UIAbilityContext, fromLocation: string,
    toLocation: string): DownloadDirectoryScanResult {
    const source = this.rootForLocation(context, fromLocation);
    const target = this.rootForLocation(context, toLocation);
    if (source === target || !exists(source)) {
      ensureDirectory(target);
      return { directories: 0, files: 0, bytes: 0 };
    }
    ensureDirectory(target);
    const copied = copyDirectoryTree(source, target);
    removeDirectoryTree(source);
    return copied;
  }

  galleryDirectory(context: common.UIAbilityContext, gallery: GalleryInfo): string {
    const root = this.downloadRoot(context);
    return root + '/' + sanitizePathSegment(gallery.gid.toString() + '-' + gallery.title);
  }

  downloadedGalleryDirectory(context: common.UIAbilityContext, gallery: GalleryInfo): string {
    const archiveUri = galleryArchiveUri(gallery);
    if (archiveUri.length > 0 && exists(archiveUri)) {
      return archiveUri;
    }
    const directory = this.galleryDirectory(context, gallery);
    if (exists(directory)) {
      return directory;
    }
    return this.findGalleryDirectoryByGid(context, gallery.gid);
  }

  async exportGalleriesZip(context: common.UIAbilityContext, galleries: GalleryInfo[],
    outputPath: string = ''): Promise<DownloadZipExportResult> {
    if (galleries.length <= 0) {
      throw new Error('No downloads selected');
    }

    const zipPath = outputPath.length > 0 ? outputPath :
      uniqueZipPath(this.zipExportRoot(context), 'EhViewer_downloads_' + zipTimestamp() + '.zip');
    const zipRoot = parentPath(zipPath);
    if (zipRoot.length > 0) {
      ensureDirectory(zipRoot);
    }
    const stagingRoot = context.cacheDir + '/download_zip_export_' + Date.now().toString();
    removeDirectoryTree(stagingRoot);
    ensureDirectory(stagingRoot);

    let folders = 0;
    let files = 0;
    try {
      for (let i = 0; i < galleries.length; i++) {
        const source = this.downloadedGalleryDirectory(context, galleries[i]);
        if (source.length === 0 || !isDirectory(source)) {
          continue;
        }
        const target = uniqueChildPath(stagingRoot, pathBaseName(source));
        const copied = copyDirectoryTree(source, target);
        if (copied.files > 0) {
          folders++;
          files += copied.files;
        } else {
          removeDirectoryTree(target);
        }
      }

      if (folders <= 0 || files <= 0) {
        throw new Error('Selected downloaded folders are missing');
      }

      const options: zlib.Options = {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
        memLevel: zlib.MemLevel.MEM_LEVEL_DEFAULT,
        strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY
      };
      try {
        removeFileQuietly(zipPath);
        await zlib.compressFile(stagingRoot, zipPath, options);
      } catch (error) {
        throw new Error('Zip compression failed: ' + String(error));
      }
      const bytes = this.statFileSize(zipPath);
      return {
        path: zipPath,
        folders: folders,
        files: files,
        bytes: bytes
      };
    } finally {
      removeDirectoryTree(stagingRoot);
    }
  }

  prepareGallery(context: common.UIAbilityContext, detail: GalleryDetail): string {
    const root = this.downloadRoot(context);
    ensureDirectory(root);
    const directory = this.galleryDirectory(context, detail);
    ensureDirectory(directory);
    this.rewriteGalleryMetadataByDirectory(directory, detail);
    return directory;
  }

  rewriteGalleryMetadata(context: common.UIAbilityContext, detail: GalleryDetail): string {
    const root = this.downloadRoot(context);
    ensureDirectory(root);
    const directory = this.galleryDirectory(context, detail);
    ensureDirectory(directory);
    this.rewriteGalleryMetadataByDirectory(directory, detail);
    return directory;
  }

  private rewriteGalleryMetadataByDirectory(directory: string, detail: GalleryDetail): void {
    this.rewriteGalleryMetadataForDirectory(directory, detail);
  }

  rewriteGalleryMetadataForDirectory(directory: string, gallery: GalleryInfo): void {
    const metadata = createMetadata(gallery);
    writeTextFile(directory + '/' + OHOS_METADATA_FILENAME, JSON.stringify(metadata));
    const detail = gallery as GalleryDetail;
    if (detail.previewSet !== undefined && Array.isArray(detail.previewSet)) {
      writeTextFile(directory + '/' + ANDROID_SPIDER_INFO_FILENAME, createAndroidSpiderInfo(detail));
    } else {
      writeTextFile(directory + '/' + ANDROID_SPIDER_INFO_FILENAME, createAndroidSpiderInfoFromMetadata(metadata));
    }
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

  findPageImage(context: common.UIAbilityContext, gallery: GalleryInfo, index: number): string {
    const directory = this.downloadedGalleryDirectory(context, gallery);
    for (let i = 0; i < SUPPORTED_IMAGE_EXTENSIONS.length; i++) {
      const path = directory + '/' + pageFileName(index, SUPPORTED_IMAGE_EXTENSIONS[i]);
      if (exists(path)) {
        return path;
      }
    }
    return '';
  }

  removePageImage(context: common.UIAbilityContext, gallery: GalleryInfo, index: number): DownloadDirectoryScanResult {
    const path = this.findPageImage(context, gallery, index);
    if (path.length === 0) {
      return { directories: 0, files: 0, bytes: 0 };
    }
    return removeDirectoryTree(path);
  }

  listPageImages(context: common.UIAbilityContext, gallery: GalleryInfo): string[] {
    const directory = this.downloadedGalleryDirectory(context, gallery);
    const images: string[] = [];
    try {
      const names = fs.listFileSync(directory);
      names.sort();
      for (let i = 0; i < names.length; i++) {
        if (isSupportedImageFile(names[i])) {
          images.push(directory + '/' + names[i]);
        }
      }
    } catch (error) {
    }
    return images;
  }

  listPageImageSlots(context: common.UIAbilityContext, gallery: GalleryInfo, total: number): string[] {
    const count = Math.max(0, total);
    const images: string[] = [];
    for (let i = 0; i < count; i++) {
      images.push(this.findPageImage(context, gallery, i));
    }
    return images;
  }

  directorySize(context: common.UIAbilityContext, gallery: GalleryInfo): number {
    const directory = this.downloadedGalleryDirectory(context, gallery);
    return this.directorySizeByPath(directory);
  }

  restoreDownloadedGalleries(context: common.UIAbilityContext): RestoredDownloadGallery[] {
    const currentLocation = normalizeDownloadLocation(ehSettingsStore.getValue('download_location', DOWNLOAD_LOCATION_APP_FILES));
    if (currentLocation === DOWNLOAD_LOCATION_APP_FILES) {
      return this.restoreAppFileDownloads(context);
    }
    return this.scanRestoredDownloadRoot(this.downloadRoot(context));
  }

  removeGalleryDirectory(context: common.UIAbilityContext, gallery: GalleryInfo): DownloadDirectoryScanResult {
    return removeDirectoryTree(this.downloadedGalleryDirectory(context, gallery));
  }

  scanRedundantDirectories(context: common.UIAbilityContext, keepGids: number[]): DownloadDirectoryScanResult {
    return scanRedundantDownloadDirectories(this.downloadRoot(context), keepGids, false);
  }

  cleanRedundantDirectories(context: common.UIAbilityContext, keepGids: number[]): DownloadDirectoryScanResult {
    return scanRedundantDownloadDirectories(this.downloadRoot(context), keepGids, true);
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
    return this.rootForLocation(context, ehSettingsStore.getValue('download_location', DOWNLOAD_LOCATION_APP_FILES));
  }

  private zipExportRoot(context: common.UIAbilityContext): string {
    try {
      return this.publicDownloadRoot(context);
    } catch (error) {
      throw new Error('Zip export needs Downloads access. Set Settings > EH > Download location to Downloads first.');
    }
  }

  private findGalleryDirectoryByGid(context: common.UIAbilityContext, gid: number): string {
    const root = this.downloadRoot(context);
    const prefix = gid.toString() + '-';
    try {
      const names = fs.listFileSync(root);
      let best = '';
      for (let i = 0; i < names.length; i++) {
        const path = root + '/' + names[i];
        if (names[i].startsWith(prefix) && isDirectory(path) && names[i].length > best.length) {
          best = path;
        }
      }
      return best;
    } catch (error) {
      return '';
    }
  }

  private restoreAppFileDownloads(context: common.UIAbilityContext): RestoredDownloadGallery[] {
    const appRoot = this.appDownloadRoot(context);
    ensureDirectory(appRoot);
    const appItems = this.scanRestoredDownloadRoot(appRoot);
    const publicItems = this.scanPublicDownloadedGalleries(context);
    if (publicItems.length <= 0) {
      return appItems;
    }

    const merged: RestoredDownloadGallery[] = [];
    for (let i = 0; i < appItems.length; i++) {
      merged.push(appItems[i]);
    }

    for (let i = 0; i < publicItems.length; i++) {
      this.mergePublicDownloadIntoApp(appRoot, merged, publicItems[i]);
    }
    return merged;
  }

  private scanPublicDownloadedGalleries(context: common.UIAbilityContext): RestoredDownloadGallery[] {
    try {
      const publicRoot = this.publicDownloadRoot(context);
      return this.scanRestoredDownloadRoot(publicRoot);
    } catch (error) {
      return [];
    }
  }

  private mergePublicDownloadIntoApp(appRoot: string, appItems: RestoredDownloadGallery[],
    publicItem: RestoredDownloadGallery): void {
    const existingIndex = restoredIndexByGid(appItems, publicItem.gallery.gid);
    if (existingIndex >= 0 && appItems[existingIndex].fileSize >= publicItem.fileSize) {
      removeDirectoryTree(publicItem.directory);
      return;
    }

    const target = uniqueChildPath(appRoot, pathBaseName(publicItem.directory));

    const copied = copyDirectoryTree(publicItem.directory, target);
    if (copied.files <= 0) {
      return;
    }
    removeDirectoryTree(publicItem.directory);
    if (existingIndex >= 0) {
      removeDirectoryTree(appItems[existingIndex].directory);
    }
    const migrated = this.restoredItemFromDirectory(target, true, publicItem.directory);
    if (migrated === null) {
      return;
    }
    if (existingIndex >= 0) {
      appItems[existingIndex] = migrated;
    } else {
      appItems.push(migrated);
    }
  }

  private scanRestoredDownloadRoot(root: string): RestoredDownloadGallery[] {
    const restored: RestoredDownloadGallery[] = [];
    try {
      const names = fs.listFileSync(root);
      for (let i = 0; i < names.length; i++) {
        const item = this.restoredItemFromDirectory(root + '/' + names[i], false, '');
        if (item !== null) {
          restored.push(item);
        }
      }
    } catch (error) {
    }
    return restored;
  }

  private restoredItemFromDirectory(directory: string, migrated: boolean,
    sourceDirectory: string): RestoredDownloadGallery | null {
    const restoredGallery = readRestoredGallery(directory, pathBaseName(directory));
    if (restoredGallery === null) {
      return null;
    }
    return {
      gallery: restoredGallery.gallery,
      directory: directory,
      sourceDirectory: sourceDirectory.length > 0 ? sourceDirectory : undefined,
      fileSize: this.directorySizeByPath(directory),
      finished: countImageFiles(directory),
      total: Math.max(0, restoredGallery.total),
      migrated: migrated
    };
  }
}

function restoredIndexByGid(items: RestoredDownloadGallery[], gid: number): number {
  for (let i = 0; i < items.length; i++) {
    if (items[i].gallery.gid === gid) {
      return i;
    }
  }
  return -1;
}

function scanRedundantDownloadDirectories(root: string, keepGids: number[], shouldRemove: boolean): DownloadDirectoryScanResult {
  let directories = 0;
  let files = 0;
  let bytes = 0;
  try {
    const names = fs.listFileSync(root);
    for (let i = 0; i < names.length; i++) {
      const directory = root + '/' + names[i];
      const restoredGallery = readRestoredGallery(directory, names[i]);
      if (restoredGallery === null || containsNumber(keepGids, restoredGallery.gallery.gid)) {
        continue;
      }
      const result = shouldRemove ? removeDirectoryTree(directory) : scanDirectoryTree(directory);
      directories += result.directories;
      files += result.files;
      bytes += result.bytes;
    }
  } catch (error) {
  }
  return { directories: directories, files: files, bytes: bytes };
}

function normalizeDownloadLocation(location: string): string {
  return location === DOWNLOAD_LOCATION_DOWNLOADS ? DOWNLOAD_LOCATION_DOWNLOADS : DOWNLOAD_LOCATION_APP_FILES;
}

function createMetadata(gallery: GalleryInfo): GalleryMetadata {
  const detail = gallery as GalleryDetail;
  const tags = galleryDetailTags(gallery);
  const language = galleryDetailLanguage(gallery);
  return {
    version: 1,
    gid: gallery.gid,
    token: gallery.token,
    title: gallery.title,
    titleJpn: gallery.titleJpn === undefined ? '' : gallery.titleJpn,
    thumb: gallery.thumb === undefined ? '' : gallery.thumb,
    category: gallery.category,
    posted: gallery.posted === undefined ? '' : gallery.posted,
    uploader: gallery.uploader === undefined ? '' : gallery.uploader,
    rating: gallery.rating,
    pages: gallery.pages,
    previewPages: detail.previewPages === undefined ? 0 : detail.previewPages,
    savedAt: Date.now(),
    simpleLanguage: gallery.simpleLanguage,
    simpleTags: cloneStringArray(gallery.simpleTags),
    tagList: cloneStringArray(gallery.tagList),
    detailTags: cloneGalleryTagGroups(tags),
    detailLanguage: language,
    language: detail.language,
    previewSet: cloneGalleryPreviews(detail.previewSet)
  };
}

function createAndroidSpiderInfo(detail: GalleryDetail): string {
  const lines: string[] = [];
  lines.push('VERSION2');
  lines.push('00000000');
  lines.push(detail.gid.toString());
  lines.push(detail.token);
  lines.push('1');
  lines.push(Math.max(0, detail.previewPages).toString());
  lines.push(previewPerPage(detail).toString());
  lines.push(Math.max(0, detail.pages).toString());
  for (let i = 0; i < detail.previewSet.length; i++) {
    const parsed = parseGalleryPageUrl(detail.previewSet[i].pageUrl);
    if (parsed !== null && parsed.pageToken.length > 0) {
      lines.push(parsed.pageIndex.toString() + ' ' + parsed.pageToken);
    }
  }
  return lines.join('\n') + '\n';
}

function previewPerPage(detail: GalleryDetail): number {
  if (detail.previewSet.length <= 0) {
    return 0;
  }
  if (detail.previewPages <= 1) {
    return detail.previewSet.length;
  }
  return Math.max(1, Math.ceil(detail.previewSet.length / detail.previewPages));
}

function readRestoredGallery(directory: string, directoryName: string): RestoredGalleryData | null {
  const metadata = readMetadata(directory + '/' + OHOS_METADATA_FILENAME);
  if (metadata !== null) {
    writeTextFileQuietly(directory + '/' + ANDROID_SPIDER_INFO_FILENAME, createAndroidSpiderInfoFromMetadata(metadata));
    return {
      gallery: metadataToGallery(metadata),
      total: metadata.pages
    };
  }

  const oldJsonMetadata = readMetadata(directory + '/' + ANDROID_SPIDER_INFO_FILENAME);
  if (oldJsonMetadata !== null) {
    writeTextFileQuietly(directory + '/' + ANDROID_SPIDER_INFO_FILENAME, createAndroidSpiderInfoFromMetadata(oldJsonMetadata));
    writeTextFileQuietly(directory + '/' + OHOS_METADATA_FILENAME, JSON.stringify(oldJsonMetadata));
    return {
      gallery: metadataToGallery(oldJsonMetadata),
      total: oldJsonMetadata.pages
    };
  }

  const spiderInfo = readAndroidSpiderInfo(directory + '/' + ANDROID_SPIDER_INFO_FILENAME);
  if (spiderInfo === null) {
    return null;
  }
  return {
    gallery: spiderInfoToGallery(spiderInfo, directoryName),
    total: spiderInfo.pages
  };
}

function createAndroidSpiderInfoFromMetadata(metadata: GalleryMetadata): string {
  const lines: string[] = [];
  lines.push('VERSION2');
  lines.push('00000000');
  lines.push(metadata.gid.toString());
  lines.push(metadata.token);
  lines.push('1');
  lines.push(Math.max(0, metadata.previewPages).toString());
  lines.push('0');
  lines.push(Math.max(0, metadata.pages).toString());
  return lines.join('\n') + '\n';
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

function readAndroidSpiderInfo(path: string): AndroidSpiderInfo | null {
  try {
    const lines = fs.readTextSync(path).split(/\r?\n/);
    if (lines.length < 7) {
      return null;
    }
    let offset = 0;
    let version = 1;
    if (lines[0].startsWith('VERSION')) {
      version = parseInteger(lines[0].substring('VERSION'.length), -1);
      offset = 1;
    }
    if (version !== 1 && version !== 2) {
      return null;
    }
    if (lines.length <= offset + 6) {
      return null;
    }

    const gid = parseInteger(lines[offset + 1], -1);
    const token = lines[offset + 2];
    const previewPages = parseInteger(lines[offset + 4], 0);
    const previewPerPage = version === 2 ? parseInteger(lines[offset + 5], 0) : 0;
    const pages = parseInteger(lines[offset + 6], -1);
    if (gid <= 0 || token.length === 0 || pages <= 0) {
      return null;
    }
    return {
      gid: gid,
      token: token,
      pages: pages,
      previewPages: previewPages,
      previewPerPage: previewPerPage
    };
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
    simpleLanguage: metadata.simpleLanguage,
    simpleTags: cloneStringArray(metadata.simpleTags),
    pages: metadata.pages,
    thumbWidth: 0,
    thumbHeight: 0,
    favoriteSlot: -1,
    favoriteName: '',
    tagList: cloneStringArray(metadata.tagList),
    detailTags: cloneGalleryTagGroups(metadata.detailTags),
    detailLanguage: metadata.detailLanguage === undefined ? metadata.language : metadata.detailLanguage
  };
}

function galleryDetailTags(item: GalleryInfo): GalleryTagGroup[] | undefined {
  const detail = item as GalleryDetail;
  if (detail.tags !== undefined && Array.isArray(detail.tags) && detail.tags.length > 0) {
    return detail.tags;
  }
  return item.detailTags;
}

function galleryDetailLanguage(item: GalleryInfo): string | undefined {
  const detail = item as GalleryDetail;
  if (detail.language !== undefined && detail.language.length > 0) {
    return detail.language;
  }
  return item.detailLanguage;
}

function cloneStringArray(values: string[] | undefined): string[] | undefined {
  if (values === undefined || !Array.isArray(values)) {
    return undefined;
  }
  const cloned: string[] = [];
  for (let i = 0; i < values.length; i++) {
    cloned.push(values[i]);
  }
  return cloned;
}

function cloneGalleryTagGroups(groups: GalleryTagGroup[] | undefined): GalleryTagGroup[] | undefined {
  if (groups === undefined || !Array.isArray(groups)) {
    return undefined;
  }
  const cloned: GalleryTagGroup[] = [];
  for (let i = 0; i < groups.length; i++) {
    cloned.push({
      namespace: groups[i].namespace,
      tags: cloneStringArray(groups[i].tags) ?? []
    });
  }
  return cloned;
}

function cloneGalleryPreviews(previews: GalleryPreview[] | undefined): GalleryPreview[] | undefined {
  if (previews === undefined || !Array.isArray(previews)) {
    return undefined;
  }
  const cloned: GalleryPreview[] = [];
  for (let i = 0; i < previews.length; i++) {
    cloned.push({
      index: previews[i].index,
      pageUrl: previews[i].pageUrl,
      imageUrl: previews[i].imageUrl,
      width: previews[i].width,
      height: previews[i].height,
      xOffset: previews[i].xOffset,
      yOffset: previews[i].yOffset
    });
  }
  return cloned;
}

function spiderInfoToGallery(info: AndroidSpiderInfo, directoryName: string): GalleryInfo {
  return {
    gid: info.gid,
    token: info.token,
    title: titleFromDirectoryName(directoryName, info.gid),
    titleJpn: '',
    thumb: '',
    category: 0,
    posted: '',
    uploader: '',
    rating: 0,
    rated: false,
    pages: info.pages,
    thumbWidth: 0,
    thumbHeight: 0,
    favoriteSlot: -1,
    favoriteName: ''
  };
}

function titleFromDirectoryName(name: string, gid: number): string {
  const prefix = gid.toString() + '-';
  if (name.startsWith(prefix) && name.length > prefix.length) {
    return name.substring(prefix.length);
  }
  return name.length > 0 ? name : gid.toString();
}

function parseInteger(value: string, fallback: number): number {
  const parsed = Number.parseInt(value);
  return Number.isNaN(parsed) ? fallback : parsed;
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

function galleryArchiveUri(gallery: GalleryInfo): string {
  const downloadInfo = gallery as DownloadArchiveLocation;
  if (downloadInfo.archiveUri !== undefined && downloadInfo.archiveUri.length > 0) {
    return downloadInfo.archiveUri;
  }
  return '';
}

interface DownloadArchiveLocation extends GalleryInfo {
  archiveUri?: string;
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

function pathBaseName(path: string): string {
  const normalized = normalizePath(path);
  const index = normalized.lastIndexOf('/');
  if (index >= 0 && index < normalized.length - 1) {
    return normalized.substring(index + 1);
  }
  return normalized.length > 0 ? normalized : 'downloads';
}

function uniqueChildPath(parent: string, childName: string): string {
  const safeName = sanitizePathSegment(childName);
  let candidate = parent + '/' + safeName;
  let index = 2;
  while (exists(candidate)) {
    candidate = parent + '/' + safeName + '-' + index.toString();
    index++;
  }
  return candidate;
}

function uniqueZipPath(parent: string, fileName: string): string {
  const dot = fileName.toLowerCase().endsWith('.zip') ? fileName.length - 4 : fileName.length;
  const base = sanitizePathSegment(fileName.substring(0, dot));
  let candidate = parent + '/' + base + '.zip';
  let index = 2;
  while (exists(candidate)) {
    candidate = parent + '/' + base + '-' + index.toString() + '.zip';
    index++;
  }
  return candidate;
}

function parentPath(path: string): string {
  const slash = path.lastIndexOf('/');
  if (slash <= 0) {
    return '';
  }
  return path.substring(0, slash);
}

function removeFileQuietly(path: string): void {
  try {
    fs.unlinkSync(path);
  } catch (error) {
  }
}

function zipTimestamp(): string {
  const date = new Date();
  return date.getFullYear().toString() + padTwoDigits(date.getMonth() + 1) + padTwoDigits(date.getDate()) + '_' +
    padTwoDigits(date.getHours()) + padTwoDigits(date.getMinutes()) + padTwoDigits(date.getSeconds());
}

function padTwoDigits(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
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

function writeTextFileQuietly(path: string, value: string): void {
  try {
    writeTextFile(path, value);
  } catch (error) {
  }
}

function exists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (error) {
    return false;
  }
}

function isDirectory(path: string): boolean {
  try {
    return fs.statSync(path).isDirectory();
  } catch (error) {
    return false;
  }
}

function scanDirectoryTree(path: string): DownloadDirectoryScanResult {
  let directories = 0;
  let files = 0;
  let bytes = 0;
  try {
    const stat = fs.statSync(path);
    if (!stat.isDirectory()) {
      return { directories: 0, files: 1, bytes: stat.size };
    }
    directories++;
    const names = fs.listFileSync(path);
    for (let i = 0; i < names.length; i++) {
      const child = scanDirectoryTree(path + '/' + names[i]);
      directories += child.directories;
      files += child.files;
      bytes += child.bytes;
    }
  } catch (error) {
  }
  return { directories: directories, files: files, bytes: bytes };
}

function removeDirectoryTree(path: string): DownloadDirectoryScanResult {
  let directories = 0;
  let files = 0;
  let bytes = 0;
  try {
    const stat = fs.statSync(path);
    if (!stat.isDirectory()) {
      const size = stat.size;
      fs.unlinkSync(path);
      return { directories: 0, files: 1, bytes: size };
    }
    const names = fs.listFileSync(path);
    for (let i = 0; i < names.length; i++) {
      const removed = removeDirectoryTree(path + '/' + names[i]);
      directories += removed.directories;
      files += removed.files;
      bytes += removed.bytes;
    }
    fs.rmdirSync(path);
    directories++;
  } catch (error) {
  }
  return { directories: directories, files: files, bytes: bytes };
}

function copyDirectoryTree(source: string, target: string): DownloadDirectoryScanResult {
  let directories = 0;
  let files = 0;
  let bytes = 0;
  try {
    const stat = fs.statSync(source);
    if (!stat.isDirectory()) {
      if (exists(target)) {
        removeDirectoryTree(target);
      }
      fs.copyFileSync(source, target);
      return { directories: 0, files: 1, bytes: stat.size };
    }
    ensureDirectory(target);
    directories++;
    const names = fs.listFileSync(source);
    for (let i = 0; i < names.length; i++) {
      const copied = copyDirectoryTree(source + '/' + names[i], target + '/' + names[i]);
      directories += copied.directories;
      files += copied.files;
      bytes += copied.bytes;
    }
  } catch (error) {
  }
  return { directories: directories, files: files, bytes: bytes };
}

function normalizePath(path: string): string {
  let result = path.trim();
  while (result.endsWith('/') && result.length > 1) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

export const ehDownloadFileStore: EhDownloadFileStore = new EhDownloadFileStore();
