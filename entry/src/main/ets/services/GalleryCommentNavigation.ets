import { GalleryDetailLink } from './GalleryDetailSupport';

export function commentGalleryIdentity(link: GalleryDetailLink): string {
  // E and Ex mirrors, query strings and comment anchors are the same gallery.
  return link.gid.toString() + ':' + link.token.toLowerCase();
}

export function canOpenCommentGallery(current: GalleryDetailLink, target: GalleryDetailLink,
  ancestors: string[]): boolean {
  if (!Number.isSafeInteger(target.gid) || target.gid <= 0 || target.token.length === 0 || ancestors.length >= 16) {
    return false;
  }
  const identity = commentGalleryIdentity(target);
  return identity !== commentGalleryIdentity(current) && ancestors.indexOf(identity) < 0;
}
