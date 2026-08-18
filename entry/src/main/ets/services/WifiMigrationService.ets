import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { socket } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SearchBookmarkBackupInfo, ehBookmarkStore } from './EhBookmarkStore';
import { ehDownloadFileStore } from './EhDownloadFileStore';
import { DownloadInfo, DownloadLabel, DownloadState, ehDownloadStore } from './EhDownloadStore';
import { LocalFavoriteBackupInfo, ehLocalFavoritesStore } from './EhLocalFavoritesStore';
import { CommentBlacklistBackupEntry, ehCommentBlacklistStore } from './EhCommentBlacklistStore';
import { ReadingProgressBackupInfo, ehHistoryStore } from './EhHistoryStore';
import { ehSettingsStore, SettingEntry, SettingImportResult } from './EhSettingsStore';
import { applyAppChromeImmersiveMode } from './EhWindowImmersive';
import { readerImageCache } from './ReaderImageCache';
import { notifyGalleryTitleChanged, notifyLanguageChanged, notifyThemeChanged } from '../shared/EhShared';

export const WIFI_MIGRATION_PORT: number = 54321;

const TRANSFER_PROTOCOL: string = 'ehviewer-ohos-wifi-direct';
const TRANSFER_VERSION: number = 4;
const PACKET_METADATA: string = 'metadata';
const PACKET_FILE: string = 'file';
const PACKET_COMPLETE: string = 'complete';
const PACKET_ACK: string = 'ack';
const FILE_CHUNK_SIZE: number = 256 * 1024;
const MAX_HEADER_BYTES: number = 64 * 1024;
const MAX_PACKET_PAYLOAD_BYTES: number = 32 * 1024 * 1024;
const ACK_TIMEOUT_MS: number = 60000;
const P2P_READY_TIMEOUT_MS: number = 30000;
const P2P_READY_POLL_INTERVAL_MS: number = 500;
const DOWNLOAD_PAGE_PROGRESS_SCALE: number = 1000;
const LOG_DOMAIN: number = 0x3214;
const LOG_TAG: string = 'WifiMigration';

export enum WifiMigrationRole {
  Server = 'server',
  Client = 'client'
}

export enum WifiMigrationDataKind {
  Progress = 'progress',
  Settings = 'settings',
  Bookmarks = 'bookmarks',
  Favorites = 'favorites',
  Blacklist = 'blacklist',
  Downloads = 'downloads'
}

export enum WifiMigrationPhase {
  Idle = 'idle',
  Starting = 'starting',
  Waiting = 'waiting',
  Connected = 'connected',
  Transferring = 'transferring',
  Completed = 'completed',
  Error = 'error'
}

export interface WifiMigrationPeer {
  name: string;
  address: string;
  addressType: wifiManager.DeviceAddressType;
  status: wifiManager.P2pDeviceStatus;
}

export interface WifiMigrationSnapshot {
  role: WifiMigrationRole;
  phase: WifiMigrationPhase;
  status: string;
  peerAddress: string;
  peerName: string;
  localDeviceName: string;
  peers: WifiMigrationPeer[];
  currentPage: number;
  totalPages: number;
  transferredItems: number;
  transferredFiles: number;
  totalFiles: number;
  transferredBytes: number;
  totalBytes: number;
}

type WifiMigrationObserver = (snapshot: WifiMigrationSnapshot) => void;

interface WifiTransferMetadata {
  version: number;
  kinds?: WifiMigrationDataKind[];
  kind?: WifiMigrationDataKind;
  settings?: SettingEntry[];
  readingProgress?: ReadingProgressBackupInfo[];
  bookmarks?: SearchBookmarkBackupInfo[];
  favorites?: LocalFavoriteBackupInfo[];
  blacklist?: CommentBlacklistBackupEntry[];
  downloadLabels?: DownloadLabel[];
  downloads?: DownloadInfo[];
}

interface WifiTransferPacketHeader {
  protocol: string;
  version: number;
  type: string;
  sequence: number;
  payloadLength: number;
  totalPackets: number;
  totalBytes: number;
  totalFiles: number;
  kind?: WifiMigrationDataKind;
  includesProgress?: boolean;
  fileGid?: number;
  fileName?: string;
  fileOffset?: number;
  fileSize?: number;
}

interface OutgoingTransferPacket {
  header: WifiTransferPacketHeader;
  payload?: Uint8Array;
  filePath?: string;
}

interface TransferPlan {
  packets: OutgoingTransferPacket[];
  itemCount: number;
  progressCount: number;
  fileCount: number;
  totalBytes: number;
}

interface TransferImageFile {
  gid: number;
  path: string;
  name: string;
  size: number;
}

export class WifiMigrationSession {
  private context: common.UIAbilityContext;
  private observer: WifiMigrationObserver;
  private role: WifiMigrationRole = WifiMigrationRole.Server;
  private phase: WifiMigrationPhase = WifiMigrationPhase.Idle;
  private status: string = 'Wi-Fi transfer is idle';
  private peerAddress: string = '';
  private peerName: string = '';
  private localDeviceName: string = '';
  private peers: WifiMigrationPeer[] = [];
  private currentPage: number = 0;
  private totalPages: number = 0;
  private transferredItems: number = 0;
  private transferredFiles: number = 0;
  private totalFiles: number = 0;
  private transferredBytes: number = 0;
  private totalBytes: number = 0;
  private server: socket.TCPSocketServer | null = null;
  private serverConnection: socket.TCPSocketConnection | null = null;
  private client: socket.TCPSocket | null = null;
  private outgoingPackets: OutgoingTransferPacket[] = [];
  private outgoingIndex: number = 0;
  private awaitingAck: boolean = false;
  private receiveBuffer: Uint8Array = new Uint8Array(0);
  private receiveChain: Promise<void> = Promise.resolve();
  private encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
  private ackTimer: number = 0;
  private stopped: boolean = false;
  private sessionVersion: number = 0;
  private listenersRegistered: boolean = false;
  private incomingMetadata: WifiTransferMetadata | null = null;
  private incomingDirectories: Map<number, string> = new Map<number, string>();
  private senderItemCount: number = 0;
  private senderProgressCount: number = 0;
  private dataChannelVersion: number = -1;

