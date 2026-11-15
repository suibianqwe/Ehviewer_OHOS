import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

export async function readDiagnosticFile(path: string, limit: number, tail: boolean = false): Promise<string> {
  try {
    const stat = await fs.stat(path);
    if (stat.size === 0) return '';
    const offset = tail ? Math.max(0, stat.size - limit) : 0;
    let text = await fs.readText(path, { offset: offset,
      length: Math.min(stat.size, limit) });
    if (offset > 0) {
      // A byte offset can land in a UTF-8 character or a partial record.
      const newline = text.indexOf('\n');
      text = newline < 0 ? '' : text.substring(newline + 1);
    }
    return stat.size > limit ? (tail ? '[Earlier content omitted]\n' + text : text + '\n[Remaining content omitted]') : text;
  } catch (error) {
    if ((error as BusinessError).code === 13900002) return '';
    throw new Error(String(error));
  }
}

export async function writeDiagnosticFile(path: string, text: string, append: boolean = false): Promise<void> {
  const mode = fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | (append ? fs.OpenMode.APPEND : fs.OpenMode.TRUNC);
  const file = await fs.open(path, mode);
  try {
    // Encode bounded chunks and honor partial writes, including multibyte text.
    for (let start = 0; start < text.length;) {
      let end = Math.min(text.length, start + 32768);
      if (end < text.length && /[\uD800-\uDBFF]/.test(text.charAt(end - 1))) end--;
      const bytes = new util.TextEncoder().encodeInto(text.substring(start, end));
      let written = 0;
      while (written < bytes.byteLength) {
        const count = await fs.write(file.fd, bytes.buffer.slice(written));
        if (count <= 0) throw new Error('Log file write made no progress');
        written += count;
      }
      start = end;
    }
  } finally {
    await fs.close(file);
  }
}

// Appends, reads and clears share a queue so export includes queued writes and
// clearing cannot resurrect an in-flight append.
export class DiagnosticLogFile {
  private pending: Promise<void> = Promise.resolve();
  private failure: string = '';
  private name: string;
  private limit: number;

  constructor(name: string, limit: number) {
    this.name = name;
    this.limit = limit;
  }

  append(directory: string, text: string): void {
    this.pending = this.pending.then(async () => {
      const path = directory + '/' + this.name;
      let size = 0;
      try { size = (await fs.stat(path)).size; } catch (error) {
        if ((error as BusinessError).code !== 13900002) throw new Error(String(error));
      }
      const content = text.length > this.limit / 4 ? '[Oversized entry truncated]\n' + text.slice(-this.limit / 4) : text;
      if (size + content.length * 4 > this.limit) {
        const retained = await readDiagnosticFile(path, Math.floor(this.limit / 4), true);
        const temporary = path + '.tmp';
        await writeDiagnosticFile(temporary, retained + content);
        await fs.rename(temporary, path);
      } else {
        await writeDiagnosticFile(path, content, true);
      }
      this.failure = '';
    }).catch((error: Error) => { this.failure = String(error); });
  }

  read(directory: string): Promise<string> {
    const result = this.pending.then(async () => {
      const text = await readDiagnosticFile(directory + '/' + this.name, this.limit, true);
      return this.failure.length > 0 ? text + '\n[Log write failed] ' + this.failure : text;
    });
    this.pending = result.then(() => {}).catch(() => {});
    return result;
  }

  replace(directory: string, text: string): Promise<void> {
    const result = this.pending.then(async () => {
      const path = directory + '/' + this.name;
      const content = text.length > this.limit / 4 ? '[Oversized snapshot truncated]\n' + text.slice(-this.limit / 4) : text;
      await writeDiagnosticFile(path + '.tmp', content);
      await fs.rename(path + '.tmp', path);
      this.failure = '';
    });
    this.pending = result.catch((error: Error) => { this.failure = String(error); });
    return result;
  }

  clear(directory: string): Promise<void> {
    const result = this.pending.then(async () => {
      try { await fs.unlink(directory + '/' + this.name); } catch (error) {
        if ((error as BusinessError).code !== 13900002) throw new Error(String(error));
      }
      this.failure = '';
    });
    this.pending = result.catch((error: Error) => { this.failure = String(error); });
    return result;
  }
}
