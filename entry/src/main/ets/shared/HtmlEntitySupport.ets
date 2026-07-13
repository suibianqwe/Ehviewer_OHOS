export function decodeHtmlEntities(value: string): string {
  let decoded = value;
  for (let i = 0; i < 3; i++) {
    const next = decodeHtmlEntitiesOnce(decoded);
    if (next === decoded) {
      return decoded;
    }
    decoded = next;
  }
  return decoded;
}

function decodeHtmlEntitiesOnce(value: string): string {
  let result = '';
  let offset = 0;
  while (offset < value.length) {
    const ampersand = value.indexOf('&', offset);
    if (ampersand < 0) {
      result += value.substring(offset);
      break;
    }
    result += value.substring(offset, ampersand);
    const semicolon = value.indexOf(';', ampersand + 1);
    if (semicolon < 0 || semicolon - ampersand > 12) {
      result += '&';
      offset = ampersand + 1;
      continue;
    }
    const entity = value.substring(ampersand + 1, semicolon);
    const replacement = decodeHtmlEntity(entity);
    if (replacement === null) {
      result += '&';
      offset = ampersand + 1;
      continue;
    }
    result += replacement;
    offset = semicolon + 1;
  }
  return result;
}

function decodeHtmlEntity(entity: string): string | null {
  const normalized = entity.toLowerCase();
  switch (normalized) {
    case 'amp':
      return '&';
    case 'lt':
      return '<';
    case 'gt':
      return '>';
    case 'quot':
      return '"';
    case 'apos':
      return "'";
    case 'nbsp':
      return ' ';
    default:
      return decodeNumericHtmlEntity(normalized);
  }
}

function decodeNumericHtmlEntity(entity: string): string | null {
  if (entity.length < 2 || entity.charAt(0) !== '#') {
    return null;
  }
  const hexadecimal = entity.length > 2 && entity.charAt(1) === 'x';
  const digits = entity.substring(hexadecimal ? 2 : 1);
  if (digits.length === 0 || !(hexadecimal ? /^[0-9a-f]+$/.test(digits) : /^\d+$/.test(digits))) {
    return null;
  }
  const codePoint = Number.parseInt(digits, hexadecimal ? 16 : 10);
  if (Number.isNaN(codePoint) || codePoint <= 0 || codePoint > 0x10FFFF ||
    (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
    return null;
  }
  if (codePoint <= 0xFFFF) {
    return String.fromCharCode(codePoint);
  }
  const adjusted = codePoint - 0x10000;
  return String.fromCharCode(0xD800 + (adjusted >> 10), 0xDC00 + (adjusted & 0x3FF));
}
