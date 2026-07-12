export function normalizeGalleryLanguageCode(value: string): string {
  switch (value.trim().toLowerCase()) {
    case 'en':
    case 'english': return 'EN';
    case 'zh':
    case 'chinese': return 'ZH';
    case 'es':
    case 'spanish': return 'ES';
    case 'ko':
    case 'korean': return 'KO';
    case 'ru':
    case 'russian': return 'RU';
    case 'fr':
    case 'french': return 'FR';
    case 'pt':
    case 'portuguese': return 'PT';
    case 'th':
    case 'thai': return 'TH';
    case 'de':
    case 'german': return 'DE';
    case 'it':
    case 'italian': return 'IT';
    case 'vi':
    case 'vietnamese': return 'VI';
    case 'pl':
    case 'polish': return 'PL';
    case 'hu':
    case 'hungarian': return 'HU';
    case 'nl':
    case 'dutch': return 'NL';
    case 'ja':
    case 'japanese': return 'JA';
    default: return '';
  }
}

export function galleryLanguageCodeToName(code: string): string {
  switch (normalizeGalleryLanguageCode(code)) {
    case 'EN': return 'english';
    case 'ZH': return 'chinese';
    case 'ES': return 'spanish';
    case 'KO': return 'korean';
    case 'RU': return 'russian';
    case 'FR': return 'french';
    case 'PT': return 'portuguese';
    case 'TH': return 'thai';
    case 'DE': return 'german';
    case 'IT': return 'italian';
    case 'VI': return 'vietnamese';
    case 'PL': return 'polish';
    case 'HU': return 'hungarian';
    case 'NL': return 'dutch';
    case 'JA': return 'japanese';
    default: return '';
  }
}
