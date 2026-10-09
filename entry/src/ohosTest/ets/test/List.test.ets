import { describe, it } from '@ohos/hypium';
import { runMigrationRegression } from './DownloadMigration.test';

export default function testsuite(): void {
  describe('DownloadMigrationRegression', () => {
    it('migrates_isolated_real_files_in_both_directions', 0, async () => {
      await runMigrationRegression();
    });
  });
}