  private peerChangeCallback = (devices: wifiManager.WifiP2pDevice[]): void => {
    const peers: WifiMigrationPeer[] = [];
    for (let i = 0; i < devices.length; i++) {
      const device = devices[i];
      if (device.deviceAddress.length === 0 || device.deviceStatus === wifiManager.P2pDeviceStatus.UNAVAILABLE) {
        continue;
      }
      peers.push({
        name: device.deviceName.length > 0 ? device.deviceName : 'Nearby device',
        address: device.deviceAddress,
        addressType: device.deviceAddressType === undefined ? wifiManager.DeviceAddressType.RANDOM_DEVICE_ADDRESS :
          device.deviceAddressType,
        status: device.deviceStatus
      });
    }
    peers.sort((left: WifiMigrationPeer, right: WifiMigrationPeer): number => left.name.localeCompare(right.name));
    this.peers = peers;
    if (this.role === WifiMigrationRole.Client && this.phase === WifiMigrationPhase.Waiting) {
      this.status = peers.length > 0 ? 'Select the sending device' : 'Searching for nearby devices';
    }
    this.emit();
  };

  private connectionChangeCallback = (info: wifiManager.WifiP2pLinkedInfo): void => {
    const version = this.sessionVersion;
    this.logLinkedInfo('event', info);
    if (info.connectState !== wifiManager.P2pConnectState.CONNECTED) {
      if (!this.stopped && (this.phase === WifiMigrationPhase.Connected ||
        this.phase === WifiMigrationPhase.Transferring)) {
        this.fail('Wi-Fi Direct connection was disconnected');
      }
      return;
    }
    this.startDataChannel(version);
  };

  constructor(context: common.UIAbilityContext, observer: WifiMigrationObserver) {
    this.context = context;
    this.observer = observer;
    this.refreshLocalDevice().catch(() => {});
    this.emit();
  }

  snapshot(): WifiMigrationSnapshot {
    return {
      role: this.role,
      phase: this.phase,
      status: this.status,
      peerAddress: this.peerAddress,
      peerName: this.peerName,
      localDeviceName: this.localDeviceName,
      peers: clonePeers(this.peers),
      currentPage: this.currentPage,
      totalPages: this.totalPages,
      transferredItems: this.transferredItems,
      transferredFiles: this.transferredFiles,
      totalFiles: this.totalFiles,
      transferredBytes: this.transferredBytes,
      totalBytes: this.totalBytes
    };
  }

  async startServer(selectedKinds: WifiMigrationDataKind[]): Promise<void> {
    await this.resetForStart(WifiMigrationRole.Server);
    if (!isWifiReady()) {
      this.fail('Turn on Wi-Fi before using Wi-Fi Direct');
      return;
    }
    this.setState(WifiMigrationPhase.Starting, 'Preparing transfer data');
    await this.prepareStores();
    const kinds = normalizeDataKinds(selectedKinds);
    if (kinds.length === 0) {
      this.setState(WifiMigrationPhase.Idle, 'Select at least one data type to send');
      return;
    }
    const plan = createTransferPlan(this.context, kinds, this.encoder);
    if (!containsDataKind(kinds, WifiMigrationDataKind.Progress) && plan.itemCount <= 0 && plan.fileCount <= 0) {
      this.setState(WifiMigrationPhase.Idle, 'No data is available for this transfer');
      return;
    }
    this.outgoingPackets = plan.packets;
    this.senderItemCount = plan.itemCount;
    this.senderProgressCount = plan.progressCount;
    this.totalPages = plan.packets.length;
    this.totalFiles = plan.fileCount;
    this.totalBytes = plan.totalBytes;
    this.emit();
    this.ensureP2pListeners();
    await this.refreshLocalDevice();
    try {
      wifiManager.startDiscoverDevices();
    } catch (error) {
      throw new Error('Unable to advertise with Wi-Fi Direct: ' + cleanError(error));
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, `Sender is discoverable, session=%{public}d`, this.sessionVersion);
    this.setState(WifiMigrationPhase.Waiting, 'Waiting for a receiving device with Wi-Fi Direct');
  }

  async discoverPeers(): Promise<void> {
    await this.resetForStart(WifiMigrationRole.Client);
    if (!isWifiReady()) {
      this.fail('Turn on Wi-Fi before using Wi-Fi Direct');
      return;
    }
    this.ensureP2pListeners();
    await this.refreshLocalDevice();
    this.setState(WifiMigrationPhase.Waiting, 'Searching for nearby devices');
    try {
      wifiManager.startDiscoverDevices();
    } catch (error) {
      this.fail('Unable to discover Wi-Fi Direct devices: ' + cleanError(error));
      return;
    }
    try {
      this.peerChangeCallback(await wifiManager.getP2pPeerDevices());
    } catch (error) {
    }
  }

  connectToPeer(address: string): void {
    if (this.role !== WifiMigrationRole.Client || this.stopped) {
      return;
    }
    let selected: WifiMigrationPeer | null = null;
    for (let i = 0; i < this.peers.length; i++) {
      if (this.peers[i].address === address) {
        selected = this.peers[i];
        break;
      }
    }
    if (selected === null) {
      this.fail('The selected device is no longer available');
      return;
    }
    this.peerName = selected.name;
    this.peerAddress = selected.address;
    this.setState(WifiMigrationPhase.Starting, 'Connecting with Wi-Fi Direct');
    const config: wifiManager.WifiP2PConfig = {
      deviceAddress: selected.address,
      deviceAddressType: selected.addressType,
      netId: -2,
      passphrase: '',
      groupName: '',
      goBand: wifiManager.GroupOwnerBand.GO_BAND_AUTO
    };
    try {
      hilog.info(LOG_DOMAIN, LOG_TAG,
        `Connect requested, peer=%{public}s, addressType=%{public}d, status=%{public}d`,
        selected.name, selected.addressType, selected.status);
      wifiManager.p2pConnect(config);
      this.startDataChannel(this.sessionVersion);
    } catch (error) {
      this.fail('Unable to connect with Wi-Fi Direct: ' + cleanError(error));
    }
  }

