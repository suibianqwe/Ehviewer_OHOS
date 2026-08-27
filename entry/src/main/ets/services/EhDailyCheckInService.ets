import { GallerySite } from '../model/GalleryModels';
import { decodeHtmlEntities } from '../shared/HtmlEntitySupport';
import { EhHttpClient } from './EhHttpClient';
import { EhUrl } from './EhUrl';

export interface EhDailyCheckInEvent {
  message: string;
}

export interface EhDailyCheckInResult {
  ok: boolean;
  statusCode: number;
  message: string;
  event: EhDailyCheckInEvent | null;
}

class EhDailyCheckInService {
  private client: EhHttpClient = new EhHttpClient();
  private pending: Promise<EhDailyCheckInResult> | null = null;

  async check(): Promise<EhDailyCheckInResult> {
    if (this.pending !== null) {
      return this.pending;
    }
    const pending = this.requestCheckIn();
    this.pending = pending;
    try {
      return await pending;
    } finally {
      if (this.pending === pending) {
        this.pending = null;
      }
    }
  }

  private async requestCheckIn(): Promise<EhDailyCheckInResult> {
    const url = EhUrl.getNewsUrl();
    try {
      const response = await this.client.getText(url, EhUrl.getReferer(GallerySite.E), 0, {
        includeUConfig: false,
        browserCompatibility: true
      });
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return failureResult(response.statusCode, 'HTTP ' + response.statusCode.toString());
      }
      return {
        ok: true,
        statusCode: response.statusCode,
        message: '',
        event: parseEhDailyCheckInEvent(response.body)
      };
    } catch (error) {
      return failureResult(0, String(error));
    }
  }
}

export function parseEhDailyCheckInEvent(body: string): EhDailyCheckInEvent | null {
  const paneMatch = /<div\b[^>]*\bid\s*=\s*["']eventpane["'][^>]*>([\s\S]*?)<\/div>/i.exec(body);
  if (paneMatch === null) {
    return null;
  }

  const paragraphs: string[] = [];
  const paragraphPattern = /<p\b[^>]*>([\s\S]*?)<\/p>/gi;
  let paragraphMatch: RegExpExecArray | null = paragraphPattern.exec(paneMatch[1]);
  while (paragraphMatch !== null) {
    const text = cleanEventText(paragraphMatch[1]);
    if (text.length > 0) {
      paragraphs.push(text);
    }
    paragraphMatch = paragraphPattern.exec(paneMatch[1]);
  }

  // Match the Android implementation: ordinary news pages must not produce a dialog.
  if (paragraphs.length !== 3) {
    return null;
  }
  return { message: paragraphs.join('\n\n') };
}

function cleanEventText(value: string): string {
  return decodeHtmlEntities(value.replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
}

function failureResult(statusCode: number, message: string): EhDailyCheckInResult {
  return { ok: false, statusCode: statusCode, message: message, event: null };
}

export const ehDailyCheckInService: EhDailyCheckInService = new EhDailyCheckInService();
