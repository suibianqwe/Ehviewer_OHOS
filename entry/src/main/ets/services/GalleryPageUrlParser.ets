export interface GalleryPageUrlInfo {
  pageToken: string;
  gid: number;
  pageIndex: number;
}

export function parseGalleryPageUrl(url: string): GalleryPageUrlInfo | null {
  const match = /^https?:\/\/[^\/?#]+\/s\/([^\/?#]+)\/(\d+)-(\d+)/i.exec(url);
  if (match === null) {
    return null;
  }

  const gid = Number.parseInt(match[2]);
  const page = Number.parseInt(match[3]);
  if (Number.isNaN(gid) || Number.isNaN(page) || page <= 0) {
    return null;
  }

  return {
    pageToken: match[1],
    gid: gid,
    pageIndex: page - 1
  };
}