  async stop(): Promise<void> {
    this.stopped = true;
    this.sessionVersion++;
    this.clearAckTimer();
    await this.closeSockets();
    this.stopP2p();
    this.unregisterP2pListeners();
    this.clearTransferState();
    this.peerAddress = '';
    this.peerName = '';
    this.peers = [];
    this.setState(WifiMigrationPhase.Idle, 'Wi-Fi transfer stopped');
  }

  private async resetForStart(role: WifiMigrationRole): Promise<void> {
    this.stopped = true;
    this.sessionVersion++;
    this.clearAckTimer();
    await this.closeSockets();
    this.stopP2p();
    this.unregisterP2pListeners();
    this.clearTransferState();
    this.role = role;
    this.peerAddress = '';
    this.peerName = '';
    this.peers = [];
    this.dataChannelVersion = -1;
    this.stopped = false;
    this.emit();
  }

  private async prepareStores(): Promise<void> {
    await Promise.all([
      ehBookmarkStore.ensureLoaded(this.context),
      ehLocalFavoritesStore.ensureLoaded(this.context),
      ehCommentBlacklistStore.ensureLoaded(this.context),
      ehHistoryStore.ensureLoaded(this.context),
      ehSettingsStore.ensureLoaded(this.context)
    ]);
  }

  private async refreshLocalDevice(): Promise<void> {
    if (!isWifiReady()) {
      return;
    }
    let local: wifiManager.WifiP2pDevice;
    try {
      local = await wifiManager.getP2pLocalDevice();
    } catch (error) {
      return;
    }
    this.localDeviceName = local.deviceName;
    this.emit();
  }

  private ensureP2pListeners(): void {
    if (this.listenersRegistered) {
      return;
    }
    try {
      wifiManager.on('p2pPeerDeviceChange', this.peerChangeCallback);
      wifiManager.on('p2pConnectionChange', this.connectionChangeCallback);
      this.listenersRegistered = true;
    } catch (error) {
      try {
        wifiManager.off('p2pPeerDeviceChange', this.peerChangeCallback);
      } catch (offError) {
      }
      try {
        wifiManager.off('p2pConnectionChange', this.connectionChangeCallback);
      } catch (offError) {
      }
      throw new Error('Unable to listen for Wi-Fi Direct state: ' + cleanError(error));
    }
  }

  private unregisterP2pListeners(): void {
    if (!this.listenersRegistered) {
      return;
    }
    try {
      wifiManager.off('p2pPeerDeviceChange', this.peerChangeCallback);
    } catch (error) {
    }
    try {
      wifiManager.off('p2pConnectionChange', this.connectionChangeCallback);
    } catch (error) {
    }
    this.listenersRegistered = false;
  }

  private stopP2p(): void {
    try {
      wifiManager.stopDiscoverDevices();
    } catch (error) {
    }
    try {
      wifiManager.p2pCancelConnect();
    } catch (error) {
    }
    try {
      wifiManager.removeGroup();
    } catch (error) {
    }
  }

  private startDataChannel(version: number): void {
    if (version !== this.sessionVersion || this.stopped || this.server !== null || this.serverConnection !== null ||
      this.client !== null || this.dataChannelVersion === version) {
      return;
    }
    this.dataChannelVersion = version;
    this.waitForDataChannel(version).then(() => {
      if (this.dataChannelVersion === version) {
        this.dataChannelVersion = -1;
      }
    }).catch((error: Error) => {
      if (this.dataChannelVersion === version) {
        this.dataChannelVersion = -1;
      }
      if (version === this.sessionVersion && !this.stopped) {
        this.fail('Wi-Fi Direct connection failed: ' + error.message);
      }
    });
  }

  private async waitForDataChannel(version: number): Promise<void> {
    const deadline = Date.now() + P2P_READY_TIMEOUT_MS;
    let lastError = '';
    let lastState = -1;
    while (Date.now() < deadline) {
      if (version !== this.sessionVersion || this.stopped) {
        return;
      }
      try {
        const info = await wifiManager.getP2pLinkedInfo();
        if (info.connectState !== lastState) {
          this.logLinkedInfo('poll', info);
          lastState = info.connectState;
        }
        if (info.connectState === wifiManager.P2pConnectState.CONNECTED) {
          try {
            await this.handleP2pConnected(info, version);
            return;
          } catch (error) {
            lastError = cleanError(error);
          }
        }
      } catch (error) {
        lastError = cleanError(error);
      }
      await delay(P2P_READY_POLL_INTERVAL_MS);
    }
    hilog.error(LOG_DOMAIN, LOG_TAG, `P2P connection timed out, role=%{public}s, lastError=%{public}s`,
      this.role, lastError);
    throw new Error(lastError.length > 0 ? lastError : 'Wi-Fi Direct connection timed out');
  }

