// 使用 DevEco 自带 TypeScript 转译器：node tests/thumbnail-prefetch.cjs <typescript 模块路径>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const file = path.resolve(__dirname, '../entry/src/main/ets/shared/EhShared.ets');
const source = ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
const method = source.statements.find(node => ts.isFunctionDeclaration(node) &&
  node.name?.text === 'cacheThumbnailImage');
assert.ok(method, '必须使用实际的缩略图缓存入口');
const compiled = ts.transpileModule(method.getText(source), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const pendingUiUpdates = [];
const downloads = [];
const moduleUnderTest = { exports: {} };
let context = {};
vm.runInNewContext(compiled, {
  exports: moduleUnderTest.exports,
  getAbilityContext: () => context,
  currentGallerySite: () => 'test',
  EhUrl: { getReferer: () => 'test' },
  IMAGE_DOWNLOAD_PRIORITY_BACKGROUND: 2,
  THUMBNAIL_RETRY_LIMIT: 1,
  enqueueThumbnailReady: (localPath, onReady) => pendingUiUpdates.push(() => onReady(localPath)),
  readerImageCache: {
    getCachedPath: (_context, url) => url.startsWith('cached:') ? '/cache/thumb' : '',
    ensureCached: async (_context, url) => {
      downloads.push(url);
      if (url === 'failed') throw new Error('模拟下载失败');
      return '/cache/downloaded-thumb';
    }
  }
});
const { cacheThumbnailImage } = moduleUnderTest.exports;
const flushDownloads = () => new Promise(resolve => setImmediate(resolve));

async function main() {
  for (let index = 0; index < 100; index++) cacheThumbnailImage('cached:' + index);
  cacheThumbnailImage('uncached:prefetch');
  await flushDownloads();
  assert.equal(downloads.length, 1, '预下载仍须填充磁盘缓存');
  assert.equal(pendingUiUpdates.length, 0, '连续滚动预下载不得用空回调阻塞卡片更新');

  const ready = [];
  cacheThumbnailImage('cached:visible', localPath => ready.push(localPath));
  cacheThumbnailImage('uncached:visible', localPath => ready.push(localPath));
  await flushDownloads();
  assert.equal(pendingUiUpdates.length, 2, '实际卡片仍经原有队列分批更新');
  while (pendingUiUpdates.length > 0) pendingUiUpdates.shift()();
  assert.deepEqual(ready, ['/cache/thumb', '/cache/downloaded-thumb']);

  let errors = 0;
  cacheThumbnailImage('failed');
  cacheThumbnailImage('failed', undefined, () => errors++);
  await flushDownloads();
  assert.equal(errors, 1, '失败预下载不产生未处理拒绝，显式错误回调仍执行');
  context = undefined;
  cacheThumbnailImage('uncached:no-context');
  assert.equal(pendingUiUpdates.length, 0);
  console.log('缩略图回归通过：预下载不阻塞卡片更新，缓存命中、下载完成与错误回调正常');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
