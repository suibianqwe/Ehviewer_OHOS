// 使用 DevEco 自带 TypeScript 转译器运行：node tests/gallery-status.cjs <typescript 模块路径>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const modules = new Map();
const storage = new Map();
const AppStorage = { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) };
let savedLocalFavorites = [];

function load(file) {
  file = path.resolve(file);
  if (modules.has(file)) return modules.get(file).exports;
  const module = { exports: {} };
  modules.set(file, module);
  const source = fs.readFileSync(file, 'utf8');
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const requireEts = name => {
    if (name === '@kit.AbilityKit') return {};
    if (name === '@kit.ArkData') return { preferences: { getPreferences: async (_context, options) => ({
      get: async (_key, fallback) => options.name === 'ehviewer_local_favorites' ?
        JSON.stringify(savedLocalFavorites) : fallback,
      put: async () => {}, flush: async () => {}
    }) } };
    if (name.startsWith('.')) return load(path.resolve(path.dirname(file), name + '.ets'));
    throw new Error('未模拟的依赖：' + name);
  };
  vm.runInNewContext(compiled, { module, exports: module.exports, require: requireEts, AppStorage,
    setTimeout, clearTimeout, console }, { filename: file });
  return module.exports;
}

function gallery(gid, favoriteSlot = -2) {
  return { gid, favoriteSlot, token: 'token', title: '测试画廊', thumb: '', category: 0, rating: 0,
    rated: false, pages: 10, thumbWidth: 100, thumbHeight: 150 };
}

async function main() {
  const { GalleryStatusStore, galleryStatusStore: status, GALLERY_STATUS_REVISION_KEY: key } =
    load(path.join(root, 'services/GalleryStatusStore.ets'));
  const { EhDownloadStore, DownloadState } = load(path.join(root, 'services/EhDownloadStore.ets'));
  const { EhLocalFavoritesStore } = load(path.join(root, 'services/EhLocalFavoritesStore.ets'));
  const downloads = new EhDownloadStore();
  const local = new EhLocalFavoritesStore();
  assert.equal(status.hasDownload(1), false);
  downloads.addGallery(gallery(1));
  assert.equal(status.hasDownload(1), true, '加入任务即显示箭头');
  const membershipRevision = storage.get(key);
  for (const state of Object.values(DownloadState)) {
    downloads.setState(1, state);
    assert.equal(status.hasDownload(1), true, '暂停、失败等任务仍显示箭头');
  }
  downloads.setProgress(1, 2, 10, 2);
  await new Promise(resolve => setTimeout(resolve, 400));
  assert.equal(storage.get(key), membershipRevision, '状态和进度不触发标记刷新');
  downloads.removeGallery(1);
  assert.equal(status.hasDownload(1), false);

  savedLocalFavorites = [gallery(2, -1)];
  await local.ensureLoaded({});
  assert.equal(status.isFavorite(gallery(2)), true, '首次加载本地收藏即可显示');
  local.removeGallery(2);
  assert.equal(status.isFavorite(gallery(2, -1)), false, '删除后忽略缓存的本地收藏槽位');
  local.addGallery(gallery(3));
  status.setCloudFavorite(3, false);
  assert.equal(status.isFavorite(gallery(3)), true, '取消云收藏不覆盖本地收藏');
  local.removeGallery(3);
  assert.equal(status.isFavorite(gallery(3)), false);
  status.setCloudFavorite(3, true);
  assert.equal(status.isFavorite(gallery(3)), true, '云收藏操作覆盖旧卡片');
  status.setCloudFavorite(3, false);
  assert.equal(status.isFavorite(gallery(3, 0)), false, '取消云收藏覆盖缓存中的旧槽位');
  status.syncCloudFavorites([gallery(3, 1)]);
  assert.equal(status.isFavorite(gallery(3)), true, '刷新列表同步服务端状态');
  local.importGallery(gallery(4), 1);
  await local.save({});
  assert.equal(status.isFavorite(gallery(4)), true, '导入收藏保存后更新');

  const fresh = new GalleryStatusStore();
  assert.equal(fresh.isFavorite(gallery(5, 0)), true);
  assert.equal(fresh.isFavorite(gallery(5, 9)), true);
  assert.equal(fresh.isFavorite(gallery(5, -2)), false);
  assert.equal(fresh.isFavorite(gallery(5, -1)), false);
  fresh.syncDownloads([1, 2]);
  const revision = storage.get(key);
  fresh.syncDownloads([2, 1, 1]);
  assert.equal(storage.get(key), revision, '重排或重复项不刷新');
  fresh.syncDownloads([1, 3]);
  assert.equal(fresh.hasDownload(2), false, '相同数量替换仍更新');
  fresh.setCloudAccount('account-a');
  fresh.setCloudFavorite(5, true);
  fresh.setCloudAccount('account-b');
  assert.equal(fresh.isFavorite(gallery(5)), false, '切换账号清理云收藏缓存');
  assert.equal(fresh.hasDownload(1), true, '账号切换保留本地下载');
  console.log('Issue #16：下载、收藏、持久化加载及状态更新回归检查通过');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