  private async handleP2pConnected(info: wifiManager.WifiP2pLinkedInfo, version: number): Promise<void> {
    if (version !== this.sessionVersion || this.stopped) {
      return;
    }
    let ownerAddress = info.groupOwnerAddr;
    let isGroupOwner = info.isGroupOwner;
    try {
      const group = await wifiManager.getCurrentGroup();
      if (group.goIpAddress.length > 0) {
        ownerAddress = group.goIpAddress;
      }
      isGroupOwner = group.isP2pGo;
      if (isGroupOwner && group.clientDevices.length > 0) {
        this.peerName = group.clientDevices[0].deviceName;
      } else if (!isGroupOwner) {
        this.peerName = group.ownerInfo.deviceName;
      }
      hilog.info(LOG_DOMAIN, LOG_TAG,
        `Group ready, isOwner=%{public}s, ownerAddress=%{public}s, clients=%{public}d, interface=%{public}s`,
        String(isGroupOwner), ownerAddress, group.clientDevices.length, group.interface);
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, `Unable to query current group: %{public}s`, cleanError(error));
    }
    this.peerAddress = ownerAddress;
    if (isGroupOwner) {
      await this.startTcpServer();
      this.setState(WifiMigrationPhase.Connected, 'Wi-Fi Direct connected; waiting for data channel');
      return;
    }
    if (!isUsableIpv4(ownerAddress)) {
      throw new Error('Group owner address is unavailable');
    }
    await this.connectTcpClient(ownerAddress, version);
  }

  private async startTcpServer(): Promise<void> {
    if (this.server !== null) {
      return;
    }
    const server = socket.constructTCPSocketServerInstance();
    this.server = server;
    server.on('connect', (client: socket.TCPSocketConnection) => {
      this.acceptServerConnection(client);
    });
    server.on('error', (error: BusinessError) => {
      if (!this.stopped && this.server === server) {
        this.fail('Wi-Fi server error: ' + cleanError(error));
      }
    });
    try {
      await server.listen({ address: '0.0.0.0', port: WIFI_MIGRATION_PORT, family: 1 });
      if (this.stopped || this.server !== server) {
        return;
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, `TCP server listening, port=%{public}d`, WIFI_MIGRATION_PORT);
    } catch (error) {
      server.off('connect');
      server.off('error');
      this.server = null;
      throw new Error('Unable to start Wi-Fi server: ' + cleanError(error));
    }
  }

  private acceptServerConnection(client: socket.TCPSocketConnection): void {
    if (this.serverConnection !== null) {
      this.closeServerConnection(this.serverConnection);
    }
    this.serverConnection = client;
    this.receiveBuffer = new Uint8Array(0);
    client.on('message', (info: socket.SocketMessageInfo) => {
      this.consumeBytes(info.message);
    });
    client.on('close', () => {
      if (!this.stopped && this.serverConnection === client) {
        this.serverConnection = null;
        this.awaitingAck = false;
        this.clearAckTimer();
        this.setState(WifiMigrationPhase.Waiting, 'Receiving device disconnected; waiting again');
      }
    });
    client.on('error', (error: BusinessError) => {
      if (!this.stopped && this.serverConnection === client) {
        this.fail('Device connection error: ' + cleanError(error));
      }
    });
    client.getRemoteAddress().then((address: socket.NetAddress) => {
      if (this.serverConnection === client) {
        this.peerAddress = address.address;
        hilog.info(LOG_DOMAIN, LOG_TAG, `TCP connection accepted, remote=%{public}s`, address.address);
        this.emit();
      }
    }).catch(() => {});
    this.onTcpConnected();
  }

  private async connectTcpClient(address: string, version: number): Promise<void> {
    let lastError = '';
    for (let attempt = 0; attempt < 5; attempt++) {
      if (version !== this.sessionVersion || this.stopped) {
        return;
      }
      const client = socket.constructTCPSocketInstance();
      this.client = client;
      client.on('message', (info: socket.SocketMessageInfo) => {
        this.consumeBytes(info.message);
      });
      client.on('close', () => {
        if (!this.stopped && this.client === client && this.phase !== WifiMigrationPhase.Completed) {
          this.client = null;
          this.fail('The sending device disconnected');
        }
      });
      client.on('error', (error: BusinessError) => {
        if (!this.stopped && this.client === client) {
          lastError = cleanError(error);
        }
      });
      try {
        await client.connect({
          address: { address: address, port: WIFI_MIGRATION_PORT, family: 1 },
          timeout: 8000
        });
        if (version !== this.sessionVersion || this.stopped || this.client !== client) {
          await this.closeClient(client);
          return;
        }
        this.peerAddress = address;
        hilog.info(LOG_DOMAIN, LOG_TAG, `TCP client connected, remote=%{public}s, attempt=%{public}d`,
          address, attempt + 1);
        this.onTcpConnected();
        return;
      } catch (error) {
        lastError = cleanError(error);
        hilog.warn(LOG_DOMAIN, LOG_TAG, `TCP client attempt %{public}d failed: %{public}s`, attempt + 1, lastError);
        await this.closeClient(client);
        if (this.client === client) {
          this.client = null;
        }
        await delay(400);
      }
    }
    throw new Error(lastError.length > 0 ? lastError : 'TCP data channel is unavailable');
  }

  private onTcpConnected(): void {
    if (this.role === WifiMigrationRole.Server) {
      this.setState(WifiMigrationPhase.Transferring, 'Sending data and downloaded images');
      this.sendCurrentPacket().catch((error: Error) => {
        this.fail('Send failed: ' + error.message);
      });
      return;
    }
    this.setState(WifiMigrationPhase.Connected, 'Connected and ready to receive');
  }

  private logLinkedInfo(source: string, info: wifiManager.WifiP2pLinkedInfo): void {
    hilog.info(LOG_DOMAIN, LOG_TAG,
      `P2P %{public}s, state=%{public}d, isOwner=%{public}s, ownerAddress=%{public}s, role=%{public}s`,
      source, info.connectState, String(info.isGroupOwner), info.groupOwnerAddr, this.role);
  }

  private consumeBytes(buffer: ArrayBuffer): void {
    this.receiveBuffer = concatBytes(this.receiveBuffer, new Uint8Array(buffer));
    while (this.receiveBuffer.length >= 4) {
      const headerLength = readUint32(this.receiveBuffer, 0);
      if (headerLength <= 0 || headerLength > MAX_HEADER_BYTES) {
        this.fail('Received transfer header is invalid');
        this.receiveBuffer = new Uint8Array(0);
        return;
      }
      if (this.receiveBuffer.length < 4 + headerLength) {
        return;
      }
      let header: WifiTransferPacketHeader;
      try {
        const headerBytes = this.receiveBuffer.slice(4, 4 + headerLength);
        header = JSON.parse(this.decoder.decodeToString(headerBytes)) as WifiTransferPacketHeader;
      } catch (error) {
        this.fail('Received transfer header is invalid');
        this.receiveBuffer = new Uint8Array(0);
        return;
      }
      if (!validHeader(header)) {
        this.fail('Received transfer data is not compatible');
        this.receiveBuffer = new Uint8Array(0);
        return;
      }
      const packetLength = 4 + headerLength + header.payloadLength;
      if (this.receiveBuffer.length < packetLength) {
        return;
      }
      const payload = this.receiveBuffer.slice(4 + headerLength, packetLength);
      this.receiveBuffer = this.receiveBuffer.slice(packetLength);
      const version = this.sessionVersion;
      this.receiveChain = this.receiveChain.then(async () => {
        if (version === this.sessionVersion && !this.stopped) {
          await this.handlePacket(header, payload, version);
        }
      }).catch((error: Error) => {
        this.fail('Received transfer data is invalid: ' + error.message);
      });
    }
  }

  private async handlePacket(header: WifiTransferPacketHeader, payload: Uint8Array,
    version: number): Promise<void> {
    if (this.role === WifiMigrationRole.Server) {
      if (header.type !== PACKET_ACK || !this.awaitingAck || header.sequence !== this.outgoingIndex) {
        return;
      }
      this.awaitingAck = false;
      this.clearAckTimer();
      const sent = this.outgoingPackets[this.outgoingIndex];
      if (sent.header.type === PACKET_COMPLETE && sent.header.includesProgress === true &&
        payload.length > 0) {
        const merged = await this.importReadingProgressMetadata(payload);
        const nonProgressItems = Math.max(0, this.senderItemCount - this.senderProgressCount);
        this.transferredItems = Math.max(this.senderItemCount, nonProgressItems + merged);
      }
      this.transferredBytes += sent.header.payloadLength;
      if (sent.header.type === PACKET_FILE && isLastFileChunk(sent.header)) {
        this.transferredFiles++;
      }
      this.outgoingIndex++;
      this.currentPage = this.outgoingIndex;
      if (this.outgoingIndex >= this.outgoingPackets.length) {
        if (sent.header.kind !== WifiMigrationDataKind.Progress) {
          this.transferredItems = this.senderItemCount;
        }
        this.setState(WifiMigrationPhase.Completed, sent.header.kind === WifiMigrationDataKind.Progress ?
          'Reading progress synchronized' : 'Transfer completed');
      } else {
        this.emit();
        await this.sendCurrentPacket();
      }
      return;
    }

    this.phase = WifiMigrationPhase.Transferring;
    this.currentPage = header.sequence + 1;
    this.totalPages = header.totalPackets;
    this.totalBytes = header.totalBytes;
    this.totalFiles = header.totalFiles;
    this.status = header.type === PACKET_FILE ? 'Receiving downloaded images' : 'Receiving data';
    this.emit();

    if (header.type === PACKET_METADATA) {
      this.transferredItems += await this.importMetadata(payload);
    } else if (header.type === PACKET_FILE) {
      this.writeIncomingFile(header, payload);
      if (isLastFileChunk(header)) {
        this.transferredFiles++;
      }
    } else if (header.type === PACKET_COMPLETE) {
      await this.finishIncomingDownloads();
    }
    this.transferredBytes += payload.length;
    let ackPayload = new Uint8Array(0);
    if (header.type === PACKET_COMPLETE && header.includesProgress === true) {
      ackPayload = createReadingProgressMetadataBytes(this.encoder);
    }
    await this.sendAck(header.sequence, ackPayload);
    if (version !== this.sessionVersion || this.stopped) {
      return;
    }
    if (header.type === PACKET_COMPLETE) {
      this.setState(WifiMigrationPhase.Completed, header.kind === WifiMigrationDataKind.Progress ?
        'Reading progress synchronized' : 'Received and saved transfer data');
    } else {
      this.emit();
    }
  }

  private async importMetadata(payload: Uint8Array): Promise<number> {
    const metadata = JSON.parse(this.decoder.decodeToString(payload)) as WifiTransferMetadata;
    if (metadata.version !== TRANSFER_VERSION) {
      throw new Error('Unsupported transfer version');
    }
    const kinds = metadataDataKinds(metadata);
    if (kinds.length === 0) {
      throw new Error('Transferred data types are missing');
    }
    metadata.kinds = kinds;
    this.incomingMetadata = metadata;
    let count = 0;
    if (containsDataKind(kinds, WifiMigrationDataKind.Settings)) {
      const settings = metadata.settings === undefined ? [] : metadata.settings;
      const result = ehSettingsStore.importEntries(settings);
      await ehSettingsStore.save(this.context);
      applyImportedSettingEffects(this.context, result);
      count += result.imported;
    }
    if (containsDataKind(kinds, WifiMigrationDataKind.Bookmarks)) {
      const items = metadata.bookmarks === undefined ? [] : metadata.bookmarks;
      count += ehBookmarkStore.importBackupItems(items);
      await ehBookmarkStore.save(this.context);
    }
    if (containsDataKind(kinds, WifiMigrationDataKind.Favorites)) {
      const items = metadata.favorites === undefined ? [] : metadata.favorites;
      count += ehLocalFavoritesStore.importBackupItems(items);
      await ehLocalFavoritesStore.save(this.context);
    }
    if (containsDataKind(kinds, WifiMigrationDataKind.Blacklist)) {
      const items = metadata.blacklist === undefined ? [] : metadata.blacklist;
      count += ehCommentBlacklistStore.importBackupItems(items);
      await ehCommentBlacklistStore.save(this.context);
    }
    if (containsDataKind(kinds, WifiMigrationDataKind.Progress)) {
      count += await this.importReadingProgress(metadata);
    }
    if (containsDataKind(kinds, WifiMigrationDataKind.Downloads)) {
      const labels = metadata.downloadLabels === undefined ? [] : metadata.downloadLabels;
      const downloads = metadata.downloads === undefined ? [] : metadata.downloads;
      for (let i = 0; i < labels.length; i++) {
        if (ehDownloadStore.addLabel(labels[i].label)) {
          count++;
        }
      }
      const normalizedDownloads: DownloadInfo[] = [];
      for (let i = 0; i < downloads.length; i++) {
        const item = normalizeIncomingDownload(downloads[i]);
        if (item === null) {
          continue;
        }
        normalizedDownloads.push(item);
        if (ehDownloadStore.importDownload(item)) {
          count++;
        }
        const directory = ehDownloadFileStore.prepareTransferredGallery(this.context, item);
        this.incomingDirectories.set(item.gid, directory);
      }
      metadata.downloads = normalizedDownloads;
      await ehDownloadStore.save(this.context);
    }
    return count;
  }

  private async importReadingProgressMetadata(payload: Uint8Array): Promise<number> {
    const metadata = JSON.parse(this.decoder.decodeToString(payload)) as WifiTransferMetadata;
    if (metadata.version !== TRANSFER_VERSION ||
      !containsDataKind(metadataDataKinds(metadata), WifiMigrationDataKind.Progress)) {
      throw new Error('Unsupported reading progress data');
    }
    return await this.importReadingProgress(metadata);
  }

  private async importReadingProgress(metadata: WifiTransferMetadata): Promise<number> {
    await ehHistoryStore.ensureLoaded(this.context);
    const items = metadata.readingProgress === undefined ? [] : metadata.readingProgress;
    const count = ehHistoryStore.importReadingProgressBackupItems(items);
    await ehHistoryStore.save(this.context);
    return count;
  }

  private writeIncomingFile(header: WifiTransferPacketHeader, payload: Uint8Array): void {
    const gid = header.fileGid === undefined ? 0 : header.fileGid;
    const name = header.fileName === undefined ? '' : header.fileName;
    const offset = header.fileOffset === undefined ? -1 : header.fileOffset;
    const size = header.fileSize === undefined ? -1 : header.fileSize;
    if (gid <= 0 || name.length === 0 || offset < 0 || size < 0 || offset + payload.length > size) {
      throw new Error('Invalid transferred image information');
    }
    const directory = this.incomingDirectories.get(gid);
    if (directory === undefined || directory.length === 0) {
      throw new Error('Transferred gallery metadata is missing');
    }
    const data = payload.buffer.slice(payload.byteOffset, payload.byteOffset + payload.byteLength);
    const written = ehDownloadFileStore.writeTransferredImageChunk(directory, name, offset, data);
    if (written !== payload.length) {
      throw new Error('Transferred image was not fully written');
    }
  }

  private async finishIncomingDownloads(): Promise<void> {
    if (this.incomingMetadata === null ||
      !containsDataKind(metadataDataKinds(this.incomingMetadata), WifiMigrationDataKind.Downloads)) {
      return;
    }
    const downloads = this.incomingMetadata.downloads === undefined ? [] : this.incomingMetadata.downloads;
    for (let i = 0; i < downloads.length; i++) {
      const item = downloads[i];
      const directory = this.incomingDirectories.get(item.gid);
      if (directory === undefined) {
        continue;
      }
      ehDownloadFileStore.rewriteGalleryMetadataForDirectory(directory, item);
      const images = ehDownloadFileStore.listPageImages(this.context, item);
      const finished = images.length;
      const total = Math.max(finished, item.total > 0 ? item.total : item.pages);
      ehDownloadStore.setProgress(item.gid, finished, total, finished * DOWNLOAD_PAGE_PROGRESS_SCALE);
      ehDownloadStore.setStorage(item.gid, directory, ehDownloadFileStore.directorySizeByPath(directory));
      ehDownloadStore.setState(item.gid, total > 0 && finished >= total ? DownloadState.Finish : DownloadState.None);
    }
    await ehDownloadStore.save(this.context);
  }

  private async sendCurrentPacket(): Promise<void> {
    if (this.outgoingIndex >= this.outgoingPackets.length || this.awaitingAck) {
      return;
    }
    const packet = this.outgoingPackets[this.outgoingIndex];
    const payload = readPacketPayload(packet);
    await this.sendPacket(packet.header, payload);
    this.awaitingAck = true;
    this.currentPage = this.outgoingIndex + 1;
    this.phase = WifiMigrationPhase.Transferring;
    this.status = packet.header.type === PACKET_FILE ? 'Sending downloaded images' : 'Sending data';
    this.emit();
    this.clearAckTimer();
    this.ackTimer = setTimeout(() => {
      if (this.awaitingAck && !this.stopped) {
        this.awaitingAck = false;
        this.fail('The receiving device did not confirm the data in time');
      }
    }, ACK_TIMEOUT_MS);
  }

  private async sendAck(sequence: number, payload: Uint8Array): Promise<void> {
    const header: WifiTransferPacketHeader = {
      protocol: TRANSFER_PROTOCOL,
      version: TRANSFER_VERSION,
      type: PACKET_ACK,
      sequence: sequence,
      payloadLength: payload.length,
      totalPackets: this.totalPages,
      totalBytes: this.totalBytes,
      totalFiles: this.totalFiles
    };
    await this.sendPacket(header, payload);
  }

  private async sendPacket(header: WifiTransferPacketHeader, payload: Uint8Array): Promise<void> {
    const headerBytes = this.encoder.encodeInto(JSON.stringify(header));
    const prefix = new Uint8Array(4 + headerBytes.length);
    writeUint32(prefix, 0, headerBytes.length);
    prefix.set(headerBytes, 4);
    await this.sendRaw(prefix.buffer.slice(prefix.byteOffset, prefix.byteOffset + prefix.byteLength));
    if (payload.length > 0) {
      await this.sendRaw(payload.buffer.slice(payload.byteOffset, payload.byteOffset + payload.byteLength));
    }
  }

  private async sendRaw(data: ArrayBuffer): Promise<void> {
    const options: socket.TCPSendOptions = { data: data };
    try {
      if (this.serverConnection !== null) {
        await this.serverConnection.send(options);
        return;
      }
      if (this.client !== null) {
        await this.client.send(options);
        return;
      }
    } catch (error) {
      throw new Error(cleanError(error));
    }
    throw new Error('No device is connected');
  }

  private setState(phase: WifiMigrationPhase, status: string): void {
    this.phase = phase;
    this.status = status;
    this.emit();
  }

  private fail(status: string): void {
    this.phase = WifiMigrationPhase.Error;
    this.status = status;
    this.emit();
  }

  private emit(): void {
    this.observer(this.snapshot());
  }

  private clearTransferState(): void {
    this.clearAckTimer();
    this.outgoingPackets = [];
    this.outgoingIndex = 0;
    this.awaitingAck = false;
    this.receiveBuffer = new Uint8Array(0);
    this.receiveChain = Promise.resolve();
    this.incomingMetadata = null;
    this.incomingDirectories.clear();
    this.currentPage = 0;
    this.totalPages = 0;
    this.transferredItems = 0;
    this.transferredFiles = 0;
    this.totalFiles = 0;
    this.transferredBytes = 0;
    this.totalBytes = 0;
    this.senderItemCount = 0;
    this.senderProgressCount = 0;
  }

  private clearAckTimer(): void {
    if (this.ackTimer !== 0) {
      clearTimeout(this.ackTimer);
      this.ackTimer = 0;
    }
  }

  private async closeSockets(): Promise<void> {
    const serverConnection = this.serverConnection;
    const client = this.client;
    const server = this.server;
    this.serverConnection = null;
    this.client = null;
    this.server = null;
    if (serverConnection !== null) {
      await this.closeServerConnection(serverConnection);
    }
    if (client !== null) {
      await this.closeClient(client);
    }
    if (server !== null) {
      try {
        server.off('connect');
        server.off('error');
        await server.close();
      } catch (error) {
      }
    }
  }

  private async closeServerConnection(client: socket.TCPSocketConnection): Promise<void> {
    try {
      client.off('message');
      client.off('close');
      client.off('error');
      await client.close();
    } catch (error) {
    }
  }

  private async closeClient(client: socket.TCPSocket): Promise<void> {
    try {
      client.off('message');
      client.off('close');
      client.off('error');
      await client.close();
    } catch (error) {
    }
  }
}

