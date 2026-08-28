import { GallerySite } from '../model/GalleryModels';
import { decodeHtmlEntities } from '../shared/HtmlEntitySupport';
import { EhHttpClient } from './EhHttpClient';
import { EhUrl } from './EhUrl';

export const DAILY_CHECK_IN_FOREGROUND_REVISION_KEY: string = 'dailyCheckInForegroundRevision';

export interface EhDailyCheckInEvent {
  message: string;
}

export interface EhDailyCheckInResult {
  ok: boolean;
  statusCode: number;
  message: string;
  event: EhDailyCheckInEvent | null;
  responseKind: string;
  bodyLength: number;
  eventParagraphCount: number;
}

interface EhDailyCheckInInspection {
  event: EhDailyCheckInEvent | null;
  responseKind: string;
  eventParagraphCount: number;
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
      const inspection = inspectEhDailyCheckInResponse(response.body);
      return {
        ok: true,
        statusCode: response.statusCode,
        message: '',
        event: inspection.event,
        responseKind: inspection.responseKind,
        bodyLength: response.body.length,
        eventParagraphCount: inspection.eventParagraphCount
      };
    } catch (error) {
      return failureResult(0, String(error));
    }
  }
}

export function parseEhDailyCheckInEvent(body: string): EhDailyCheckInEvent | null {
  return inspectEhDailyCheckInResponse(body).event;
}

function inspectEhDailyCheckInResponse(body: string): EhDailyCheckInInspection {
  const paneMatch = /<div\b[^>]*\bid\s*=\s*["']eventpane["'][^>]*>([\s\S]*?)<\/div>/i.exec(body);
  if (paneMatch === null) {
    return {
      event: null,
      responseKind: classifyResponseWithoutEvent(body),
      eventParagraphCount: 0
    };
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
    return {
      event: null,
      responseKind: 'event-pane-unexpected',
      eventParagraphCount: paragraphs.length
    };
  }
  return {
    event: { message: paragraphs.join('\n\n') },
    responseKind: 'daily-event',
    eventParagraphCount: paragraphs.length
  };
}

function classifyResponseWithoutEvent(body: string): string {
  if (/cf-chl-|challenge-platform|<title[^>]*>\s*Just a moment|Checking your browser|cf-ray/i.test(body)) {
    return 'site-verification';
  }
  if (/Sign in with an E-Hentai forum account|name\s*=\s*["']UserName["']|act=Login/i.test(body)) {
    return 'signed-out';
  }
  if (/\bid\s*=\s*["']newsouter["']|<title[^>]*>[^<]*E-Hentai/i.test(body)) {
    return 'news-without-event';
  }
  return 'unexpected-page';
}

function cleanEventText(value: string): string {
  return decodeHtmlEntities(value.replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
}

function failureResult(statusCode: number, message: string): EhDailyCheckInResult {
  return {
    ok: false,
    statusCode: statusCode,
    message: message,
    event: null,
    responseKind: 'request-failed',
    bodyLength: 0,
    eventParagraphCount: 0
  };
}

export const ehDailyCheckInService: EhDailyCheckInService = new EhDailyCheckInService();
