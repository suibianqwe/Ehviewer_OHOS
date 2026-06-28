import { GalleryDetail, GalleryInfo, GallerySite } from '../model/GalleryModels';
import { createDetailFromGallery, createEmptyGallery, cloneGalleryDetail, cloneGalleryInfo } from '../shared/EhShared';
import { EhHttpClient, GalleryDetailLoadResult } from './EhHttpClient';
import { EhUrl } from './EhUrl';

export interface GalleryDetailLink {
  gid: number;
  token: string;
  url: string;
  referer: string;
  site: GallerySite;
  seed: GalleryInfo;
}

export interface GalleryDetailModuleLoadResult {
  ok: boolean;
  url: string;
  statusText: string;
  detail: GalleryDetail;
}

interface ParsedGalleryDetailUrl {
  gid: number;
  token: string;
}

export function createEmptyGalleryDetailLink(): GalleryDetailLink {
  return {
    gid: 0,
    token: '',
    url: '',
    referer: '',
    site: GallerySite.E,
    seed: createEmptyGallery()
  };
}

export function createGalleryDetailLinkFromGallery(gallery: GalleryInfo, site: GallerySite,
  referer: string = ''): GalleryDetailLink {
  const url = EhUrl.getGalleryDetailUrl(gallery.gid, gallery.token, 0, false, site);
  return {
    gid: gallery.gid,
    token: gallery.token,
    url: url,
    referer: referer.length > 0 ? referer : EhUrl.getReferer(site),
    site: site,
    seed: gallery
  };
}

export function createGalleryDetailLink(gid: number, token: string, title: string, site: GallerySite,
  referer: string = ''): GalleryDetailLink {
  const seed = createEmptyGallery();
  seed.gid = gid;
  seed.token = token;
  seed.title = title;
  return createGalleryDetailLinkFromGallery(seed, site, referer);
}

export function createGalleryDetailLinkFromUrl(url: string, site: GallerySite, referer: string = '',
  seed?: GalleryInfo): GalleryDetailLink | null {
  const parsed = parseGalleryDetailUrl(url);
  if (parsed === null) {
    return null;
  }
  const source = seed === undefined ? createEmptyGallery() : cloneGalleryInfo(seed);
  source.gid = parsed.gid;
  source.token = parsed.token;
  return {
    gid: parsed.gid,
    token: parsed.token,
    url: url,
    referer: referer.length > 0 ? referer : EhUrl.getReferer(site),
    site: site,
    seed: source
  };
}

export function initialDetailForLink(link: GalleryDetailLink): GalleryDetail {
  return createDetailFromGallery(link.seed);
}

export async function loadGalleryDetailModule(client: EhHttpClient,
  link: GalleryDetailLink): Promise<GalleryDetailModuleLoadResult> {
  const initial = initialDetailForLink(link);
  const result: GalleryDetailLoadResult = await client.loadGalleryDetail(link.gid, link.token, 0, link.site,
    link.referer);
  if (!result.ok || result.detail === null) {
    return {
      ok: false,
      url: result.url.length > 0 ? result.url : link.url,
      statusText: 'Detail load failed: ' + result.message,
      detail: initial
    };
  }
  return {
    ok: true,
    url: result.url.length > 0 ? result.url : link.url,
    statusText: 'Detail loaded',
    detail: mergeLoadedGalleryDetail(result.detail, initial)
  };
}

function mergeLoadedGalleryDetail(loaded: GalleryDetail, previous: GalleryDetail): GalleryDetail {
  const next = cloneGalleryDetail(loaded);
  if (next.title.length === 0 && previous.title.length > 0) {
    next.title = previous.title;
  }
  if ((next.titleJpn === undefined || next.titleJpn.length === 0) && previous.titleJpn !== undefined &&
    previous.titleJpn.length > 0) {
    next.titleJpn = previous.titleJpn;
  }
  if ((next.thumb === undefined || next.thumb.length === 0) && previous.thumb !== undefined &&
    previous.thumb.length > 0) {
    next.thumb = previous.thumb;
  }
  if ((next.thumb === undefined || next.thumb.length === 0) && next.previewSet.length > 0) {
    next.thumb = next.previewSet[0].imageUrl;
  }
  return next;
}

function parseGalleryDetailUrl(url: string): ParsedGalleryDetailUrl | null {
  const match = /\/g\/(\d+)\/([^\/?#]+)/i.exec(url);
  if (match === null) {
    return null;
  }
  const gid = Number.parseInt(match[1], 10);
  const token = match[2];
  if (!Number.isFinite(gid) || gid <= 0 || token.length === 0) {
    return null;
  }
  return { gid: gid, token: token };
}
