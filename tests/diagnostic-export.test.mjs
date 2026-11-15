import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = name => readFileSync(new URL('../entry/src/main/ets/services/' + name, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
function erase(source) {
  return source.replace(/^import [\s\S]*?;\n/gm, '')
    .replace(/^(?:export )?interface \w+ \{[\s\S]*?^}\n/gm, '')
    .replace(/\bexport |\bprivate |@Concurrent\n/g, '')
    .replace(/(\w)\?:/g, '$1:')
    .replace(/: (?:Promise<[^>]+>|Record<[^>]+>|common\.UIAbilityContext|AbilityConstant\.LaunchParam|hiAppEvent\.AppEventInfo|hiAppEvent\.AppEventGroup|DiagnosticLogFile|EhFaultLogStore|EhAppLog|SavedFault|string|number|boolean|void|Error)(?:\[\])?(?: \| undefined)?/g, '')
    .replace(/: \(\) => Promise<string>/g, '')
    .replace(/ as (?:BusinessError|SavedFault|FaultParams|string)/g, '');
}
const { redactDiagnosticText, formatAppDiagnosticLog, isAbnormalExit } = Function(erase(read('DiagnosticLogSupport.ets')) +
  '; return { redactDiagnosticText, formatAppDiagnosticLog, isAbnormalExit };')();

function memoryFiles() {
  const files = new Map();
  const handles = new Map();
  let next = 1;
  const failures = new Set();
  const missing = () => Object.assign(new Error('missing'), { code: 13900002 });
  const fs = {
    OpenMode: { CREATE: 1, READ_WRITE: 2, APPEND: 4, TRUNC: 8 },
    async stat(path) { if (!files.has(path)) throw missing(); return { size: files.get(path).length }; },
    async readText(path, options) {
      if (!files.has(path)) throw missing();
      const bytes = files.get(path);
      return bytes.subarray(options?.offset ?? 0, (options?.offset ?? 0) + (options?.length ?? bytes.length)).toString('utf8');
    },
    async open(path, mode) {
      if (!files.has(path) || mode & 8) files.set(path, Buffer.alloc(0));
      const fd = next++;
      handles.set(fd, path);
      return { fd };
    },
    async write(fd, data) {
      const path = handles.get(fd);
      if (failures.delete('write')) throw new Error('disk write failed');
      // Force partial native writes, including cuts inside UTF-8 sequences.
      const bytes = Buffer.from(data).subarray(0, 7);
      files.set(path, Buffer.concat([files.get(path), bytes]));
      return bytes.length;
    },
    async close(file) { handles.delete(typeof file === 'number' ? file : file.fd); },
    async rename(from, to) {
      if (failures.delete('rename')) throw new Error('commit failed');
      files.set(to, files.get(from)); files.delete(from);
    },
    async unlink(path) {
      if (failures.delete('unlink')) throw new Error('delete failed');
      if (!files.delete(path)) throw missing();
    },
    async listFile(directory) { return [...files.keys()].filter(p => p.startsWith(directory + '/')).map(p => p.slice(directory.length + 1)); }
  };
  const util = { TextEncoder: class { encodeInto(text) { return new Uint8Array(Buffer.from(text)); } } };
  const api = Function('fs', 'util', erase(read('DiagnosticLogFile.ets')) +
    ';return { DiagnosticLogFile, readDiagnosticFile, writeDiagnosticFile };')(fs, util);
  return { files, handles, failures, fs, ...api };
}

test('exports redact credentials and signed URLs while retaining native crash evidence', () => {
  const input = 'Cookie: ipb_member_id=123; ipb_pass_hash=private\nAuthorization: Bearer bearer-secret\n' +
    '{"api_key":"api-secret", "token":"json-secret"}\n' +
    'https://username:password@host.test/path?key=query-secret&token=another-secret\n' +
    'https://image.test/h/abcdef/keystamp=timestamp-secret;fileindex=123/\n' +
    'SIGSEGV address 0x94 thread OS_NET_RcpWork BuildId abcdef libcurl.so+0x2511a8';
  const output = redactDiagnosticText(input);
  for (const secret of ['ipb_member_id=123', 'private', 'bearer-secret', 'api-secret', 'json-secret',
    'username:password', 'query-secret', 'another-secret', 'timestamp-secret']) assert.ok(!output.includes(secret), secret);
  assert.match(output, /https:\/\/\[PRIVATE_HOST\]\/\[PRIVATE_PATH\]/);
  assert.match(output, /SIGSEGV address 0x94 thread OS_NET_RcpWork BuildId abcdef libcurl\.so\+0x2511a8/);
  assert.equal(redactDiagnosticText(output), output);
});

test('custom servers, gallery paths and remote profile names are hidden without removing public service evidence', () => {
  const input = '2026-11-15T14:36:50.901Z [INFO] RemoteStorage: response PUT ' +
    'https://private.example.test:5006/account-secret/download/123-%E7%A7%81%E5%AF%86/00000001.webp -> 204 in 90ms\n' +
    '2026-11-15T14:36:50.902Z [INFO] RemoteStorage: download mirror start profile=personal server\n' +
    '2026-11-15T14:36:50.903Z [INFO] RemoteStorage: put text path=download/private title/manifest.json bytes=90\n' +
    '2026-11-15T14:36:50.904Z [INFO] RemoteStorage: download manifest shard pulled dir=private title items=3\n' +
    'https://api.e-hentai.org/api.php https://sni.hath.network/file?key=secret\n' +
    'https://e-hentai.org.private.example.test/secret https://[2001:db8::1]:5006/secret\n' +
    'SIGSEGV 0x94 libcurl.so+0x2511a8 BuildId 123';
  const output = redactDiagnosticText(input);
  for (const secret of ['private.example.test', 'account-secret', '%E7', 'personal server', 'private title', '2001:db8', 'key=secret']) {
    assert.ok(!output.includes(secret), secret);
  }
  for (const evidence of ['[PRIVATE_HOST]:5006/[PRIVATE_PATH].webp', '-> 204 in 90ms', 'bytes=90', 'items=3',
    'api.e-hentai.org/api.php', 'sni.hath.network', 'SIGSEGV 0x94 libcurl.so+0x2511a8 BuildId 123']) {
    assert.ok(output.includes(evidence), evidence);
  }
  assert.equal(redactDiagnosticText(output), output);
});

test('legacy log fragments and remote storage overflow are marked while other modules remain intact', () => {
  const app = 'fragment-of-an-old-url\n' +
    '2026-11-15T14:36:50.901Z [ERROR] Reader: important failure\n  stack line\n' +
    '2026-11-15T14:36:50.902Z [INFO] RemoteStorage: legacy remote record\n' +
    '2026-11-15T14:36:50.903Z [INFO] EntryAbility: startup\n';
  const remote = Array.from({ length: 1500 }, (_, i) =>
    `2026-11-15T14:36:51.000Z [INFO] RemoteStorage: response ${i}\n`).join('');
  const result = formatAppDiagnosticLog(app, remote);
  assert.ok(!result.includes('fragment-of-an-old-url'));
  for (const fragment of ['incomplete legacy record removed', 'Reader: important failure\n  stack line',
    'EntryAbility: startup', '[Earlier remote storage records omitted]', 'response 1499']) {
    assert.ok(result.includes(fragment), fragment);
  }
  assert.ok(result.length < 34000);
  assert.ok(!result.split('[Remote storage log, independent capacity]')[0].includes('RemoteStorage:'));
});

test('remote traffic has an independent disk budget, and clear removes both runtime files', async () => {
  const env = memoryFiles();
  const settings = { getValue: () => 'On' };
  const AppLog = Function('DiagnosticLogFile', 'ehSettingsStore', 'taskpool', 'formatAppDiagnosticLogTask',
    erase(read('EhAppLog.ets')) + ';return EhAppLog;')(
    env.DiagnosticLogFile, settings, { execute: async (_fn, app, remote) => formatAppDiagnosticLog(app, remote) }, () => {});
  const log = new AppLog();
  const context = { filesDir: '/app' };
  log.error(context, 'Reader', 'failure before remote activity');
  for (let i = 0; i < 3000; i++) log.info(context, 'RemoteStorage', 'response ' + i);
  const exported = await log.read(context);
  assert.match(exported, /failure before remote activity/);
  assert.match(exported, /response 2999/);
  assert.ok(!env.files.get('/app/ehviewer_app.log').toString().includes('RemoteStorage'));
  assert.ok(env.files.get('/app/ehviewer_remote_storage.log').length <= 128 * 1024);
  const readText = env.fs.readText;
  env.fs.readText = async (path, options) => {
    if (path.endsWith('ehviewer_remote_storage.log')) throw new Error('remote log unreadable');
    return readText(path, options);
  };
  const partial = await log.read(context);
  assert.match(partial, /failure before remote activity/);
  assert.match(partial, /Log read failed.*remote log unreadable/);
  await log.clear(context);
  assert.ok(!env.files.has('/app/ehviewer_app.log'));
  assert.ok(!env.files.has('/app/ehviewer_remote_storage.log'));
});

test('byte-limited tails discard incomplete UTF-8 lines and explicitly report truncation', async () => {
  const env = memoryFiles();
  env.files.set('/tail', Buffer.from('header\n中文中文中文\ncomplete record\n'));
  const result = await env.readDiagnosticFile('/tail', 25, true);
  assert.equal(result, '[Earlier content omitted]\ncomplete record\n');
  assert.ok(!result.includes('�'));
});

test('async writes preserve Unicode, partial writes and serialized export/clear boundaries', async () => {
  const env = memoryFiles();
  const text = 'x'.repeat(32767) + '😀中文';
  await env.writeDiagnosticFile('/unicode', text);
  assert.equal(env.files.get('/unicode').toString(), text);
  assert.equal(env.handles.size, 0);
  const log = new env.DiagnosticLogFile('app.log', 1024);
  log.append('/app', 'before');
  const before = log.read('/app');
  const clear = log.clear('/app');
  log.append('/app', 'after');
  assert.equal(await before, 'before');
  await clear;
  assert.equal(await log.read('/app'), 'after');
});

test('rotation stays bounded and write/clear failures do not poison subsequent operations', async () => {
  const env = memoryFiles();
  const log = new env.DiagnosticLogFile('app.log', 256);
  for (let i = 0; i < 10; i++) log.append('/app', String(i).repeat(40));
  const content = await log.read('/app');
  assert.ok(env.files.get('/app/app.log').length <= 256);
  assert.ok(content.endsWith('9'.repeat(40)));
  env.failures.add('write');
  log.append('/app', 'failed');
  assert.match(await log.read('/app'), /Log write failed/);
  log.append('/app', 'recovered');
  assert.ok((await log.read('/app')).endsWith('recovered'));
  env.failures.add('unlink');
  await assert.rejects(log.clear('/app'), /delete failed/);
  await log.clear('/app');
  assert.equal(await log.read('/app'), '');
});

test('a failed snapshot replacement preserves the last committed report and permits retry', async () => {
  const env = memoryFiles();
  const log = new env.DiagnosticLogFile('network.log', 1024);
  await log.replace('/app', 'previous complete diagnostics');
  env.failures.add('rename');
  await assert.rejects(log.replace('/app', 'new diagnostics'), /commit failed/);
  assert.equal(env.files.get('/app/network.log').toString(), 'previous complete diagnostics');
  await log.replace('/app', 'new diagnostics');
  assert.equal(await log.read('/app'), 'new diagnostics');
});

function faultStore(env) {
  let watcher;
  const hiAppEvent = { domain: { OS: 'OS' }, event: { APP_CRASH: 'APP_CRASH', APP_FREEZE: 'APP_FREEZE' },
    addWatcher(value) { watcher = value; return {}; } };
  const FaultStore = Function('hiAppEvent', 'errorManager', 'ehSettingsStore', 'ehAppLog', 'fs', 'taskpool',
    'readDiagnosticFile', 'writeDiagnosticFile', 'isAbnormalExit', 'redactDiagnosticExportTask',
    erase(read('EhFaultLogStore.ets')) + ';return EhFaultLogStore;')(
      hiAppEvent, { on() {} }, { ensureLoaded: async () => {} }, { error() {} }, env.fs,
      { execute: async (_fn, text) => redactDiagnosticText(text) }, env.readDiagnosticFile, env.writeDiagnosticFile,
      isAbnormalExit, () => {});
  const store = new FaultStore();
  store.initialize({ filesDir: '/app' }, { lastExitReason: 3, lastExitMessage: 'native crash' });
  return { store, emit(time, path, extra = {}) {
    watcher.onReceive('OS', [{ appEventInfos: [{ name: 'APP_CRASH', params: {
      time, bundle_name: 'yt.ehviewer.huawei', external_log: [path], ...extra } }] }]);
  } };
}

test('latest fault survives restart, rejects older callbacks and is copied before attachment cleanup', async () => {
  const env = memoryFiles();
  const path = '/data/storage/el2/log/hiappevent/APP_CRASH_200_123.log';
  env.files.set(path, Buffer.from('OS_NET_HttpWork SIGSEGV 0x8\nCookie: secret\nBuildId 123'));
  const { store, emit } = faultStore(env);
  await store.read();
  emit(200, path, { exception: { signal: { address: '0x8' } }, memory: { rss: 1000 } });
  const report = await store.read();
  assert.match(report, /OS_NET_HttpWork SIGSEGV 0x8/);
  assert.match(report, /rss/);
  assert.ok(!report.includes('Cookie: secret'));
  assert.ok(!env.files.has(path));
  emit(100, '/data/storage/el2/log/hiappevent/APP_CRASH_100_123.log');
  assert.match(await store.read(), /OS_NET_HttpWork SIGSEGV 0x8/);
  const { store: restarted, emit: emitRestarted } = faultStore(env);
  assert.match(await restarted.read(), /OS_NET_HttpWork SIGSEGV 0x8/);
  await restarted.clear();
  emitRestarted(200, path);
  assert.match(await restarted.read(), /No captured fault attachment/);
});

test('a failed fault commit keeps its original system attachment for recovery', async () => {
  const env = memoryFiles();
  const { store, emit } = faultStore(env);
  await store.read();
  const path = '/data/storage/el2/log/hiappevent/APP_CRASH_300_123.log';
  env.files.set(path, Buffer.from('NativeCrash stack survives'));
  env.failures.add('rename');
  emit(300, path);
  await store.pending;
  assert.ok(env.files.has(path));
  const recovered = faultStore(env).store;
  assert.match(await recovered.read(), /NativeCrash stack survives/);
});

test('export recovers attachments generated after startup and explains empty or cleared fault reports', async () => {
  const env = memoryFiles();
  const { store } = faultStore(env);
  const empty = await store.read();
  assert.match(empty, /System fault subscription active since/);
  assert.match(empty, /abnormal previous exit/);
  assert.match(empty, /about two minutes/);
  const path = '/data/storage/el2/log/hiappevent/APP_CRASH_500_123.log';
  env.files.set(path, Buffer.from('late SIGSEGV stack'));
  const recovered = await store.read();
  assert.match(recovered, /late SIGSEGV stack/);
  assert.ok(!env.files.has(path));
  await store.clear();
  assert.match(await store.read(), /Saved faults cleared at/);
});

test('missing attachments retain metadata and report the absence explicitly', async () => {
  const env = memoryFiles();
  const { store, emit } = faultStore(env);
  await store.read();
  emit(400, '/data/storage/el2/log/hiappevent/APP_CRASH_400_123.log', { log_over_limit: true });
  const report = await store.read();
  assert.match(report, /log_over_limit/);
  assert.match(report, /Fault attachment unavailable/);
  for (const reason of [1, 3, 4, 5, 6, 7]) assert.equal(isAbnormalExit(reason), true);
  for (const reason of [0, 2, 8, 9]) assert.equal(isAbnormalExit(reason), false);
});

test('unified reports include faults and body contents, isolate read failures and scope optional records', async () => {
  const env = memoryFiles();
  const source = erase(read('EhDiagnosticExport.ets'))
    .replace(/: EhDiagnosticExport/g, '');
  const settings = { getValue: (key, fallback) => key === 'proxy' ? 'System' : fallback };
  const records = { read: async () => 'AI request/response', clear: async () => {} };
  const Export = Function('deviceInfo', 'taskpool', 'ehAppLog', 'ehFaultLogStore', 'ehParseErrorBodyStore',
    'aiTranslationConversationLog', 'readerOcrDebugLog', 'DiagnosticLogFile', 'readDiagnosticFile',
    'redactDiagnosticExportTask', 'ehSettingsStore', 'EH_APP_VERSION_CODE', 'EH_APP_VERSION_NAME', 'EH_TARGET_PLATFORM',
    source + ';return EhDiagnosticExport;')(
      { productModel: 'test tablet', deviceType: 'tablet', osFullName: 'test OS', displayVersion: 'test build', sdkApiVersion: 20 },
      { execute: async (_fn, content) => redactDiagnosticText(content) },
      { read: async () => { throw Error('unreadable app log'); }, clear: async () => {} },
      { read: async () => 'NativeCrash stack sample', clear: async () => {} },
      { list: async () => [{ name: 'failed.html', path: '/body', size: 50 }], clear: async () => {} },
      records, { read: async () => 'OCR layout data', clear: async () => {} },
      env.DiagnosticLogFile, async () => '<html>failed response body</html>', () => {}, settings, 705, '0.7.5', 'API 20–26');
  const exporter = new Export();
  const all = await exporter.create({ filesDir: '/app' });
  for (const fragment of ['test tablet', 'API 20', 'NativeCrash stack sample', 'Section unavailable',
    'failed response body', 'AI request/response', 'OCR layout data']) assert.ok(all.includes(fragment), fragment);
  const ai = await exporter.create({ filesDir: '/app' }, 'ai');
  assert.match(ai, /AI request\/response/);
  assert.ok(!ai.includes('OCR layout data'));
  const ocr = await exporter.create({ filesDir: '/app' }, 'ocr');
  assert.match(ocr, /OCR layout data/);
  assert.ok(!ocr.includes('AI request/response'));
  await exporter.rememberNetwork({ filesDir: '/app' }, 'network probe result');
  assert.match(await exporter.create({ filesDir: '/app' }, 'network'), /network probe result/);
});