function containsDataKind(kinds: WifiMigrationDataKind[], kind: WifiMigrationDataKind): boolean {
  for (let i = 0; i < kinds.length; i++) {
    if (kinds[i] === kind) {
      return true;
    }
  }
  return false;
}

function normalizeDataKinds(kinds: WifiMigrationDataKind[]): WifiMigrationDataKind[] {
  const ordered: WifiMigrationDataKind[] = [
    WifiMigrationDataKind.Progress,
    WifiMigrationDataKind.Settings,
    WifiMigrationDataKind.Bookmarks,
    WifiMigrationDataKind.Favorites,
    WifiMigrationDataKind.Blacklist,
    WifiMigrationDataKind.Downloads
  ];
  const normalized: WifiMigrationDataKind[] = [];
  for (let i = 0; i < ordered.length; i++) {
    if (containsDataKind(kinds, ordered[i])) {
      normalized.push(ordered[i]);
    }
  }
  return normalized;
}

function metadataDataKinds(metadata: WifiTransferMetadata): WifiMigrationDataKind[] {
  if (metadata.kinds !== undefined) {
    return normalizeDataKinds(metadata.kinds);
  }
  if (metadata.kind !== undefined) {
    return normalizeDataKinds([metadata.kind]);
  }
  return [];
}

