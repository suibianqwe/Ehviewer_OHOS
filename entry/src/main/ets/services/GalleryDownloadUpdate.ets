import { GalleryDetail, GallerySite } from '../model/GalleryModels';
import { EhHttpClient } from './EhHttpClient';

export interface GalleryDownloadUpdateCheck {
  current: GalleryDetail;
  latest: GalleryDetail | null;
}

export async function checkGalleryDownloadUpdate(client: EhHttpClient, gid: number, token: string,
  site: GallerySite, referer: string): Promise<GalleryDownloadUpdateCheck> {
  const loaded = await client.loadGalleryDetail(gid, token, 0, site, referer, true);
  if (!loaded.ok || loaded.detail === null || loaded.detail.gid !== gid || loaded.detail.token !== token) {
    throw new Error('Unable to check the current gallery');
  }
  const current = loaded.detail;
  let latest = current;
  const seen = new Set<number>([gid]);
  for (let depth = 0; depth < 16; depth++) {
    const versions = latest.newerVersions ?? [];
    if (versions.length === 0) return { current: current, latest: latest.gid === gid ? null : latest };
    const next = versions.reduce((left, right) => left.gid > right.gid ? left : right);
    if (seen.has(next.gid)) throw new Error('Invalid gallery version chain');
    seen.add(next.gid);
    const result = await client.loadGalleryDetail(next.gid, next.token, 0, site, referer, true);
    if (!result.ok || result.detail === null || result.detail.gid !== next.gid || result.detail.token !== next.token) {
      throw new Error('Unable to load the updated gallery');
    }
    latest = result.detail;
  }
  throw new Error('Gallery version chain is too long');
}
