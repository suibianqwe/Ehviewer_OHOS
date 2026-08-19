import { ehBookmarkStore } from '../services/EhBookmarkStore';
import { ehDownloadStore } from '../services/EhDownloadStore';
import { ehLocalFavoritesStore } from '../services/EhLocalFavoritesStore';
import { ehCommentBlacklistStore } from '../services/EhCommentBlacklistStore';
import { ehCookieStore } from '../services/EhCookieStore';
import { ehHistoryStore } from '../services/EhHistoryStore';
import { ehSettingsStore } from '../services/EhSettingsStore';
import {
  WifiMigrationDataKind,
  WifiMigrationPeer,
  WifiMigrationPhase,
  WifiMigrationRole,
  WifiMigrationSession,
  WifiMigrationSnapshot
} from '../services/WifiMigrationService';
import { getAbilityContext, uiStatusText, uiText } from '../shared/EhShared';
import {
  themeDangerBackground,
  themeDangerText,
  themeFieldBackground,
  themeOnPrimaryText,
  themePageBackground,
  themePrimaryColor,
  themePrimaryText,
  themeSecondaryText,
  themeSelectedBackground,
  themeSurface,
  themeSurfaceVariant,
  themeTertiaryText
} from '../shared/EhTheme';
import { AppSubToolbar } from './NavigationComponents';

@Component
export struct WifiMigrationPanel {
  onBack: () => void = () => {};
  @State role: WifiMigrationRole = WifiMigrationRole.Server;
  @State dataKinds: WifiMigrationDataKind[] = [WifiMigrationDataKind.Progress];
  @State phase: WifiMigrationPhase = WifiMigrationPhase.Idle;
  @State status: string = 'Wi-Fi transfer is idle';
  @State peerAddress: string = '';
  @State peerName: string = '';
  @State localDeviceName: string = '';
  @State peers: WifiMigrationPeer[] = [];
  @State currentPage: number = 0;
  @State totalPages: number = 0;
  @State transferredItems: number = 0;
  @State transferredFiles: number = 0;
  @State totalFiles: number = 0;
  @State transferredBytes: number = 0;
  @State totalBytes: number = 0;
  @State bookmarkCount: number = 0;
  @State progressCount: number = 0;
  @State favoriteCount: number = 0;
  @State downloadCount: number = 0;
  @State blacklistCount: number = 0;
  @State settingsCount: number = 0;
  private session: WifiMigrationSession | null = null;