function applyImportedSettingEffects(context: common.UIAbilityContext, result: SettingImportResult): void {
  if (result.languageChanged) {
    notifyLanguageChanged();
  }
  if (result.themeChanged) {
    notifyThemeChanged();
    applyAppChromeImmersiveMode();
  }
  if (result.titleChanged) {
    notifyGalleryTitleChanged();
  }
  readerImageCache.prune(context);
}

function createTransferPlan(context: common.UIAbilityContext, selectedKinds: WifiMigrationDataKind[],
  encoder: util.TextEncoder): TransferPlan {
  const kinds = normalizeDataKinds(selectedKinds);
  const metadata: WifiTransferMetadata = { version: TRANSFER_VERSION, kinds: kinds };
  if (kinds.length === 1) {
    metadata.kind = kinds[0];
  }
  let itemCount = 0;
  let progressCount = 0;
  const files: TransferImageFile[] = [];
  if (containsDataKind(kinds, WifiMigrationDataKind.Settings)) {
    metadata.settings = ehSettingsStore.getTransferEntries();
    itemCount += metadata.settings.length;
  }
  if (containsDataKind(kinds, WifiMigrationDataKind.Progress)) {
    metadata.readingProgress = ehHistoryStore.getReadingProgressBackupItems();
    progressCount = metadata.readingProgress.length;
    itemCount += progressCount;
  }
  if (containsDataKind(kinds, WifiMigrationDataKind.Bookmarks)) {
    metadata.bookmarks = ehBookmarkStore.getBackupItems();
    itemCount += metadata.bookmarks.length;
  }
  if (containsDataKind(kinds, WifiMigrationDataKind.Favorites)) {
    metadata.favorites = ehLocalFavoritesStore.getBackupItems();
    itemCount += metadata.favorites.length;
  }
  if (containsDataKind(kinds, WifiMigrationDataKind.Blacklist)) {
    metadata.blacklist = ehCommentBlacklistStore.getBackupItems();
    itemCount += metadata.blacklist.length;
  }
  if (containsDataKind(kinds, WifiMigrationDataKind.Downloads)) {
    metadata.downloadLabels = ehDownloadStore.getLabels();
    metadata.downloads = ehDownloadStore.getItems();
    itemCount += metadata.downloadLabels.length + metadata.downloads.length;
    for (let i = 0; i < metadata.downloads.length; i++) {
      const gallery = metadata.downloads[i];
      const images = ehDownloadFileStore.listPageImages(context, gallery);
      for (let j = 0; j < images.length; j++) {
        const size = fileSize(images[j]);
        if (size > 0) {
          const image: TransferImageFile = {
            gid: gallery.gid,
            path: images[j],
            name: pathBaseName(images[j]),
            size: size
          };
          files.push(image);
        }
      }
    }
  }
  const metadataBytes = encoder.encodeInto(JSON.stringify(metadata));
  const packets: OutgoingTransferPacket[] = [];
  packets.push({
    header: baseHeader(PACKET_METADATA, 0, metadataBytes.length),
    payload: metadataBytes
  });
  let totalBytes = metadataBytes.length;
  for (let i = 0; i < files.length; i++) {
    const file = files[i];
    totalBytes += file.size;
    for (let offset = 0; offset < file.size; offset += FILE_CHUNK_SIZE) {
      const length = Math.min(FILE_CHUNK_SIZE, file.size - offset);
      const header = baseHeader(PACKET_FILE, packets.length, length);
      header.fileGid = file.gid;
      header.fileName = file.name;
      header.fileOffset = offset;
      header.fileSize = file.size;
      packets.push({ header: header, filePath: file.path });
    }
  }
  packets.push({ header: baseHeader(PACKET_COMPLETE, packets.length, 0), payload: new Uint8Array(0) });
  for (let i = 0; i < packets.length; i++) {
    packets[i].header.totalPackets = packets.length;
    packets[i].header.totalBytes = totalBytes;
    packets[i].header.totalFiles = files.length;
    if (kinds.length === 1) {
      packets[i].header.kind = kinds[0];
    }
    packets[i].header.includesProgress = containsDataKind(kinds, WifiMigrationDataKind.Progress);
  }
  return {
    packets: packets,
    itemCount: itemCount,
    progressCount: progressCount,
    fileCount: files.length,
    totalBytes: totalBytes
  };
}

