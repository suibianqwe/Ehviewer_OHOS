import { decodeHtmlEntities } from '../shared/HtmlEntitySupport';

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

interface EhDailyCheckInWebSnapshot {
  paragraphs: string[];
  responseKind: string;
  bodyLength: number;
}

export function buildDailyCheckInInspectionScript(): string {
  return "(() => {" +
    "const pane=document.getElementById('eventpane');" +
    "const paragraphs=pane?Array.from(pane.querySelectorAll('p')).map((p)=>" +
    "(p.innerText||p.textContent||'').replace(/\\s+/g,' ').trim()).filter((p)=>p.length>0):[];" +
    "const bodyText=(document.body&&document.body.innerText)||'';" +
    "const html=(document.documentElement&&document.documentElement.innerHTML)||'';" +
    "let kind='unexpected-page';" +
    "if(pane){kind='event-pane';}" +
    "else if(/cf-chl-|challenge-platform|Just a moment|Checking your browser|cf-ray/i.test(html)){" +
    "kind='site-verification';}" +
    "else if(/Sign in with an E-Hentai forum account|act=Login/i.test(bodyText)||" +
    "document.querySelector('[name=UserName]')){kind='signed-out';}" +
    "else if(document.getElementById('newsouter')||/E-Hentai/i.test(document.title)){" +
    "kind='news-without-event';}" +
    "return JSON.stringify({paragraphs:paragraphs,responseKind:kind,bodyLength:bodyText.length});" +
    "})()";
}

export function parseEhDailyCheckInWebResult(raw: string): EhDailyCheckInResult {
  try {
    let json = raw.trim();
    if (json.startsWith('"')) {
      json = JSON.parse(json) as string;
    }
    const snapshot = JSON.parse(json) as EhDailyCheckInWebSnapshot;
    const paragraphs = Array.isArray(snapshot.paragraphs) ? snapshot.paragraphs : [];
    if (paragraphs.length === 3) {
      return {
        ok: true,
        statusCode: 200,
        message: '',
        event: { message: paragraphs.join('\n\n') },
        responseKind: 'daily-event',
        bodyLength: normalizeBodyLength(snapshot.bodyLength),
        eventParagraphCount: paragraphs.length
      };
    }
    return {
      ok: true,
      statusCode: 200,
      message: '',
      event: null,
      responseKind: snapshot.responseKind === 'event-pane' ? 'event-pane-unexpected' :
        normalizeResponseKind(snapshot.responseKind),
      bodyLength: normalizeBodyLength(snapshot.bodyLength),
      eventParagraphCount: paragraphs.length
    };
  } catch (error) {
    return dailyCheckInFailureResult('Invalid background Web result: ' + String(error), 'inspection-failed');
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

export function dailyCheckInFailureResult(message: string,
  responseKind: string = 'web-failed'): EhDailyCheckInResult {
  return {
    ok: false,
    statusCode: 0,
    message: message,
    event: null,
    responseKind: responseKind,
    bodyLength: 0,
    eventParagraphCount: 0
  };
}

function normalizeBodyLength(value: number): number {
  return Number.isFinite(value) && value >= 0 ? Math.floor(value) : 0;
}

function normalizeResponseKind(value: string): string {
  if (value === 'site-verification' || value === 'signed-out' ||
    value === 'news-without-event' || value === 'unexpected-page') {
    return value;
  }
  return 'unexpected-page';
}
