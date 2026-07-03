import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { GalleryCategory, GalleryInfo, GallerySite } from '../model/GalleryModels';
import { DownloadMetadataRestoreResult, rebuildImportedHistoryMetadata } from './DownloadMetadataRestore';
import { DownloadInfo, DownloadState, ehDownloadStore } from './EhDownloadStore';
import { ehFilterStore } from './EhFilterStore';
import { ehHistoryStore } from './EhHistoryStore';
import { HISTORY_INFO_SIZE_KEY, ehSettingsStore, historyInfoSizeLimitFromValue } from './EhSettingsStore';
import { ehSearchHistoryStore } from './EhSearchHistoryStore';

const SQLITE_HEADER: string = 'SQLite format 3';
const ANDROID_IMPORT_DB_NAME: string = 'ehviewer_android_import.db';

const ANDROID_DOWNLOAD_STATE_INVALID: number = -1;
const ANDROID_DOWNLOAD_STATE_WAIT: number = 1;
const ANDROID_DOWNLOAD_STATE_DOWNLOAD: number = 2;
const ANDROID_DOWNLOAD_STATE_FINISH: number = 3;
const ANDROID_DOWNLOAD_STATE_FAILED: number = 4;
const ANDROID_DOWNLOAD_STATE_UPDATE: number = 5;

export interface AndroidDataImportSummary {
  history: number;
  historyMetadata: number;
  historyMetadataFetched: number;
  downloads: number;
  labels: number;
  filters: number;
  searches: number;
}

interface AndroidHistoryImportResult {
  count: number;
  items: GalleryInfo[];
}

export function isAndroidDatabaseBackup(data: Uint8Array): boolean {
  if (data.length < SQLITE_HEADER.length) {
    return false;
  }
  for (let i = 0; i < SQLITE_HEADER.length; i++) {
    if (data[i] !== SQLITE_HEADER.charCodeAt(i)) {
      return false;
    }
  }
  return true;
}

export async function importAndroidDatabaseBackup(context: common.UIAbilityContext,
  data: Uint8Array): Promise<AndroidDataImportSummary> {
  const config: relationalStore.StoreConfig = {
    name: ANDROID_IMPORT_DB_NAME,
    securityLevel: relationalStore.SecurityLevel.S1
  };
  await deleteImportStoreQuietly(context, config);
  writeImportDatabase(context, data);

  let store: relationalStore.RdbStore | null = null;
  try {
    store = await relationalStore.getRdbStore(context, config);
    await ehHistoryStore.load(context);
    await ehDownloadStore.load(context);
    await ehFilterStore.load(context);
    await ehSettingsStore.load(context);
    await ehSearchHistoryStore.load(context);

    const historyResult = await importHistory(store);
    const labels = await importDownloadLabels(store);
    const downloads = await importDownloads(store);
    const historyMetadata = await rebuildImportedHistoryMetadata(context, historyResult.items, currentImportGallerySite());
    const summary: AndroidDataImportSummary = {
      history: historyResult.count,
      historyMetadata: historyMetadata.rebuilt,
      historyMetadataFetched: historyMetadata.fetched,
      labels: labels,
      downloads: downloads,
      filters: await importFilters(store),
      searches: await importQuickSearch(store)
    };

    await Promise.all([
      ehHistoryStore.save(context),
      ehDownloadStore.save(context),
      ehFilterStore.save(context)
    ]);
    return summary;
  } catch (error) {
    throw new Error(String(error));
  } finally {
    if (store !== null) {
      try {
        await store.close();
      } catch (error) {
      }
    }
    await deleteImportStoreQuietly(context, config);
  }
}

async function importHistory(store: relationalStore.RdbStore): Promise<AndroidHistoryImportResult> {
  if (!await tableExists(store, 'HISTORY')) {
    return { count: 0, items: [] };
  }
  let count = 0;
  const items: GalleryInfo[] = [];
  const historyLimit = historyInfoSizeLimitFromValue(ehSettingsStore.getValue(HISTORY_INFO_SIZE_KEY, '100'));
  await queryEach(store, 'SELECT * FROM "HISTORY" ORDER BY "TIME" ASC', (row: relationalStore.ResultSet) => {
    const gallery = readGalleryInfo(row);
    if (gallery.gid > 0 && gallery.token.length > 0) {
      ehHistoryStore.addGallery(gallery, historyLimit);
      items.push(gallery);
      count++;
    }
  });
  return { count: count, items: items };
}

