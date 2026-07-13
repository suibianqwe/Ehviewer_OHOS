import { GallerySite } from '../model/GalleryModels';
import { ehCookieStore } from './EhCookieStore';

export function gallerySiteCandidates(selectedSite: GallerySite): GallerySite[] {
  if (selectedSite === GallerySite.E && ehCookieStore.hasCookies()) {
    return [GallerySite.E, GallerySite.Ex];
  }
  return [selectedSite];
}
