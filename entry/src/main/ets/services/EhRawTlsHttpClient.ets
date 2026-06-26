import { util } from '@kit.ArkTS';
import { socket } from '@kit.NetworkKit';
import { EhRequestPlan } from './EhNetworkConfig';

export interface RawTlsHttpResponse {
  statusCode: number;
  body: string;
  cookies: string;
}

export interface RawHttpHeaderEntry {
  name: string;
  value: string;
}

export interface RawTlsHttpRequestOptions {
  method: string;
  url: string;
  plan: EhRequestPlan;
  header: RawHttpHeaderEntry[];
  body?: string;
  timeoutMs: number;
}

interface RawUrlPath {
  path: string;
}

const CRLF: string = '\r\n';

export async function requestRawTlsText(options: RawTlsHttpRequestOptions): Promise<RawTlsHttpResponse> {
  const urlParts = parseUrlPath(options.url);
  if (urlParts === null || options.plan.tlsFrontHost.length === 0) {
    throw new Error('Raw TLS fronting is not available for this URL');
  }

  const client = socket.constructTLSSocketInstance();
  try {
    const responseBytes = await requestWithSocket(client, options, urlParts.path);
    return parseRawHttpResponse(responseBytes);
  } finally {
    try {
      await client.close();
    } catch (error) {
    }
  }
}

function requestWithSocket(client: socket.TLSSocket, options: RawTlsHttpRequestOptions,
  path: string): Promise<Uint8Array> {
  return new Promise<Uint8Array>((resolve: (value: Uint8Array) => void, reject: (reason: Error) => void) => {
    const chunks: Uint8Array[] = [];
    let finished = false;
    const timer = setTimeout(() => {
      finishError(new Error('Network request timed out after ' + Math.floor(options.timeoutMs / 1000).toString() + 's'));
    }, options.timeoutMs);

    const finishOk = (): void => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimeout(timer);
      resolve(concatBytes(chunks));
    };

    const finishError = (error: Error): void => {
      if (finished) {
        return;
      }
      finished = true;
      clearTimeout(timer);
      reject(error);
    };

    client.on('message', (info: socket.SocketMessageInfo) => {
      if (finished || info.message.byteLength <= 0) {
        return;
      }
      chunks.push(new Uint8Array(info.message));
    });
    client.on('close', () => {
      finishOk();
    });
    client.on('error', (error: Error) => {
      finishError(error);
    });

    client.connect({
      address: {
        address: options.plan.tlsFrontHost,
        port: 443
      },
      secureOptions: {},
      ALPNProtocols: ['http/1.1'],
      skipRemoteValidation: true,
      timeout: options.timeoutMs
    }).then(async () => {
      try {
        await client.setExtraOptions({ TCPNoDelay: true });
      } catch (error) {
      }
      return client.send(buildRawHttpRequest(options, path));
    }).catch((error: Error) => {
      finishError(error);
    });
  });
}

function buildRawHttpRequest(options: RawTlsHttpRequestOptions, path: string): string {
  const lines: string[] = [options.method + ' ' + path + ' HTTP/1.1'];
  for (let i = 0; i < options.header.length; i++) {
    const normalized = options.header[i].name.toLowerCase();
    if (normalized === 'connection' || normalized === 'content-length') {
      continue;
    }
    if (options.header[i].value.length > 0) {
      lines.push(options.header[i].name + ': ' + options.header[i].value);
    }
  }
  lines.push('Connection: close');
  if (options.body !== undefined) {
    lines.push('Content-Length: ' + utf8ByteLength(options.body).toString());
  }
  lines.push('');
  lines.push(options.body === undefined ? '' : options.body);
  return lines.join(CRLF);
}

function parseRawHttpResponse(bytes: Uint8Array): RawTlsHttpResponse {
  const headerEnd = indexOfHeaderEnd(bytes);
  if (headerEnd < 0) {
    throw new Error('Invalid HTTP response');
  }
  const headerText = decodeUtf8(bytes.subarray(0, headerEnd));
  const headerLines = headerText.split(CRLF);
  const statusCode = parseStatusCode(headerLines.length > 0 ? headerLines[0] : '');
  const headers = parseHeaders(headerLines);
  const bodyStart = headerEnd + 4;
  let bodyBytes = bytes.subarray(bodyStart);
  if (headerValue(headers, 'transfer-encoding').toLowerCase().indexOf('chunked') >= 0) {
    bodyBytes = decodeChunkedBody(bodyBytes);
  }
  return {
    statusCode: statusCode,
    body: decodeUtf8(bodyBytes),
    cookies: collectSetCookie(headers)
  };
}

