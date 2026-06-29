import { GalleryDetail, GalleryPage, GallerySite } from '../model/GalleryModels';
import { cloneGalleryDetail, cloneGalleryPage, cloneGalleryPreviews } from '../shared/EhShared';

export const READER_SESSION_REVISION_KEY: string = 'readerSessionRevision';

export interface ReaderSessionState {
  detail: GalleryDetail;
  page: GalleryPage;
  statusText: string;
  detailRequestUrl: string;
  listRequestUrl: string;
  site: GallerySite;
  pageIndex: number;
}

class ReaderSessionStore {
  private session: ReaderSessionState | null = null;

  setSession(state: ReaderSessionState): void {
    this.session = cloneReaderSessionState(state);
    const current = AppStorage.get<number>(READER_SESSION_REVISION_KEY);
    AppStorage.setOrCreate<number>(READER_SESSION_REVISION_KEY, current === undefined ? 1 : current + 1);
  }

  getSession(): ReaderSessionState | null {
    if (this.session === null) {
      return null;
    }
    return cloneReaderSessionState(this.session);
  }

  updateSession(state: ReaderSessionState): void {
    this.session = cloneReaderSessionState(state);
  }

  clear(): void {
    this.session = null;
  }
}

export const readerSessionStore: ReaderSessionStore = new ReaderSessionStore();

export function createReaderSessionState(detail: GalleryDetail, page: GalleryPage, statusText: string,
  detailRequestUrl: string, listRequestUrl: string, site: GallerySite, pageIndex: number): ReaderSessionState {
  return {
    detail: cloneGalleryDetail(detail),
    page: cloneGalleryPage(page),
    statusText: statusText,
    detailRequestUrl: detailRequestUrl,
    listRequestUrl: listRequestUrl,
    site: site,
    pageIndex: pageIndex
  };
}

function cloneReaderSessionState(state: ReaderSessionState): ReaderSessionState {
  const detail = cloneGalleryDetail(state.detail);
  detail.previewSet = cloneGalleryPreviews(state.detail.previewSet);
  return {
    detail: detail,
    page: cloneGalleryPage(state.page),
    statusText: state.statusText,
    detailRequestUrl: state.detailRequestUrl,
    listRequestUrl: state.listRequestUrl,
    site: state.site,
    pageIndex: state.pageIndex
  };
}