function createReadingProgressMetadataBytes(encoder: util.TextEncoder): Uint8Array {
  const metadata: WifiTransferMetadata = {
    version: TRANSFER_VERSION,
    kinds: [WifiMigrationDataKind.Progress],
    kind: WifiMigrationDataKind.Progress,
    readingProgress: ehHistoryStore.getReadingProgressBackupItems()
  };
  return encoder.encodeInto(JSON.stringify(metadata));
}

function baseHeader(type: string, sequence: number, payloadLength: number): WifiTransferPacketHeader {
  return {
    protocol: TRANSFER_PROTOCOL,
    version: TRANSFER_VERSION,
    type: type,
    sequence: sequence,
    payloadLength: payloadLength,
    totalPackets: 0,
    totalBytes: 0,
    totalFiles: 0
  };
}

function readPacketPayload(packet: OutgoingTransferPacket): Uint8Array {
  if (packet.payload !== undefined) {
    return packet.payload;
  }
  if (packet.filePath === undefined || packet.header.fileOffset === undefined) {
    return new Uint8Array(0);
  }
  const buffer = new ArrayBuffer(packet.header.payloadLength);
  let fd = -1;
  try {
    const file = fs.openSync(packet.filePath, fs.OpenMode.READ_ONLY);
    fd = file.fd;
    const count = fs.readSync(fd, buffer, {
      offset: packet.header.fileOffset,
      length: packet.header.payloadLength
    });
    if (count !== packet.header.payloadLength) {
      throw new Error('Downloaded image changed during transfer');
    }
    return new Uint8Array(buffer);
  } catch (error) {
    throw new Error('Unable to read downloaded image: ' + cleanError(error));
  } finally {
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (error) {
      }
    }
  }
}