function parseHeaders(lines: string[]): Map<string, string[]> {
  const headers = new Map<string, string[]>();
  for (let i = 1; i < lines.length; i++) {
    const index = lines[i].indexOf(':');
    if (index <= 0) {
      continue;
    }
    const name = lines[i].substring(0, index).trim().toLowerCase();
    const value = lines[i].substring(index + 1).trim();
    const values = headers.get(name);
    if (values === undefined) {
      headers.set(name, [value]);
    } else {
      values.push(value);
    }
  }
  return headers;
}

function collectSetCookie(headers: Map<string, string[]>): string {
  const values = headers.get('set-cookie');
  return values === undefined ? '' : values.join('\n');
}

function headerValue(headers: Map<string, string[]>, name: string): string {
  const values = headers.get(name.toLowerCase());
  return values === undefined || values.length === 0 ? '' : values.join(', ');
}

function parseStatusCode(statusLine: string): number {
  const match = /^HTTP\/\d(?:\.\d)?\s+(\d{3})/i.exec(statusLine);
  return match === null ? 0 : Number.parseInt(match[1]);
}

function decodeChunkedBody(bytes: Uint8Array): Uint8Array {
  const chunks: Uint8Array[] = [];
  let offset = 0;
  while (offset < bytes.length) {
    const lineEnd = indexOfCrlf(bytes, offset);
    if (lineEnd < 0) {
      break;
    }
    const line = decodeAscii(bytes.subarray(offset, lineEnd)).split(';')[0].trim();
    const size = Number.parseInt(line, 16);
    if (Number.isNaN(size) || size < 0) {
      break;
    }
    offset = lineEnd + 2;
    if (size === 0) {
      break;
    }
    if (offset + size > bytes.length) {
      break;
    }
    chunks.push(bytes.subarray(offset, offset + size));
    offset += size + 2;
  }
  return concatBytes(chunks);
}

function concatBytes(chunks: Uint8Array[]): Uint8Array {
  let length = 0;
  for (let i = 0; i < chunks.length; i++) {
    length += chunks[i].byteLength;
  }
  const result = new Uint8Array(length);
  let offset = 0;
  for (let i = 0; i < chunks.length; i++) {
    result.set(chunks[i], offset);
    offset += chunks[i].byteLength;
  }
  return result;
}

function indexOfHeaderEnd(bytes: Uint8Array): number {
  for (let i = 0; i + 3 < bytes.length; i++) {
    if (bytes[i] === 13 && bytes[i + 1] === 10 && bytes[i + 2] === 13 && bytes[i + 3] === 10) {
      return i;
    }
  }
  return -1;
}

function indexOfCrlf(bytes: Uint8Array, start: number): number {
  for (let i = start; i + 1 < bytes.length; i++) {
    if (bytes[i] === 13 && bytes[i + 1] === 10) {
      return i;
    }
  }
  return -1;
}

function decodeUtf8(bytes: Uint8Array): string {
  const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
  return decoder.decodeToString(bytes, { stream: false });
}

function decodeAscii(bytes: Uint8Array): string {
  let text = '';
  for (let i = 0; i < bytes.length; i++) {
    text += String.fromCharCode(bytes[i]);
  }
  return text;
}

function utf8ByteLength(text: string): number {
  return util.TextEncoder.create('utf-8').encodeInto(text).byteLength;
}

function parseUrlPath(url: string): RawUrlPath | null {
  const match = /^https:\/\/[^\/?#]+([^?#]*)(\?[^#]*)?/i.exec(url);
  if (match === null) {
    return null;
  }
  const path = match[1].length === 0 ? '/' : match[1];
  const query = match[2] === undefined ? '' : match[2];
  return { path: path + query };
}
