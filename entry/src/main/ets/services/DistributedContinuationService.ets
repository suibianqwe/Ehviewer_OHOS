import { AbilityConstant, common, Want } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { GalleryDetail, GalleryPage } from '../model/GalleryModels';
import { ReaderSessionPageState, ReaderSessionState } from './ReaderSessionStore';
import { ehSettingsStore, MULTI_DEVICE_CONTINUATION_SETTING_KEY } from './EhSettingsStore';

export const EH_CONTINUATION_DATA_KEY: string = 'ehviewer.continuation.data';
export const EH_CONTINUATION_PENDING_KEY: string = 'ehviewer.continuation.pending';
export const EH_CONTINUATION_ROUTE_KEY: string = 'ehviewer.continuation.route';
export const EH_CONTINUATION_VERSION: number = 1;
const MAX_CONTINUATION_BYTES: number = 90000;

export function isMultiDeviceContinuationEnabled(): boolean {
  return ehSettingsStore.getValue(MULTI_DEVICE_CONTINUATION_SETTING_KEY, 'Off') === 'On';
}

export function applyMissionContinuationSetting(context: common.UIAbilityContext | undefined): void {
  if (context === undefined) {
    return;
  }
  try {
    if (!deviceInfo.apiAvailable(10)) {
      return;
    }
    const state = isMultiDeviceContinuationEnabled()
      ? AbilityConstant.ContinueState.ACTIVE
      : AbilityConstant.ContinueState.INACTIVE;
    context.setMissionContinueState(state).catch(() => {});
  } catch (_error) {
    // API 9 and earlier keep the local navigation behavior.
  }
}

export type EhContinuationKind = 'main' | 'embedded_reader' | 'standalone_reader';

export interface EhContinuationSnapshot {
  version: number;
  kind: EhContinuationKind;
  route: string;
  timestamp: number;
  readerSession?: ReaderSessionState;
}

let pendingSnapshot: EhContinuationSnapshot | null = null;

export function rememberContinuationRoute(route: string): void {
  if (route.length > 0) {
    AppStorage.setOrCreate<string>(EH_CONTINUATION_ROUTE_KEY, route);
  }
}

export function continuationRoute(): string {
  return AppStorage.get<string>(EH_CONTINUATION_ROUTE_KEY) ?? '';
}

export function buildReaderContinuationSnapshot(kind: EhContinuationKind, route: string,
  session: ReaderSessionState | null): EhContinuationSnapshot {
  const snapshot: EhContinuationSnapshot = {
    version: EH_CONTINUATION_VERSION,
    kind: kind,
    route: route,
    timestamp: Date.now()
  };
  if (session !== null) {
    snapshot.readerSession = compactReaderSession(session);
  }
  return snapshot;
}

export function putContinuationSnapshot(wantParam: Record<string, Object>, snapshot: EhContinuationSnapshot): boolean {
  const encoded = encodeContinuationSnapshot(snapshot);
  if (encoded.length === 0) {
    return false;
  }
  wantParam[EH_CONTINUATION_DATA_KEY] = encoded;
  return true;
}

export function encodeContinuationSnapshot(snapshot: EhContinuationSnapshot): string {
  try {
    const encoded = JSON.stringify(snapshot);
    if (encoded.length > MAX_CONTINUATION_BYTES) {
      return '';
    }
    return encoded;
  } catch (_error) {
    return '';
  }
}

export function readContinuationSnapshot(want: Want | undefined): EhContinuationSnapshot | null {
  if (want === undefined || want.parameters === undefined) {
    return null;
  }
  const raw = want.parameters[EH_CONTINUATION_DATA_KEY];
  if (typeof raw !== 'string' || raw.length === 0 || raw.length > MAX_CONTINUATION_BYTES) {
    return null;
  }
  try {
    const value = JSON.parse(raw) as EhContinuationSnapshot;
    if (value === undefined || value.version !== EH_CONTINUATION_VERSION ||
      (value.kind !== 'main' && value.kind !== 'embedded_reader' && value.kind !== 'standalone_reader') ||
      typeof value.route !== 'string' || typeof value.timestamp !== 'number') {
      return null;
    }
    if (value.readerSession !== undefined && !isValidReaderSession(value.readerSession)) {
      return null;
    }
    return value;
  } catch (_error) {
    return null;
  }
}

export function setPendingContinuationSnapshot(snapshot: EhContinuationSnapshot | null): void {
  pendingSnapshot = snapshot;
  AppStorage.setOrCreate<boolean>(EH_CONTINUATION_PENDING_KEY, snapshot !== null);
}

export function takePendingContinuationSnapshot(): EhContinuationSnapshot | null {
  const snapshot = pendingSnapshot;
  pendingSnapshot = null;
  AppStorage.setOrCreate<boolean>(EH_CONTINUATION_PENDING_KEY, false);
  return snapshot;
}

export function peekPendingContinuationSnapshot(): EhContinuationSnapshot | null {
  return pendingSnapshot;
}

function compactReaderSession(session: ReaderSessionState): ReaderSessionState {
  const pages: ReaderSessionPageState[] = [];
  const sourcePages = session.pages;
  const start = Math.max(0, session.pageIndex - 2);
  const end = Math.min(sourcePages.length, session.pageIndex + 4);
  for (let i = 0; i < sourcePages.length; i++) {
    const item = sourcePages[i];
    if (item.index >= start && item.index < end) {
      pages.push({ index: item.index, page: compactPage(item.page) });
    }
  }
  return {
    detail: compactDetail(session.detail),
    page: compactPage(session.page),
    pages: pages,
    statusText: session.statusText,
    detailRequestUrl: session.detailRequestUrl,
    listRequestUrl: session.listRequestUrl,
    site: session.site,
    pageIndex: session.pageIndex
  };
}

function compactDetail(detail: GalleryDetail): GalleryDetail {
  // Preview metadata is needed to paint the reader immediately. Keep it
  // bounded; missing previews are fetched again on the destination device.
  const copy = JSON.parse(JSON.stringify(detail)) as GalleryDetail;
  if (copy.previewSet.length > 80) {
    copy.previewSet = copy.previewSet.slice(0, 80);
  }
  copy.comments = [];
  copy.tags = [];
  return copy;
}

function compactPage(page: GalleryPage): GalleryPage {
  return {
    pageUrl: page.pageUrl,
    imageUrl: page.imageUrl,
    skipHathKey: page.skipHathKey,
    originImageUrl: page.originImageUrl,
    showKey: page.showKey
  };
}

function isValidReaderSession(session: ReaderSessionState): boolean {
  return session !== undefined && session.detail !== undefined && session.page !== undefined &&
    Array.isArray(session.pages) && typeof session.pageIndex === 'number' &&
    session.pageIndex >= 0 &&
    typeof session.detailRequestUrl === 'string' && typeof session.listRequestUrl === 'string';
}