function normalizeIncomingDownload(value: DownloadInfo): DownloadInfo | null {
  if (value === undefined || value.gid <= 0 || typeof value.token !== 'string' || value.token.length === 0) {
    return null;
  }
  value.archiveUri = '';
  value.fileSize = -1;
  value.speed = 0;
  value.remaining = 0;
  if (value.state === DownloadState.Wait || value.state === DownloadState.Downloading ||
    value.state === DownloadState.Update || value.state === DownloadState.Finish) {
    value.state = DownloadState.None;
  }
  return value;
}

function validHeader(header: WifiTransferPacketHeader): boolean {
  if (header === undefined || header.protocol !== TRANSFER_PROTOCOL || header.version !== TRANSFER_VERSION) {
    return false;
  }
  if (header.sequence < 0 || header.payloadLength < 0 || header.payloadLength > MAX_PACKET_PAYLOAD_BYTES ||
    header.totalPackets < 0 || header.totalBytes < 0 || header.totalFiles < 0) {
    return false;
  }
  return header.type === PACKET_METADATA || header.type === PACKET_FILE || header.type === PACKET_COMPLETE ||
    header.type === PACKET_ACK;
}

function isLastFileChunk(header: WifiTransferPacketHeader): boolean {
  return header.type === PACKET_FILE && header.fileOffset !== undefined && header.fileSize !== undefined &&
    header.fileOffset + header.payloadLength >= header.fileSize;
}

function clonePeers(peers: WifiMigrationPeer[]): WifiMigrationPeer[] {
  const cloned: WifiMigrationPeer[] = [];
  for (let i = 0; i < peers.length; i++) {
    cloned.push({
      name: peers[i].name,
      address: peers[i].address,
      addressType: peers[i].addressType,
      status: peers[i].status
    });
  }
  return cloned;
}

function concatBytes(left: Uint8Array, right: Uint8Array): Uint8Array {
  const result = new Uint8Array(left.length + right.length);
  result.set(left, 0);
  result.set(right, left.length);
  return result;
}

function readUint32(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] * 0x1000000) + (bytes[offset + 1] << 16) + (bytes[offset + 2] << 8) +
    bytes[offset + 3];
}

function writeUint32(bytes: Uint8Array, offset: number, value: number): void {
  bytes[offset] = (value >>> 24) & 0xff;
  bytes[offset + 1] = (value >>> 16) & 0xff;
  bytes[offset + 2] = (value >>> 8) & 0xff;
  bytes[offset + 3] = value & 0xff;
}

function fileSize(path: string): number {
  try {
    return fs.statSync(path).size;
  } catch (error) {
    return 0;
  }
}

function pathBaseName(path: string): string {
  const slash = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  return slash >= 0 ? path.substring(slash + 1) : path;
}

function isUsableIpv4(address: string): boolean {
  const parts = address.trim().split('.');
  if (parts.length !== 4 || address === '0.0.0.0' || address.startsWith('127.')) {
    return false;
  }
  for (let i = 0; i < parts.length; i++) {
    if (parts[i].length === 0 || !/^\d+$/.test(parts[i])) {
      return false;
    }
    const value = Number.parseInt(parts[i]);
    if (value < 0 || value > 255) {
      return false;
    }
  }
  return true;
}

function delay(milliseconds: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, milliseconds);
  });
}

function isWifiReady(): boolean {
  try {
    return wifiManager.isWifiActive();
  } catch (error) {
    return false;
  }
}

function cleanError(error: Object): string {
  if (error instanceof Error && error.message.length > 0) {
    return error.message;
  }
  return String(error);
}
