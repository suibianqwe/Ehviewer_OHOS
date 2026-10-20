import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ReaderImageDemand } from './ReaderImageRequestControl';

export interface ReaderTransferResult {
  statusCode: number;
  header: Object;
}

// Keep the existing transport for fronting and custom proxies, rather than lose
// their API 26 features. Stop obsolete transfers at the next body write instead
// of removing an active handle with Session.cancel during socket dispatch.
export function supportsCancellableReaderTransfer(fronted: boolean, options: http.HttpRequestOptions): boolean {
  if (!canIUse('SystemCapability.Collaboration.RemoteCommunication') ||
    (deviceInfo.apiAvailable('26.0.0') && options.usingSocks5Proxy !== undefined)) {
    return false;
  }
  return !fronted &&
    (options.usingProxy === undefined || typeof options.usingProxy === 'boolean');
}

class ReaderTransferSink implements rcp.WriteFile {
  oversized: boolean = false;
  stoppedOnWrite: boolean = false;
  private cancelled: boolean = false;
  private received: number = 0;
  private pending: Promise<number> = Promise.resolve(0);
  private file: fs.File;
  private demand: ReaderImageDemand;
  private maxBytes: number;

  constructor(file: fs.File, demand: ReaderImageDemand, maxBytes: number) {
    this.file = file;
    this.demand = demand;
    this.maxBytes = maxBytes;
  }

  cancel(): void {
    this.cancelled = true;
  }

  write(buffer: ArrayBuffer): Promise<number> {
    // Serialize writes, including platforms that enqueue more than one callback.
    this.pending = this.pending.then(() => this.writeChunk(buffer));
    return this.pending;
  }

  drain(): Promise<number> {
    return this.pending.catch(() => 0);
  }

  private async writeChunk(buffer: ArrayBuffer): Promise<number> {
    if (this.cancelled || this.demand.cancelled) {
      this.stoppedOnWrite = true;
      // A zero-byte short write is retried on some builds; rejection ends the
      // transfer with WRITE_ERROR from its own receive path, not Session.cancel.
      throw new Error('Reader image request cancelled');
    }
    if (this.received + buffer.byteLength > this.maxBytes) {
      this.oversized = true;
      throw new Error('Image response exceeds size limit');
    }
    let written = 0;
    while (written < buffer.byteLength) {
      if (this.cancelled || this.demand.cancelled) {
        this.stoppedOnWrite = true;
        throw new Error('Reader image request cancelled');
      }
      const count = await fs.write(this.file.fd, written === 0 ? buffer : buffer.slice(written));
      if (count <= 0) {
        throw new Error('Image file write failed');
      }
      written += count;
    }
    this.received += written;
    return written;
  }
}

class ReaderCancellableImageTransfer {
  private session: rcp.Session | undefined = undefined;

  async download(url: string, options: http.HttpRequestOptions, temporary: string, demand: ReaderImageDemand,
    maxBytes: number, onProgress: (received: number, total: number) => void): Promise<ReaderTransferResult> {
    if (demand.cancelled) {
      throw new Error('Reader image request cancelled');
    }
    if (this.session === undefined) {
      this.session = rcp.createSession();
    }
    const session = this.session;
    const request = new rcp.Request(url, 'GET', options.header as Record<string, string>);
    let file: fs.File | undefined = undefined;
    let sink: ReaderTransferSink | undefined = undefined;
    const transfer: rcp.TransferConfiguration = {
      timeout: { connectMs: options.connectTimeout, transferMs: options.readTimeout }
    };
    if (deviceInfo.apiAvailable('26.0.0') && options.reuseConnections === false) {
      transfer.connectionReusePolicy = 'forbidden';
    }
    request.configuration = {
      transfer: transfer,
      proxy: options.usingProxy === false ? 'no-proxy' : 'system',
      tracing: {
        httpEventsHandler: {
          onDownloadProgress: (total: number, received: number) => {
            if (demand.cancelled) {
              return;
            }
            onProgress(received, total);
          }
        }
      }
    };
    if (options.dnsOverHttps !== undefined) {
      request.configuration.dns = { dnsOverHttps: { url: options.dnsOverHttps } };
    }
    const abort = (): void => {
      sink?.cancel();
    };
    demand.abort = abort;
    try {
      file = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      if (demand.cancelled) {
        throw new Error('Reader image request cancelled');
      }
      sink = new ReaderTransferSink(file, demand, maxBytes);
      request.destination = { kind: 'file', file: sink };
      console.info('ReaderImageQueue: start page=' + (demand.index + 1).toString() +
        ' priority=' + demand.priority.toString() + ' transport=rcp-stream');
      const response = await session.fetch(request);
      if (demand.cancelled) {
        throw new Error('Reader image request cancelled');
      }
      if (sink.oversized) {
        throw new Error('Image response exceeds size limit');
      }
      return { statusCode: response.statusCode, header: response.headers };
    } catch (error) {
      const code = (error as BusinessError).code;
      if (demand.cancelled) {
        console.info('ReaderImageQueue: cancelled page=' + (demand.index + 1).toString() +
          ' code=' + String(code) + ' bodyStopped=' + (sink?.stoppedOnWrite === true).toString());
        throw new Error('Reader image request cancelled');
      }
      if (sink?.oversized) {
        throw new Error('Image response exceeds size limit');
      }
      // Preserve the retry/DoH fallback categories used by ReaderImageCache.
      if (code === 1007900028) {
        throw new Error('Image network timeout');
      }
      if (code === 1007900006) {
        throw new Error('Image DNS lookup failed');
      }
      throw new Error(String(error));
    } finally {
      if (demand.abort === abort) {
        demand.abort = () => {};
      }
      // Never close/unlink a destination while an asynchronous write still owns it.
      await sink?.drain();
      if (file !== undefined) {
        await fs.close(file);
      }
    }
  }
}

export const readerCancellableImageTransfer: ReaderCancellableImageTransfer = new ReaderCancellableImageTransfer();
