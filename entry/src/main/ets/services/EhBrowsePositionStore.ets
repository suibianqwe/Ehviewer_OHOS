import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const PREFERENCES_NAME: string = 'ehviewer_browse_positions';
const VALUES_KEY: string = 'positions';

export interface BrowsePosition {
  anchorId: string;
  anchorIndex: number;
  offset: number;
}

interface StoredBrowsePositions {
  bookmarkDrawer?: BrowsePosition;
  downloads?: BrowsePosition;
}

function emptyBrowsePosition(): BrowsePosition {
  return { anchorId: '', anchorIndex: 0, offset: 0 };
}

function normalizeBrowsePosition(value: BrowsePosition | undefined): BrowsePosition {
  if (value === undefined) {
    return emptyBrowsePosition();
  }
  return {
    anchorId: typeof value.anchorId === 'string' ? value.anchorId : '',
    anchorIndex: Number.isFinite(value.anchorIndex) ? Math.max(0, Math.floor(value.anchorIndex)) : 0,
    offset: Number.isFinite(value.offset) ? Math.max(0, value.offset) : 0
  };
}

function cloneBrowsePosition(value: BrowsePosition): BrowsePosition {
  return { anchorId: value.anchorId, anchorIndex: value.anchorIndex, offset: value.offset };
}

export class EhBrowsePositionStore {
  private bookmarkDrawer: BrowsePosition = emptyBrowsePosition();
  private downloads: BrowsePosition = emptyBrowsePosition();
  private context?: common.UIAbilityContext;
  private loaded: boolean = false;
  private loadPromise: Promise<void> | null = null;
  private saveTimer: number = -1;
  private saveChain: Promise<void> = Promise.resolve();

  async ensureLoaded(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    if (this.loaded) {
      return;
    }
    if (this.loadPromise !== null) {
      await this.loadPromise;
      return;
    }
    this.loadPromise = this.load(context);
    await this.loadPromise;
  }

  getBookmarkDrawerPosition(): BrowsePosition {
    return cloneBrowsePosition(this.bookmarkDrawer);
  }

  getDownloadPosition(): BrowsePosition {
    return cloneBrowsePosition(this.downloads);
  }

  updateBookmarkDrawerPosition(anchorId: string, anchorIndex: number, offset: number): void {
    this.bookmarkDrawer = normalizeBrowsePosition({
      anchorId: anchorId,
      anchorIndex: anchorIndex,
      offset: offset
    });
    this.scheduleSave();
  }

  updateDownloadPosition(anchorId: string, anchorIndex: number, offset: number): void {
    this.downloads = normalizeBrowsePosition({
      anchorId: anchorId,
      anchorIndex: anchorIndex,
      offset: offset
    });
    this.scheduleSave();
  }

  flush(): void {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    this.queueSave();
  }

  private async load(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const raw = await prefs.get(VALUES_KEY, '');
      if (typeof raw === 'string' && raw.length > 0) {
        const parsed = JSON.parse(raw) as StoredBrowsePositions;
        this.bookmarkDrawer = normalizeBrowsePosition(parsed.bookmarkDrawer);
        this.downloads = normalizeBrowsePosition(parsed.downloads);
      }
    } catch (error) {
      this.bookmarkDrawer = emptyBrowsePosition();
      this.downloads = emptyBrowsePosition();
    } finally {
      this.loaded = true;
      this.loadPromise = null;
    }
  }

  private scheduleSave(): void {
    if (!this.loaded || this.context === undefined) {
      return;
    }
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout(() => {
      this.saveTimer = -1;
      this.queueSave();
    }, 240);
  }

  private queueSave(): void {
    const context = this.context;
    if (!this.loaded || context === undefined) {
      return;
    }
    const snapshot: StoredBrowsePositions = {
      bookmarkDrawer: cloneBrowsePosition(this.bookmarkDrawer),
      downloads: cloneBrowsePosition(this.downloads)
    };
    this.saveChain = this.saveChain.then(async () => {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(VALUES_KEY, JSON.stringify(snapshot));
      await prefs.flush();
    }).catch(() => {});
  }
}

export const ehBrowsePositionStore: EhBrowsePositionStore = new EhBrowsePositionStore();