async function importDownloadLabels(store: relationalStore.RdbStore): Promise<number> {
  if (!await tableExists(store, 'DOWNLOAD_LABELS')) {
    return 0;
  }
  let count = 0;
  await queryEach(store, 'SELECT * FROM "DOWNLOAD_LABELS" ORDER BY "TIME" ASC', (row: relationalStore.ResultSet) => {
    const label = getStringColumn(row, 'LABEL', '').trim();
    if (label.length > 0) {
      if (ehDownloadStore.addLabel(label)) {
        count++;
      }
    }
  });
  return count;
}

async function importDownloads(store: relationalStore.RdbStore): Promise<number> {
  if (!await tableExists(store, 'DOWNLOADS')) {
    return 0;
  }
  let count = 0;
  await queryEach(store, 'SELECT * FROM "DOWNLOADS" ORDER BY "TIME" ASC', (row: relationalStore.ResultSet) => {
    const gallery = readGalleryInfo(row);
    if (gallery.gid <= 0 || gallery.token.length === 0) {
      return;
    }
    const state = getNumberColumn(row, 'STATE', 0);
    const downloadState = mapAndroidDownloadState(state);
    const item: DownloadInfo = {
      gid: gallery.gid,
      token: gallery.token,
      title: gallery.title,
      titleJpn: gallery.titleJpn,
      thumb: gallery.thumb,
      category: gallery.category,
      posted: gallery.posted,
      uploader: gallery.uploader,
      rating: gallery.rating,
      rated: gallery.rated,
      simpleLanguage: gallery.simpleLanguage,
      simpleTags: gallery.simpleTags,
      pages: gallery.pages,
      thumbWidth: gallery.thumbWidth,
      thumbHeight: gallery.thumbHeight,
      favoriteSlot: gallery.favoriteSlot,
      favoriteName: gallery.favoriteName,
      tagList: gallery.tagList,
      detailTags: gallery.detailTags,
      detailLanguage: gallery.detailLanguage,
      state: downloadState,
      legacy: getNumberColumn(row, 'LEGACY', 0),
      time: getNumberColumn(row, 'TIME', Date.now()),
      label: getStringColumn(row, 'LABEL', ''),
      archiveUri: getStringColumn(row, 'ARCHIVE_URI', ''),
      speed: 0,
      remaining: 0,
      finished: downloadState === DownloadState.Finish ? gallery.pages : 0,
      downloaded: 0,
      total: gallery.pages,
      fileSize: -1
    };
    if (ehDownloadStore.importDownload(item)) {
      count++;
    }
  });
  return count;
}

async function importFilters(store: relationalStore.RdbStore): Promise<number> {
  if (!await tableExists(store, 'FILTER')) {
    return 0;
  }
  let count = 0;
  await queryEach(store, 'SELECT * FROM "FILTER" ORDER BY "_id" ASC', (row: relationalStore.ResultSet) => {
    const mode = getNumberColumn(row, 'MODE', 0);
    const text = getStringColumn(row, 'TEXT', '').trim();
    const enabled = getNumberColumn(row, 'ENABLE', 1) !== 0;
    if (text.length > 0 && ehFilterStore.addRule(mode, text, enabled)) {
      count++;
    }
  });
  return count;
}

async function importQuickSearch(store: relationalStore.RdbStore): Promise<number> {
  if (!await tableExists(store, 'QUICK_SEARCH')) {
    return 0;
  }
  let count = 0;
  await queryEach(store, 'SELECT * FROM "QUICK_SEARCH" ORDER BY "TIME" ASC', (row: relationalStore.ResultSet) => {
    const keyword = getStringColumn(row, 'KEYWORD', '').trim();
    if (keyword.length > 0) {
      ehSearchHistoryStore.record(keyword);
      count++;
    }
  });
  return count;
}

function currentImportGallerySite(): GallerySite {
  return ehSettingsStore.getValue('gallery_site', 'E-Hentai') === 'ExHentai' ? GallerySite.Ex : GallerySite.E;
}

async function tableExists(store: relationalStore.RdbStore, table: string): Promise<boolean> {
  let resultSet: relationalStore.ResultSet | null = null;
  try {
    resultSet = await store.querySql('SELECT name FROM sqlite_master WHERE type = ? AND name = ?', ['table', table]);
    return resultSet.goToFirstRow();
  } catch (error) {
    return false;
  } finally {
    closeResultSetQuietly(resultSet);
  }
}