  aboutToAppear(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.status = 'Wi-Fi transfer needs app context';
      this.phase = WifiMigrationPhase.Error;
      return;
    }
    this.session = new WifiMigrationSession(context, (snapshot: WifiMigrationSnapshot) => {
      this.applySnapshot(snapshot);
    });
    Promise.all([
      waitForCountStore(ehBookmarkStore.ensureLoaded(context)),
      waitForCountStore(ehLocalFavoritesStore.ensureLoaded(context)),
      waitForCountStore(ehCommentBlacklistStore.ensureLoaded(context)),
      waitForCountStore(ehHistoryStore.ensureLoaded(context)),
      waitForCountStore(ehSettingsStore.ensureLoaded(context)),
      waitForCountStore(ehCookieStore.ensureLoaded(context)),
      waitForCountStore(ehDownloadStore.ensureLoaded(context))
    ]).then(() => {
      if (this.session !== null) {
        this.refreshCounts();
      }
    });
  }

  aboutToDisappear(): void {
    if (this.session !== null) {
      this.session.stop().catch(() => {});
      this.session = null;
    }
  }

  private applySnapshot(snapshot: WifiMigrationSnapshot): void {
    this.role = snapshot.role;
    this.phase = snapshot.phase;
    this.status = snapshot.status;
    this.peerAddress = snapshot.peerAddress;
    this.peerName = snapshot.peerName;
    this.localDeviceName = snapshot.localDeviceName;
    this.peers = snapshot.peers;
    this.currentPage = snapshot.currentPage;
    this.totalPages = snapshot.totalPages;
    this.transferredItems = snapshot.transferredItems;
    this.transferredFiles = snapshot.transferredFiles;
    this.totalFiles = snapshot.totalFiles;
    this.transferredBytes = snapshot.transferredBytes;
    this.totalBytes = snapshot.totalBytes;
    if (snapshot.phase === WifiMigrationPhase.Completed) {
      this.refreshCounts();
    }
  }

  private refreshCounts(): void {
    this.progressCount = ehHistoryStore.getReadingProgressCount();
    this.bookmarkCount = ehBookmarkStore.getItems().length;
    this.favoriteCount = ehLocalFavoritesStore.count();
    this.downloadCount = ehDownloadStore.getItems().length;
    this.blacklistCount = ehCommentBlacklistStore.count();
    this.settingsCount = ehSettingsStore.getTransferEntries().length +
      (ehCookieStore.getTransferCookieHeader().length > 0 ? 1 : 0);
  }

  private active(): boolean {
    return this.phase === WifiMigrationPhase.Starting || this.phase === WifiMigrationPhase.Waiting ||
      this.phase === WifiMigrationPhase.Connected || this.phase === WifiMigrationPhase.Transferring ||
      this.phase === WifiMigrationPhase.Completed;
  }

  private progressValue(): number {
    if (this.totalBytes > 0) {
      return Math.min(100, Math.max(0, Math.floor(this.transferredBytes * 100 / this.totalBytes)));
    }
    if (this.totalPages > 0) {
      return Math.min(100, Math.max(0, Math.floor(this.currentPage * 100 / this.totalPages)));
    }
    return 0;
  }

  private switchRole(role: WifiMigrationRole): void {
    if (this.role === role) {
      return;
    }
    const apply = () => {
      this.role = role;
      this.phase = WifiMigrationPhase.Idle;
      this.status = 'Wi-Fi transfer is idle';
      this.peerAddress = '';
      this.peerName = '';
      this.peers = [];
      this.currentPage = 0;
      this.totalPages = 0;
      this.transferredItems = 0;
      this.transferredFiles = 0;
      this.totalFiles = 0;
      this.transferredBytes = 0;
      this.totalBytes = 0;
    };
    if (this.session === null) {
      apply();
      return;
    }
    this.session.stop().then(apply).catch(apply);
  }

  private runPrimaryAction(): void {
    if (this.session === null) {
      return;
    }
    if (this.active()) {
      this.session.stop().catch((error: Error) => {
        this.status = error.message;
        this.phase = WifiMigrationPhase.Error;
      });
      return;
    }
    if (this.role === WifiMigrationRole.Server) {
      this.session.startServer(this.dataKinds).catch((error: Error) => {
        this.status = error.message;
        this.phase = WifiMigrationPhase.Error;
      });
    } else {
      this.session.discoverPeers().catch((error: Error) => {
        this.status = error.message;
        this.phase = WifiMigrationPhase.Error;
      });
    }
  }

  private connectPeer(peer: WifiMigrationPeer): void {
    if (this.session === null || this.role !== WifiMigrationRole.Client) {
      return;
    }
    this.session.connectToPeer(peer.address);
  }

  private primaryLabel(): string {
    if (this.active()) {
      return this.role === WifiMigrationRole.Server ? 'Stop sending' : 'Stop Wi-Fi Direct';
    }
    return this.role === WifiMigrationRole.Server ? 'Start sending' : 'Scan nearby devices';
  }

  private selectedCount(): number {
    let count = 0;
    if (this.isDataKindSelected(WifiMigrationDataKind.Progress)) count += this.progressCount;
    if (this.isDataKindSelected(WifiMigrationDataKind.Settings)) count += this.settingsCount;
    if (this.isDataKindSelected(WifiMigrationDataKind.Bookmarks)) count += this.bookmarkCount;
    if (this.isDataKindSelected(WifiMigrationDataKind.Favorites)) count += this.favoriteCount;
    if (this.isDataKindSelected(WifiMigrationDataKind.Blacklist)) count += this.blacklistCount;
    if (this.isDataKindSelected(WifiMigrationDataKind.Downloads)) count += this.downloadCount;
    return count;
  }

  private isDataKindSelected(kind: WifiMigrationDataKind): boolean {
    for (let i = 0; i < this.dataKinds.length; i++) {
      if (this.dataKinds[i] === kind) {
        return true;
      }
    }
    return false;
  }

  private toggleDataKind(kind: WifiMigrationDataKind): void {
    const selected = this.isDataKindSelected(kind);
    const next: WifiMigrationDataKind[] = [];
    for (let i = 0; i < this.dataKinds.length; i++) {
      if (this.dataKinds[i] !== kind) {
        next.push(this.dataKinds[i]);
      }
    }
    if (!selected) {
      next.push(kind);
    }
    this.dataKinds = next;
  }

  @Builder
  private roleButton(role: WifiMigrationRole, title: string, summary: string, symbol: Resource) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 10 }) {
        SymbolGlyph(symbol)
          .fontSize(22)
          .fontColor([this.role === role ? themeOnPrimaryText() : themePrimaryColor()])
        Column({ space: 2 }) {
          Text(uiText(title))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.role === role ? themeOnPrimaryText() : themePrimaryText())
          Text(uiText(summary))
            .fontSize(11)
            .fontColor(this.role === role ? themeOnPrimaryText() : themeSecondaryText())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
    }
    .height(68)
    .layoutWeight(1)
    .padding({ left: 14, right: 14 })
    .backgroundColor(this.role === role ? themePrimaryColor() : themeSurfaceVariant())
    .borderRadius(8)
    .onClick(() => {
      this.switchRole(role);
    })
  }

  @Builder
  private dataCard(kind: WifiMigrationDataKind, title: string, summary: string, count: number, symbol: Resource) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          Row()
            .width(42)
            .height(42)
            .backgroundColor(this.isDataKindSelected(kind) ? themePrimaryColor() : themeFieldBackground())
            .borderRadius(21)
          SymbolGlyph(symbol)
            .fontSize(21)
            .fontColor([this.isDataKindSelected(kind) ? themeOnPrimaryText() : themePrimaryColor()])
        }
        Column({ space: 3 }) {
          Text(uiText(title))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
          Text(uiText(summary))
            .fontSize(11)
            .fontColor(themeSecondaryText())
            .maxLines(2)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(count.toString())
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isDataKindSelected(kind) ? themeOnPrimaryText() : themePrimaryColor())
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(this.isDataKindSelected(kind) ? themePrimaryColor() : themeSelectedBackground())
          .borderRadius(14)
      }
      .width('100%')
    }
    .width('100%')
    .height(72)
    .padding({ left: 12, right: 12 })
    .backgroundColor(this.isDataKindSelected(kind) ? themeSelectedBackground() : themeSurface())
    .borderRadius(8)
    .onClick(() => {
      if (!this.active()) {
        this.toggleDataKind(kind);
      }
    })
  }

  @Builder
  private peerCard(peer: WifiMigrationPeer) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          Row()
            .width(42)
            .height(42)
            .backgroundColor(themeSelectedBackground())
            .borderRadius(21)
          SymbolGlyph($r('sys.symbol.wifi'))
            .fontSize(21)
            .fontColor([themePrimaryColor()])
        }
        Column({ space: 3 }) {
          Text(peer.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(themePrimaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(peer.address)
            .fontSize(11)
            .fontColor(themeSecondaryText())
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(uiText('Connect'))
          .fontSize(13)
          .fontColor(themeOnPrimaryText())
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(themePrimaryColor())
          .borderRadius(15)
      }
      .width('100%')
    }
    .width('100%')
    .height(66)
    .padding({ left: 12, right: 12 })
    .backgroundColor(themeSurface())
    .borderRadius(8)
    .onClick(() => {
      this.connectPeer(peer);
    })
  }

  build() {
    Column() {
      AppSubToolbar({
        title: uiText('Wi-Fi Direct transfer'),
        onBack: this.onBack
      })

      Scroll() {
        Column({ space: 12 }) {
          Row({ space: 10 }) {
            this.roleButton(WifiMigrationRole.Server, 'Send data', 'Advertise the sending device',
              $r('sys.symbol.arrow_up_circle'))
            this.roleButton(WifiMigrationRole.Client, 'Receive data', 'Discover the sending device',
              $r('sys.symbol.arrow_down_circle'))
          }
          .width('100%')

          Column({ space: 12 }) {
            Row({ space: 10 }) {
              Stack({ alignContent: Alignment.Center }) {
                Row()
                  .width(44)
                  .height(44)
                  .backgroundColor(this.phase === WifiMigrationPhase.Error ? themeDangerBackground() :
                    themeSelectedBackground())
                  .borderRadius(22)
                SymbolGlyph(this.phase === WifiMigrationPhase.Error ? $r('sys.symbol.exclamationmark_triangle') :
                  $r('sys.symbol.wifi'))
                  .fontSize(22)
                  .fontColor([this.phase === WifiMigrationPhase.Error ? themeDangerText() : themePrimaryColor()])
              }
              Column({ space: 3 }) {
                Text(uiText('Connection status'))
                  .fontSize(12)
                  .fontColor(themeSecondaryText())
                Text(uiStatusText(this.status))
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.phase === WifiMigrationPhase.Error ? themeDangerText() : themePrimaryText())
                  .maxLines(3)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')

            if (this.totalPages > 0 || this.totalBytes > 0) {
              Progress({ value: this.progressValue(), total: 100, type: ProgressType.Linear })
                .width('100%')
                .height(6)
                .color(themePrimaryColor())
                .backgroundColor(themeSurfaceVariant())
              Row() {
                Text(uiText('Progress') + ': ' + this.progressValue().toString() + '%')
                  .fontSize(11)
                  .fontColor(themeSecondaryText())
                Blank()
                Text(formatTransferBytes(this.transferredBytes) + ' / ' + formatTransferBytes(this.totalBytes))
                  .fontSize(11)
                  .fontColor(themeSecondaryText())
              }
              .width('100%')
              Row() {
                Text(uiText('Items') + ': ' + this.transferredItems.toString())
                  .fontSize(11)
                  .fontColor(themeSecondaryText())
                Blank()
                Text(uiText('Image files') + ': ' + this.transferredFiles.toString() + ' / ' +
                  this.totalFiles.toString())
                  .fontSize(11)
                  .fontColor(themeSecondaryText())
              }
              .width('100%')
            }

            Row() {
              Column({ space: 3 }) {
                Text(uiText('This device'))
                  .fontSize(11)
                  .fontColor(themeSecondaryText())
                Text(this.localDeviceName.length > 0 ? this.localDeviceName : uiText('Unavailable'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.localDeviceName.length > 0 ? themePrimaryText() : themeTertiaryText())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              if (this.peerName.length > 0 || this.peerAddress.length > 0) {
                Column({ space: 3 }) {
                  Text(uiText('Connected device'))
                    .fontSize(11)
                    .fontColor(themeSecondaryText())
                  Text(this.peerName.length > 0 ? this.peerName : this.peerAddress)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(themePrimaryColor())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.End)
                .layoutWeight(1)
              }
            }
            .width('100%')
            .padding({ top: 10 })
            .border({ width: { top: 1 }, color: themeSurfaceVariant() })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(themeSurface())
          .borderRadius(8)

          if (this.role === WifiMigrationRole.Server) {
            Column({ space: 8 }) {
              Row() {
                Text(uiText('Data to send'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(themePrimaryText())
                Blank()
                Text(uiText('Selected') + ': ' + this.selectedCount().toString())
                  .fontSize(12)
                  .fontColor(themePrimaryColor())
              }
              .width('100%')
              this.dataCard(WifiMigrationDataKind.Progress, 'Reading progress',
                'Merge the latest reading position on both devices', this.progressCount, $r('sys.symbol.book'))
              this.dataCard(WifiMigrationDataKind.Settings, 'Application settings',
                'Portable preferences, reader presets, service configurations, and login cookies excluding igneous',
                this.settingsCount,
                $r('sys.symbol.gearshape'))
              this.dataCard(WifiMigrationDataKind.Bookmarks, 'Search bookmarks',
                'Saved quick searches and their search options', this.bookmarkCount, $r('sys.symbol.bookmark'))
              this.dataCard(WifiMigrationDataKind.Favorites, 'Local favorites',
                'Locally saved gallery information', this.favoriteCount, $r('sys.symbol.heart'))
              this.dataCard(WifiMigrationDataKind.Blacklist, 'Comment blacklist',
                'Blocked comment user names and saved reasons', this.blacklistCount,
                $r('sys.symbol.xmark_circle'))
              this.dataCard(WifiMigrationDataKind.Downloads, 'Downloads and images',
                'Transfer download records and all downloaded image files', this.downloadCount,
                $r('sys.symbol.arrow_down_circle'))
            }
            .width('100%')
          } else {
            Column({ space: 8 }) {
              Row() {
                Text(uiText('Nearby devices'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(themePrimaryText())
                Blank()
                Text(this.peers.length.toString())
                  .fontSize(12)
                  .fontColor(themePrimaryColor())
              }
              .width('100%')
              if (this.peers.length === 0) {
                Text(uiText('Start scanning, then select the sender device from the list'))
                  .fontSize(13)
                  .lineHeight(20)
                  .fontColor(themeSecondaryText())
                  .width('100%')
                  .padding(16)
                  .backgroundColor(themeSurface())
                  .borderRadius(8)
              } else {
                ForEach(this.peers, (peer: WifiMigrationPeer) => {
                  this.peerCard(peer)
                }, (peer: WifiMigrationPeer) => peer.address)
              }
            }
            .width('100%')
          }

          Button(uiText(this.primaryLabel()), { type: ButtonType.Normal, stateEffect: true })
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.active() ? themeDangerText() : themeOnPrimaryText())
            .backgroundColor(this.active() ? themeDangerBackground() : themePrimaryColor())
            .borderRadius(8)
            .onClick(() => {
              this.runPrimaryAction();
            })

          Column({ space: 7 }) {
            Text(uiText('Wi-Fi Direct instructions'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(themePrimaryText())
            Text(uiText('On the sending device, choose the data and start sending. On the receiving device, scan and select the sender.'))
              .fontSize(12)
              .lineHeight(19)
              .fontColor(themeSecondaryText())
            Text(uiText('Keep both transfer pages open until completion. Download transfer includes metadata and downloaded image files.'))
              .fontSize(12)
              .lineHeight(19)
              .fontColor(themeSecondaryText())
            Text(uiText('Reading progress is merged in both directions; the newer position is kept on both devices.'))
              .fontSize(12)
              .lineHeight(19)
              .fontColor(themeSecondaryText())
            Text(uiText('The direct group and data server stop automatically when this page is closed.'))
              .fontSize(12)
              .lineHeight(19)
              .fontColor(themeSecondaryText())
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(16)
          .backgroundColor(themeSurface())
          .borderRadius(8)
          .margin({ bottom: 18 })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.None)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themePageBackground())
  }
}

function formatTransferBytes(bytes: number): string {
  const safe = Math.max(0, bytes);
  if (safe >= 1024 * 1024 * 1024) {
    return (safe / (1024 * 1024 * 1024)).toFixed(2) + ' GiB';
  }
  if (safe >= 1024 * 1024) {
    return (safe / (1024 * 1024)).toFixed(1) + ' MiB';
  }
  if (safe >= 1024) {
    return (safe / 1024).toFixed(1) + ' KiB';
  }
  return safe.toString() + ' B';
}

function waitForCountStore(promise: Promise<void>): Promise<void> {
  return promise.catch(() => {});
}
