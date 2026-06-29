import { GalleryDetail, GalleryPage, GallerySite } from '../model/GalleryModels';
import { cloneGalleryDetail, cloneGalleryPage, cloneGalleryPreviews } from '../shared/EhShared';

export const READER_SESSION_REVISION_KEY: string = 'readerSessionRevision';

export interface ReaderSessionState {
  detail: GalleryDetail;
  page: GalleryPage;
  pages: ReaderSessionPageState[];
  statusText: string;
  detailRequestUrl: string;
  listRequestUrl: string;
  site: GallerySite;
  pageIndex: number;
}

export interface ReaderSessionPageState {
  index: number;
  page: GalleryPage;
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
  detailRequestUrl: string, listRequestUrl: string, site: GallerySite, pageIndex: number,
  pages: ReaderSessionPageState[] = []): ReaderSessionState {
  return {
    detail: cloneGalleryDetail(detail),
    page: cloneGalleryPage(page),
    pages: cloneReaderSessionPages(pages),
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
    pages: cloneReaderSessionPages(state.pages),
    statusText: state.statusText,
    detailRequestUrl: state.detailRequestUrl,
    listRequestUrl: state.listRequestUrl,
    site: state.site,
    pageIndex: state.pageIndex
  };
}

function cloneReaderSessionPages(pages: ReaderSessionPageState[]): ReaderSessionPageState[] {
  const next: ReaderSessionPageState[] = [];
  for (let i = 0; i < pages.length; i++) {
    next.push({
      index: pages[i].index,
      page: cloneGalleryPage(pages[i].page)
    });
  }
  return next;
}
