import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { EhDownloadFileStore, DownloadMigrationProgress } from '../../../main/ets/services/EhDownloadFileStore';

// Exercise the production migration code, but never resolve either real download root.
class IsolatedDownloadStore extends EhDownloadFileStore {
  private appRoot: string;
  private publicRoot: string;

  constructor(appRoot: string, publicRoot: string) {
    super();
    this.appRoot = appRoot;
    this.publicRoot = publicRoot;
  }

  rootForLocation(_context: common.UIAbilityContext, location: string): string {
    return location === 'Downloads' ? this.publicRoot : this.appRoot;
  }
}

function check(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(message);
  }
}

function writeFixture(path: string, contents: string): void {
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
  try {
    fs.writeSync(file.fd, contents);
  } finally {
    fs.closeSync(file.fd);
  }
}

export async function runMigrationRegression(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const context = delegator.getAppContext() as common.UIAbilityContext;
    const parameters = abilityDelegatorRegistry.getArguments().parameters;
    const publicParent = parameters['-s publicRoot'] ?? parameters['publicRoot'];
    check(typeof publicParent === 'string' && publicParent.startsWith('/storage/Users/') &&
      publicParent.includes('/Download/') && !publicParent.includes('..'), 'Pass an authorized app download directory');
    const name = 'ehviewer-issue31-test-' + Date.now().toString();
    const appRoot = context.filesDir + '/' + name;
    const publicRoot = publicParent + '/' + name;
    check(!fs.accessSync(appRoot) && !fs.accessSync(publicRoot), 'Fixture roots must be new');
    fs.mkdirSync(appRoot);
    fs.mkdirSync(publicRoot);
    const store = new IsolatedDownloadStore(appRoot, publicRoot);
    try {
      fs.mkdirSync(publicRoot + '/gallery');
      writeFixture(publicRoot + '/gallery/001.txt', 'verified migration page one');
      writeFixture(publicRoot + '/gallery/metadata.json', '{"fixture":true}');
      const toApp = await store.migrateDownloadLocation(context, 'Downloads', 'App files');
      check(toApp.files === 2 && !toApp.cleanupIncomplete, 'Public to app result');
      check(fs.accessSync(publicRoot) && fs.listFileSync(publicRoot).length === 0, 'Public source root survives');
      check(fs.readTextSync(appRoot + '/gallery/001.txt') === 'verified migration page one', 'Copied bytes match');
      await delegator.print('PASS: public -> app, files verified, authorized source root retained\n');

      const toPublic = await store.migrateDownloadLocation(context, 'App files', 'Downloads');
      check(toPublic.files === 2 && !toPublic.cleanupIncomplete, 'App to public result');
      check(fs.accessSync(appRoot) && fs.listFileSync(appRoot).length === 0, 'App source root survives');
      check(fs.readTextSync(publicRoot + '/gallery/metadata.json') === '{"fixture":true}', 'Metadata survives round trip');
      await delegator.print('PASS: app -> public, metadata verified, source root retained\n');

      const warning = await store.migrateDownloadLocation(context, 'Downloads', 'App files',
        (progress: DownloadMigrationProgress) => {
          if (progress.phase === 'cleaning') {
            writeFixture(publicRoot + '/late.txt', 'created after copy snapshot');
          }
        });
      check(warning.files === 2 && warning.cleanupIncomplete, 'New source file reports cleanup warning');
      check(fs.readTextSync(publicRoot + '/late.txt') === 'created after copy snapshot', 'New file must not be deleted');
      check(fs.readTextSync(appRoot + '/gallery/001.txt') === 'verified migration page one', 'Copied destination remains readable');
      await delegator.print('PASS: cleanup warning preserves new source files and copied destination\n');
    } finally {
      // Exact, test-owned paths only; no recursive deletion or real download metadata changes.
      const roots: string[] = [appRoot, publicRoot];
      for (let i = 0; i < roots.length; i++) {
        const root = roots[i];
        check(root.endsWith('/' + name), 'Refuse cleanup outside the fixture roots');
        const paths: string[] = ['/gallery/001.txt', '/gallery/metadata.json', '/late.txt'];
        for (let j = 0; j < paths.length; j++) {
          if (fs.accessSync(root + paths[j])) {
            fs.unlinkSync(root + paths[j]);
          }
        }
        if (fs.accessSync(root + '/gallery')) {
          check(fs.listFileSync(root + '/gallery').length === 0, 'Unexpected fixture contents');
          fs.rmdirSync(root + '/gallery');
        }
        check(fs.listFileSync(root).length === 0, 'Unexpected files in fixture root');
        fs.rmdirSync(root);
      }
    }
    await delegator.print('PASS: 3 isolated migration cases; temporary files removed\n');
}