async function queryEach(store: relationalStore.RdbStore, sql: string,
  visitor: (row: relationalStore.ResultSet) => void): Promise<void> {
  let resultSet: relationalStore.ResultSet | null = null;
  try {
    resultSet = await store.querySql(sql);
    while (resultSet.goToNextRow()) {
      visitor(resultSet);
    }
  } catch (error) {
    throw new Error(String(error));
  } finally {
    closeResultSetQuietly(resultSet);
  }
}

function readGalleryInfo(row: relationalStore.ResultSet): GalleryInfo {
  return {
    gid: getNumberColumn(row, 'GID', 0),
    token: getStringColumn(row, 'TOKEN', ''),
    title: getStringColumn(row, 'TITLE', ''),
    titleJpn: getOptionalStringColumn(row, 'TITLE_JPN'),
    thumb: getOptionalStringColumn(row, 'THUMB'),
    category: getNumberColumn(row, 'CATEGORY', GalleryCategory.Unknown),
    posted: getOptionalStringColumn(row, 'POSTED'),
    uploader: getOptionalStringColumn(row, 'UPLOADER'),
    rating: getNumberColumn(row, 'RATING', -1),
    rated: false,
    simpleLanguage: getOptionalStringColumn(row, 'SIMPLE_LANGUAGE'),
    pages: 0,
    thumbWidth: 0,
    thumbHeight: 0,
    favoriteSlot: -2
  };
}

function mapAndroidDownloadState(state: number): DownloadState {
  if (state === ANDROID_DOWNLOAD_STATE_INVALID) {
    return DownloadState.Invalid;
  }
  if (state === ANDROID_DOWNLOAD_STATE_WAIT) {
    return DownloadState.Wait;
  }
  if (state === ANDROID_DOWNLOAD_STATE_DOWNLOAD) {
    return DownloadState.Downloading;
  }
  if (state === ANDROID_DOWNLOAD_STATE_FINISH) {
    return DownloadState.Finish;
  }
  if (state === ANDROID_DOWNLOAD_STATE_FAILED) {
    return DownloadState.Failed;
  }
  if (state === ANDROID_DOWNLOAD_STATE_UPDATE) {
    return DownloadState.Update;
  }
  return DownloadState.None;
}

function getOptionalStringColumn(row: relationalStore.ResultSet, name: string): string | undefined {
  const value = getStringColumn(row, name, '');
  return value.length > 0 ? value : undefined;
}

function getStringColumn(row: relationalStore.ResultSet, name: string, fallback: string): string {
  try {
    const index = row.getColumnIndex(name);
    if (index < 0 || row.isColumnNull(index)) {
      return fallback;
    }
    return row.getString(index);
  } catch (error) {
    return fallback;
  }
}

function getNumberColumn(row: relationalStore.ResultSet, name: string, fallback: number): number {
  try {
    const index = row.getColumnIndex(name);
    if (index < 0 || row.isColumnNull(index)) {
      return fallback;
    }
    return row.getDouble(index);
  } catch (error) {
    return fallback;
  }
}

function writeImportDatabase(context: common.UIAbilityContext, data: Uint8Array): void {
  const dbDir = context.databaseDir + '/rdb';
  ensureDirectory(dbDir);
  const dbPath = dbDir + '/' + ANDROID_IMPORT_DB_NAME;
  let fd = -1;
  try {
    const file = fs.openSync(dbPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    fd = file.fd;
    fs.writeSync(fd, data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));
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

async function deleteImportStoreQuietly(context: common.UIAbilityContext,
  config: relationalStore.StoreConfig): Promise<void> {
  try {
    await relationalStore.deleteRdbStore(context, config);
  } catch (error) {
  }
}

function ensureDirectory(path: string): void {
  try {
    if (!fs.accessSync(path)) {
      fs.mkdirSync(path, true);
    }
  } catch (error) {
    try {
      fs.mkdirSync(path, true);
    } catch (innerError) {
    }
  }
}

function closeResultSetQuietly(resultSet: relationalStore.ResultSet | null): void {
  if (resultSet === null) {
    return;
  }
  try {
    resultSet.close();
  } catch (error) {
  }
}
