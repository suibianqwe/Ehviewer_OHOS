import { ArchiveOption, ArchiverInfo, ArchiverOption, HathArchiveList } from '../model/GalleryModels';

const HATH_FORM_PATTERN: RegExp = /<form[^>]+id=["']hathdl_form["'][^>]+action=["'][^"']*(?:[?&]or=([^&"']+))?[^"']*["'][^>]*>/i;
const HATH_OPTION_PATTERN: RegExp = /<a[^>]+onclick=["']return\s+do_hathdl\(["']([0-9]+|org)["']\)["'][^>]*>([\s\S]*?)<\/a>/gi;
const FORM_PATTERN: RegExp = /<form[^>]+action=["']([^"']+)["'][^>]*>([\s\S]*?)<\/form>/gi;
const INPUT_PATTERN: RegExp = /<input[^>]+>/gi;
const DOWNLOAD_URL_PATTERN: RegExp = /href=["']([^"']+)["'][^>]*>\s*Click Here To Start Downloading/i;
const REDIRECT_PATTERN: RegExp = /document\.location\s*=\s*["']([^"']+)["']/i;

interface HiddenFields {
  dlType: string;
  dlCheck: string;
}

export function parseHathArchiveList(body: string): HathArchiveList {
  HATH_OPTION_PATTERN.lastIndex = 0;
  const formMatch = HATH_FORM_PATTERN.exec(body);
  const formParamOr = formMatch === null || formMatch[1] === undefined ? '' : decodeHtml(formMatch[1]);
  const options: ArchiveOption[] = [];
  let match: RegExpExecArray | null = HATH_OPTION_PATTERN.exec(body);
  while (match !== null) {
    options.push({
      value: cleanText(match[1]),
      label: cleanText(match[2])
    });
    match = HATH_OPTION_PATTERN.exec(body);
  }
  return { formParamOr: formParamOr, options: options };
}

export function parseArchiverInfo(body: string): ArchiverInfo {
  FORM_PATTERN.lastIndex = 0;
  const options: ArchiverOption[] = [];
  let funds = cleanText(firstMatch(body, /You currently have[^<]*/i));
  if (funds.length === 0) {
    funds = cleanText(firstMatch(body, /Available Funds[\s\S]*?(?:GP|Credits|Hath|$)/i));
  }

  let match: RegExpExecArray | null = FORM_PATTERN.exec(body);
  while (match !== null) {
    const formHtml = match[0];
    const beforeForm = body.substring(Math.max(0, match.index - 260), match.index);
    const afterForm = body.substring(match.index + formHtml.length,
      Math.min(body.length, match.index + formHtml.length + 260));
    const nearbyHtml = beforeForm + formHtml + afterForm;
    const text = cleanText(nearbyHtml);
    const hidden = parseHiddenFields(formHtml);
    const submit = parseInputValue(formHtml, 'value');
    const isOriginal = /Original/i.test(text) || /Original/i.test(submit) || hidden.dlType === 'org';
    const isResampled = /Resample|Resampled/i.test(text) || /Resample|Resampled/i.test(submit) || hidden.dlType === 'res';
    if (isOriginal || isResampled) {
      options.push({
        kind: isOriginal ? 'original' : 'resampled',
        label: isOriginal ? 'Original' : 'Resampled',
        cost: parseLastCost(cleanText(beforeForm)),
        size: parseSize(cleanText(afterForm)),
        url: decodeHtml(match[1]),
        dlType: hidden.dlType.length > 0 ? hidden.dlType : (isOriginal ? 'org' : 'res'),
        dlCheck: hidden.dlCheck
      });
    }
    match = FORM_PATTERN.exec(body);
  }
  return { funds: funds, options: options };
}

export function parseArchiverContinueUrl(body: string): string {
  const match = REDIRECT_PATTERN.exec(body);
  return match === null ? '' : decodeHtml(match[1]);
}

export function parseArchiverDownloadUrl(body: string): string {
  const match = DOWNLOAD_URL_PATTERN.exec(body);
  return match === null ? '' : decodeHtml(match[1]);
}

function parseHiddenFields(formHtml: string): HiddenFields {
  return {
    dlType: parseInputValueByName(formHtml, 'dltype'),
    dlCheck: parseInputValueByName(formHtml, 'dlcheck')
  };
}

function parseInputValueByName(formHtml: string, name: string): string {
  INPUT_PATTERN.lastIndex = 0;
  let match: RegExpExecArray | null = INPUT_PATTERN.exec(formHtml);
  while (match !== null) {
    const input = match[0];
    if (attr(input, 'name') === name) {
      return decodeHtml(attr(input, 'value'));
    }
    match = INPUT_PATTERN.exec(formHtml);
  }
  return '';
}

function parseInputValue(formHtml: string, attrName: string): string {
  INPUT_PATTERN.lastIndex = 0;
  let match: RegExpExecArray | null = INPUT_PATTERN.exec(formHtml);
  while (match !== null) {
    const value = attr(match[0], attrName);
    if (value.length > 0) {
      return decodeHtml(value);
    }
    match = INPUT_PATTERN.exec(formHtml);
  }
  return '';
}

function attr(html: string, name: string): string {
  const pattern = new RegExp(name + "\\s*=\\s*([\"'])([\\s\\S]*?)\\1", 'i');
  const match = pattern.exec(html);
  return match === null ? '' : match[2];
}

function parseCost(text: string): string {
  const match = /Download Cost\s*:?\s*([\s\S]*?)(?:Download|Estimated Size|$)/i.exec(text);
  return match === null ? '' : cleanText(match[1]);
}

function parseLastCost(text: string): string {
  const pattern = /Download Cost\s*:?\s*([\d,]+\s*(?:GP|Credits|Hath))/gi;
  let result = '';
  let match: RegExpExecArray | null = pattern.exec(text);
  while (match !== null) {
    result = cleanText(match[1]);
    match = pattern.exec(text);
  }
  return result.length > 0 ? result : parseCost(text);
}

function parseSize(text: string): string {
  const match = /Estimated Size\s*:?\s*([\d.]+\s*(?:B|KB|MB|GB|KiB|MiB|GiB))/i.exec(text);
  return match === null ? '' : cleanText(match[1]);
}

function firstMatch(value: string, pattern: RegExp): string {
  const match = pattern.exec(value);
  return match === null ? '' : match[0];
}

function cleanText(value: string): string {
  return decodeHtml(value.replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
}

function decodeHtml(value: string): string {
  return value
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, '\'')
    .replace(/&nbsp;/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}
