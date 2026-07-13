import { http } from '@kit.NetworkKit';
import { ehSettingsStore } from './EhSettingsStore';
import { applyConfiguredNetworkOptions } from './EhNetworkConfig';
import {
  SavedTranslationApi,
  findSavedTranslationApi,
  parseSavedTranslationApis
} from './TranslationApiConfigSupport';

export const TRANSLATION_ENABLED_KEY: string = 'ehviewerTranslationEnabled';
export const TRANSLATION_ERROR_REVISION_KEY: string = 'ehviewerTranslationErrorRevision';
export const TRANSLATION_ERROR_MESSAGE_KEY: string = 'ehviewerTranslationErrorMessage';

interface TranslationCacheEntry {
  key: string;
  value: string;
}

interface PendingTranslationEntry {
  key: string;
  promise: Promise<string>;
}

interface TranslationSlotWaiter {
  resume: () => void;
}

interface MyMemoryResponseData {
  translatedText?: string;
}

interface MyMemoryResponse {
  responseData?: MyMemoryResponseData;
  responseStatus?: number;
  responseDetails?: string;
}

interface LingvaResponse {
  translation?: string;
  error?: string;
}

interface BingTranslationText {
  text?: string;
}

interface BingTranslationResult {
  translations?: BingTranslationText[];
}

interface BaiduTranslationItem {
  dst?: string;
}

interface BaiduTranslationResponse {
  data?: BaiduTranslationItem[];
  trans_result?: BaiduTranslationResponse;
  errno?: number;
  errmsg?: string;
}

interface YoudaoTranslationResponse {
  translation?: string[];
  errorCode?: string;
}

interface ChatMessage {
  role: string;
  content: string;
}

interface ChatRequestBody {
  model: string;
  messages: ChatMessage[];
  stream: boolean;
  temperature: number;
}

interface ChatResponseMessage {
  content?: string;
}

interface ChatResponseChoice {
  message?: ChatResponseMessage;
}

interface ChatResponseBody {
  choices?: ChatResponseChoice[];
  error?: ChatResponseError;
}

interface ChatResponseError {
  message?: string;
}

interface GeminiPart {
  text: string;
}

interface GeminiContent {
  role?: string;
  parts: GeminiPart[];
}

interface GeminiRequestBody {
  contents: GeminiContent[];
  systemInstruction: GeminiContent;
  generationConfig: GeminiGenerationConfig;
}

interface GeminiGenerationConfig {
  temperature: number;
}

interface GeminiCandidate {
  content?: GeminiContent;
}

interface GeminiResponseBody {
  candidates?: GeminiCandidate[];
  error?: ChatResponseError;
}

interface ModelInfo {
  id?: string;
}

interface ModelListResponse {
  data?: ModelInfo[];
  error?: ChatResponseError;
}

interface GeminiModelInfo {
  name?: string;
  supportedGenerationMethods?: string[];
}

interface GeminiModelListResponse {
  models?: GeminiModelInfo[];
  error?: ChatResponseError;
}

const MAX_CACHE_ENTRIES: number = 1200;
const MAX_ACTIVE_REQUESTS: number = 3;
const DEFAULT_TIMEOUT_MS: number = 15000;
const TRANSLATION_CACHE: TranslationCacheEntry[] = [];
const PENDING_TRANSLATIONS: PendingTranslationEntry[] = [];
const SLOT_WAITERS: TranslationSlotWaiter[] = [];
let activeRequests: number = 0;
let lastTranslationErrorAt: number = 0;
let lastTranslationErrorMessage: string = '';
let translationSessionRevision: number = 0;

export class EhTranslationService {
  setEnabled(enabled: boolean): void {
    const wasEnabled = AppStorage.get<boolean>(TRANSLATION_ENABLED_KEY) === true;
    if (enabled && !wasEnabled) {
      translationSessionRevision++;
      this.clearCache();
    }
    AppStorage.setOrCreate<boolean>(TRANSLATION_ENABLED_KEY, enabled);
  }

  async translateTitle(text: string): Promise<string> {
    return this.translate(text, 'gallery title');
  }

  async translateComment(text: string): Promise<string> {
    return this.translate(text, 'gallery comment');
  }

  async translate(text: string, contentKind: string = 'text'): Promise<string> {
    const source = text.trim();
    if (source.length === 0) {
      return '';
    }
    const provider = ehSettingsStore.getValue('translation_provider', 'Google Web');
    const target = ehSettingsStore.getValue('translation_target_language', 'Simplified Chinese');
    const key = translationSessionRevision.toString() + '\n' +
      translationConfigurationKey(provider, target) + '\n' + contentKind + '\n' + source;
    const cached = getCachedTranslation(key);
    if (cached !== null) {
      return cached;
    }
    const pending = getPendingTranslation(key);
    if (pending !== null) {
      return pending;
    }
    const promise = this.translateInternal(source, provider, target, contentKind)
      .then((translated: string) => {
        const normalized = normalizeTranslationResult(translated, source);
        putCachedTranslation(key, normalized);
        return normalized;
      })
      .catch((error: Error) => {
        notifyTranslationError(error);
        throw error;
      })
      .finally(() => {
        removePendingTranslation(key);
      });
    PENDING_TRANSLATIONS.push({ key: key, promise: promise });
    return promise;
  }

  clearCache(): void {
    TRANSLATION_CACHE.splice(0, TRANSLATION_CACHE.length);
  }

  async fetchAvailableModels(provider: string = ehSettingsStore.getValue('translation_provider', 'Google Web')):
    Promise<string[]> {
    if (provider === 'Gemini') {
      const apiKey = ehSettingsStore.getValue('translation_gemini_api_key', '').trim();
      if (apiKey.length === 0) {
        throw new Error('Translation API key is missing');
      }
      const body = await requestText('https://generativelanguage.googleapis.com/v1beta/models',
        http.RequestMethod.GET, '', '', apiKey);
      const parsed = JSON.parse(body) as GeminiModelListResponse;
      const result: string[] = [];
      const models = parsed.models === undefined ? [] : parsed.models;
      for (let i = 0; i < models.length; i++) {
        const supportedMethods = models[i].supportedGenerationMethods;
        const methods: string[] = supportedMethods === undefined ? [] : supportedMethods;
        if (typeof models[i].name === 'string' && methods.indexOf('generateContent') >= 0) {
          result.push(stripGeminiModelPrefix(models[i].name as string));
        }
      }
      return uniqueSortedModels(result);
    }
    let baseUrl = '';
    let apiKey = '';
    if (provider === 'DeepSeek') {
      baseUrl = 'https://api.deepseek.com';
      apiKey = ehSettingsStore.getValue('translation_deepseek_api_key', '');
    } else if (provider === 'OpenAI') {
      baseUrl = 'https://api.openai.com/v1';
      apiKey = ehSettingsStore.getValue('translation_official_openai_api_key', '');
    } else if (provider === 'Custom API') {
      const custom = activeCustomTranslationApi();
      if (custom === null) {
        throw new Error('No custom translation API is selected');
      }
      baseUrl = custom.baseUrl;
      apiKey = custom.apiKey;
    } else {
      return [];
    }
    if (apiKey.trim().length === 0) {
      throw new Error('Translation API key is missing');
    }
    const body = await requestText(modelsUrl(baseUrl), http.RequestMethod.GET, '', apiKey.trim());
    const parsed = JSON.parse(body) as ModelListResponse;
    if (!Array.isArray(parsed.data)) {
      throw new Error(parsed.error?.message === undefined ? 'Invalid model list response' : parsed.error.message);
    }
    const result: string[] = [];
    for (let i = 0; i < parsed.data.length; i++) {
      if (typeof parsed.data[i].id === 'string' && (parsed.data[i].id as string).trim().length > 0) {
        result.push((parsed.data[i].id as string).trim());
      }
    }
    return uniqueSortedModels(result);
  }

  private async translateInternal(text: string, provider: string, target: string,
    contentKind: string): Promise<string> {
    await acquireTranslationSlot();
    try {
      if (provider === 'MyMemory') {
        return await this.translateWithMyMemory(text, target);
      }
      if (provider === 'Lingva') {
        return await this.translateWithLingva(text, target);
      }
      if (provider === 'Bing Web') {
        return await this.translateWithBingWeb(text, target);
      }
      if (provider === 'Baidu Web') {
        return await this.translateWithBaiduWeb(text, target);
      }
      if (provider === 'Youdao Web') {
        return await this.translateWithYoudaoWeb(text, target);
      }
      if (provider === 'DeepSeek') {
        return await this.translateWithChatApi(text, target, contentKind,
          'https://api.deepseek.com/chat/completions',
          ehSettingsStore.getValue('translation_deepseek_api_key', ''),
          ehSettingsStore.getValue('translation_deepseek_model', 'deepseek-v4-flash'));
      }
      if (provider === 'OpenAI') {
        return await this.translateWithChatApi(text, target, contentKind,
          'https://api.openai.com/v1/chat/completions',
          ehSettingsStore.getValue('translation_official_openai_api_key', ''),
          ehSettingsStore.getValue('translation_official_openai_model', 'gpt-4.1-mini'));
      }
      if (provider === 'Custom API') {
        const custom = activeCustomTranslationApi();
        if (custom === null) {
          throw new Error('No custom translation API is selected');
        }
        return await this.translateWithChatApi(text, target, contentKind, chatCompletionsUrl(custom.baseUrl),
          custom.apiKey, custom.model);
      }
      if (provider === 'Gemini') {
        return await this.translateWithGemini(text, target, contentKind);
      }
      return await this.translateWithGoogleWeb(text, target);
    } finally {
      releaseTranslationSlot();
    }
  }

  private async translateWithGoogleWeb(text: string, target: string): Promise<string> {
    const chunks = splitTranslationText(text, 1800);
    const translated: string[] = [];
    for (let i = 0; i < chunks.length; i++) {
      translated.push(await this.translateGoogleChunk(chunks[i], target));
    }
    return translated.join('\n');
  }

  private async translateGoogleChunk(text: string, target: string): Promise<string> {
    const url = 'https://translate.googleapis.com/translate_a/single?client=gtx&dt=t&sl=auto&tl=' +
      encodeURIComponent(targetLanguageCode(target, 'google')) + '&q=' + encodeURIComponent(text);
    const body = await requestText(url, http.RequestMethod.GET);
    const root = JSON.parse(body) as Object[];
    if (!Array.isArray(root) || root.length === 0 || !Array.isArray(root[0])) {
      throw new Error('Invalid Google translation response');
    }
    const segments = root[0] as Object[];
    let result = '';
    for (let i = 0; i < segments.length; i++) {
      if (!Array.isArray(segments[i])) {
        continue;
      }
      const segment = segments[i] as Object[];
      if (segment.length > 0 && typeof segment[0] === 'string') {
        result += segment[0] as string;
      }
    }
    return result;
  }

  private async translateWithMyMemory(text: string, target: string): Promise<string> {
    const chunks = splitTranslationText(text, 140);
    const translated: string[] = [];
    for (let i = 0; i < chunks.length; i++) {
      const sourceLanguage = detectSourceLanguage(chunks[i]);
      const url = 'https://api.mymemory.translated.net/get?q=' + encodeURIComponent(chunks[i]) + '&langpair=' +
        encodeURIComponent(sourceLanguage + '|' + targetLanguageCode(target, 'mymemory')) + '&mt=1';
      const body = await requestText(url, http.RequestMethod.GET);
      const parsed = JSON.parse(body) as MyMemoryResponse;
      const value = parsed.responseData?.translatedText;
      if (typeof value !== 'string' || value.length === 0) {
        throw new Error(parsed.responseDetails === undefined ? 'Invalid MyMemory response' : parsed.responseDetails);
      }
      translated.push(value);
    }
    return translated.join('\n');
  }

  private async translateWithLingva(text: string, target: string): Promise<string> {
    const chunks = splitTranslationText(text, 1800);
    const translated: string[] = [];
    for (let i = 0; i < chunks.length; i++) {
      const url = 'https://lingva.ml/api/v1/auto/' + targetLanguageCode(target, 'lingva') + '/' +
        encodeURIComponent(chunks[i]);
      const body = await requestText(url, http.RequestMethod.GET);
      const parsed = JSON.parse(body) as LingvaResponse;
      if (typeof parsed.translation !== 'string' || parsed.translation.length === 0) {
        throw new Error(parsed.error === undefined ? 'Invalid Lingva response' : parsed.error);
      }
      translated.push(parsed.translation);
    }
    return translated.join('\n');
  }

  private async translateWithBingWeb(text: string, target: string): Promise<string> {
    const chunks = splitTranslationText(text, 900);
    const translated: string[] = [];
    const page = await requestText('https://www.bing.com/translator', http.RequestMethod.GET, '', '', '',
      { 'Accept': 'text/html,application/xhtml+xml' });
    const ig = firstRegexGroup(page, /IG:\"([^\"]+)\"/);
    const abuse = /params_AbusePreventionHelper\s*=\s*\[(\d+),\"([^\"]+)/.exec(page);
    const iid = firstRegexGroup(page, /id=\"rich_tta\" data-iid=\"([^\"]+)/);
    if (ig.length === 0 || abuse === null || abuse.length < 3) {
      throw new Error('Bing web translation token is unavailable');
    }
    for (let i = 0; i < chunks.length; i++) {
      const form = formBody([
        ['fromLang', 'auto-detect'],
        ['text', chunks[i]],
        ['to', targetLanguageCode(target, 'bing')],
        ['token', abuse[2]],
        ['key', abuse[1]]
      ]);
      const url = 'https://www.bing.com/ttranslatev3?isVertical=1&IG=' + encodeURIComponent(ig) + '&IID=' +
        encodeURIComponent((iid.length > 0 ? iid : 'translator.5025') + '.1');
      const body = await requestText(url, http.RequestMethod.POST, form, '', '', {
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Origin': 'https://www.bing.com',
        'Referer': 'https://www.bing.com/translator'
      });
      const parsed = JSON.parse(body) as BingTranslationResult[];
      const value = parsed?.[0]?.translations?.[0]?.text;
      if (typeof value !== 'string' || value.length === 0) {
        throw new Error('Bing web translation is unavailable');
      }
      translated.push(value);
    }
    return translated.join('\n');
  }

  private async translateWithBaiduWeb(text: string, target: string): Promise<string> {
    const chunks = splitTranslationText(text, 1000);
    const translated: string[] = [];
    for (let i = 0; i < chunks.length; i++) {
      const form = formBody([
        ['from', 'auto'],
        ['to', targetLanguageCode(target, 'baidu')],
        ['query', chunks[i]],
        ['source', 'txt']
      ]);
      const body = await requestText('https://fanyi.baidu.com/transapi', http.RequestMethod.POST, form, '', '', {
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Origin': 'https://fanyi.baidu.com',
        'Referer': 'https://fanyi.baidu.com/'
      });
      const parsed = JSON.parse(body) as BaiduTranslationResponse;
      const data = parsed.data === undefined ? parsed.trans_result?.data : parsed.data;
      if (!Array.isArray(data) || data.length === 0) {
        throw new Error(parsed.errmsg === undefined ? 'Baidu web translation is unavailable' : parsed.errmsg);
      }
      let value = '';
      for (let j = 0; j < data.length; j++) {
        if (typeof data[j].dst === 'string') {
          value += data[j].dst;
        }
      }
      if (value.length === 0) {
        throw new Error('Invalid Baidu translation response');
      }
      translated.push(value);
    }
    return translated.join('\n');
  }

  private async translateWithYoudaoWeb(text: string, target: string): Promise<string> {
    const chunks = splitTranslationText(text, 900);
    const translated: string[] = [];
    for (let i = 0; i < chunks.length; i++) {
      const form = formBody([
        ['q', chunks[i]],
        ['from', 'Auto'],
        ['to', targetLanguageCode(target, 'youdao')]
      ]);
      const body = await requestText('https://aidemo.youdao.com/trans', http.RequestMethod.POST, form, '', '', {
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Origin': 'https://fanyi.youdao.com',
        'Referer': 'https://fanyi.youdao.com/'
      });
      const parsed = JSON.parse(body) as YoudaoTranslationResponse;
      if (!Array.isArray(parsed.translation) || parsed.translation.length === 0) {
        throw new Error('Youdao web translation failed: ' + (parsed.errorCode === undefined ? 'unknown' : parsed.errorCode));
      }
      translated.push(parsed.translation.join('\n'));
    }
    return translated.join('\n');
  }

  private async translateWithChatApi(text: string, target: string, contentKind: string, url: string,
    apiKey: string, model: string): Promise<string> {
    if (apiKey.trim().length === 0) {
      throw new Error('Translation API key is missing');
    }
    if (model.trim().length === 0) {
      throw new Error('Translation model is missing');
    }
    const requestBody: ChatRequestBody = {
      model: model.trim(),
      messages: [
        { role: 'system', content: translationSystemPrompt(target, contentKind) },
        { role: 'user', content: text }
      ],
      stream: false,
      temperature: 0.1
    };
    const body = await requestText(url, http.RequestMethod.POST, JSON.stringify(requestBody), apiKey.trim());
    const parsed = JSON.parse(body) as ChatResponseBody;
    const content = parsed.choices?.[0]?.message?.content;
    if (typeof content !== 'string' || content.length === 0) {
      throw new Error(parsed.error?.message === undefined ? 'Invalid AI translation response' : parsed.error.message);
    }
    return content;
  }

  private async translateWithGemini(text: string, target: string, contentKind: string): Promise<string> {
    const apiKey = ehSettingsStore.getValue('translation_gemini_api_key', '').trim();
    const model = ehSettingsStore.getValue('translation_gemini_model', 'gemini-3.5-flash').trim();
    if (apiKey.length === 0) {
      throw new Error('Translation API key is missing');
    }
    if (model.length === 0) {
      throw new Error('Translation model is missing');
    }
    const url = 'https://generativelanguage.googleapis.com/v1beta/models/' + encodeURIComponent(model) +
      ':generateContent';
    const requestBody: GeminiRequestBody = {
      systemInstruction: { parts: [{ text: translationSystemPrompt(target, contentKind) }] },
      contents: [{ role: 'user', parts: [{ text: text }] }],
      generationConfig: { temperature: 0.1 }
    };
    const body = await requestText(url, http.RequestMethod.POST, JSON.stringify(requestBody), '', apiKey);
    const parsed = JSON.parse(body) as GeminiResponseBody;
    const content = parsed.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof content !== 'string' || content.length === 0) {
      throw new Error(parsed.error?.message === undefined ? 'Invalid Gemini translation response' : parsed.error.message);
    }
    return content;
  }
}

export const ehTranslationService: EhTranslationService = new EhTranslationService();

async function requestText(url: string, method: http.RequestMethod, body: string = '', bearerToken: string = '',
  googleApiKey: string = '', extraHeaders: Record<string, string> = {}): Promise<string> {
  const request = http.createHttp();
  try {
    const timeout = translationTimeoutMs();
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      'User-Agent': 'EhViewerHarmony/Translation'
    };
    if (bearerToken.length > 0) {
      headers['Authorization'] = 'Bearer ' + bearerToken;
    }
    if (googleApiKey.length > 0) {
      headers['x-goog-api-key'] = googleApiKey;
    }
    const extraHeaderNames = Object.keys(extraHeaders);
    for (let i = 0; i < extraHeaderNames.length; i++) {
      headers[extraHeaderNames[i]] = extraHeaders[extraHeaderNames[i]];
    }
    const options: http.HttpRequestOptions = {
      method: method,
      header: headers,
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: timeout,
      readTimeout: timeout
    };
    applyConfiguredNetworkOptions(options);
    if (method === http.RequestMethod.POST) {
      options.extraData = body;
    }
    const response = await request.request(url, options);
    const statusCode = Number(response.responseCode);
    if (statusCode < 200 || statusCode >= 300) {
      throw new Error('HTTP ' + statusCode.toString());
    }
    return response.result as string;
  } catch (error) {
    throw new Error(String(error));
  } finally {
    try {
      request.destroy();
    } catch (_error) {
    }
  }
}

function translationTimeoutMs(): number {
  const raw = Number.parseInt(ehSettingsStore.getValue('translation_timeout', '15s'));
  if (Number.isNaN(raw)) {
    return DEFAULT_TIMEOUT_MS;
  }
  return Math.max(5, Math.min(60, raw)) * 1000;
}

function targetLanguageCode(target: string, provider: string): string {
  if (target === 'Traditional Chinese') {
    if (provider === 'lingva') {
      return 'zh_HANT';
    }
    if (provider === 'bing') {
      return 'zh-Hant';
    }
    if (provider === 'baidu') {
      return 'cht';
    }
    if (provider === 'youdao') {
      return 'zh-CHT';
    }
    return 'zh-TW';
  }
  if (target === 'English') {
    return 'en';
  }
  if (target === 'Japanese') {
    return provider === 'baidu' ? 'jp' : 'ja';
  }
  if (target === 'Korean') {
    return provider === 'baidu' ? 'kor' : 'ko';
  }
  if (provider === 'bing') {
    return 'zh-Hans';
  }
  if (provider === 'baidu') {
    return 'zh';
  }
  if (provider === 'youdao') {
    return 'zh-CHS';
  }
  return provider === 'lingva' ? 'zh' : 'zh-CN';
}

function targetLanguageName(target: string): string {
  if (target === 'Traditional Chinese') {
    return 'Traditional Chinese';
  }
  if (target === 'English' || target === 'Japanese' || target === 'Korean') {
    return target;
  }
  return 'Simplified Chinese';
}

function translationSystemPrompt(target: string, contentKind: string): string {
  return 'Translate the following ' + contentKind + ' into ' + targetLanguageName(target) +
    '. Preserve URLs, line breaks, names, brackets and formatting. Return only the translation without explanations or quotes.';
}

function translationConfigurationKey(provider: string, target: string): string {
  if (provider === 'DeepSeek') {
    return provider + '\n' + target + '\n' + ehSettingsStore.getValue('translation_deepseek_model', 'deepseek-v4-flash');
  }
  if (provider === 'OpenAI') {
    return provider + '\n' + target + '\n' +
      ehSettingsStore.getValue('translation_official_openai_model', 'gpt-4.1-mini');
  }
  if (provider === 'Gemini') {
    return provider + '\n' + target + '\n' + ehSettingsStore.getValue('translation_gemini_model', 'gemini-3.5-flash');
  }
  if (provider === 'Custom API') {
    const custom = activeCustomTranslationApi();
    return custom === null ? provider + '\n' + target : provider + '\n' + target + '\n' + custom.name + '\n' +
      custom.baseUrl + '\n' + custom.model;
  }
  return provider + '\n' + target;
}

function detectSourceLanguage(text: string): string {
  if (/[぀-ヿ]/.test(text)) {
    return 'ja';
  }
  if (/[가-힯]/.test(text)) {
    return 'ko';
  }
  if (/[一-鿿]/.test(text)) {
    return 'zh-CN';
  }
  return 'en';
}

function splitTranslationText(text: string, maxLength: number): string[] {
  if (text.length <= maxLength) {
    return [text];
  }
  const result: string[] = [];
  let cursor = 0;
  while (cursor < text.length) {
    let end = Math.min(text.length, cursor + maxLength);
    if (end < text.length) {
      const lineBreak = text.lastIndexOf('\n', end);
      const space = text.lastIndexOf(' ', end);
      const splitAt = Math.max(lineBreak, space);
      if (splitAt > cursor + Math.floor(maxLength * 0.55)) {
        end = splitAt;
      }
    }
    result.push(text.substring(cursor, end).trim());
    cursor = end;
    while (cursor < text.length && (text[cursor] === ' ' || text[cursor] === '\n')) {
      cursor++;
    }
  }
  return result;
}

function normalizeTranslationResult(value: string, fallback: string): string {
  let result = value.trim();
  if (result.startsWith('```') && result.endsWith('```')) {
    result = result.replace(/^```[A-Za-z-]*\s*/, '').replace(/\s*```$/, '').trim();
  }
  if (result.length >= 2 && ((result.startsWith('"') && result.endsWith('"')) ||
    (result.startsWith('“') && result.endsWith('”')))) {
    result = result.substring(1, result.length - 1).trim();
  }
  return result.length > 0 ? result : fallback;
}

function chatCompletionsUrl(baseUrl: string): string {
  let url = baseUrl.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (url.endsWith('/chat/completions')) {
    return url;
  }
  return url + '/chat/completions';
}

function modelsUrl(baseUrl: string): string {
  let url = baseUrl.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (url.endsWith('/chat/completions')) {
    url = url.substring(0, url.length - '/chat/completions'.length);
  }
  if (url.endsWith('/models')) {
    return url;
  }
  return url + '/models';
}

function activeCustomTranslationApi(): SavedTranslationApi | null {
  const items = parseSavedTranslationApis(ehSettingsStore.getValue('translation_custom_apis', '[]'));
  return findSavedTranslationApi(items, ehSettingsStore.getValue('translation_custom_api_selected', ''));
}

function stripGeminiModelPrefix(value: string): string {
  return value.indexOf('models/') === 0 ? value.substring('models/'.length) : value;
}

function uniqueSortedModels(models: string[]): string[] {
  const result: string[] = [];
  for (let i = 0; i < models.length; i++) {
    if (result.indexOf(models[i]) < 0) {
      result.push(models[i]);
    }
  }
  result.sort();
  return result;
}

function firstRegexGroup(text: string, pattern: RegExp): string {
  const match = pattern.exec(text);
  return match === null || match.length < 2 ? '' : match[1];
}

function formBody(entries: string[][]): string {
  const result: string[] = [];
  for (let i = 0; i < entries.length; i++) {
    if (entries[i].length >= 2) {
      result.push(encodeURIComponent(entries[i][0]) + '=' + encodeURIComponent(entries[i][1]));
    }
  }
  return result.join('&');
}

function notifyTranslationError(error: Error): void {
  const message = friendlyTranslationError(error);
  const now = Date.now();
  if (message === lastTranslationErrorMessage && now - lastTranslationErrorAt < 3000) {
    return;
  }
  lastTranslationErrorMessage = message;
  lastTranslationErrorAt = now;
  AppStorage.setOrCreate<string>(TRANSLATION_ERROR_MESSAGE_KEY, message);
  const revision = AppStorage.get<number>(TRANSLATION_ERROR_REVISION_KEY);
  AppStorage.setOrCreate<number>(TRANSLATION_ERROR_REVISION_KEY, revision === undefined ? 1 : revision + 1);
}

function friendlyTranslationError(error: Error): string {
  const detail = error.message.length > 0 ? error.message : String(error);
  const lower = detail.toLowerCase();
  if (lower.indexOf('timeout') >= 0 || lower.indexOf('timed out') >= 0 || lower.indexOf('2300028') >= 0) {
    return 'Translation timed out';
  }
  return 'Translation failed: ' + detail.replace(/^Error:\s*/, '');
}

function getCachedTranslation(key: string): string | null {
  for (let i = TRANSLATION_CACHE.length - 1; i >= 0; i--) {
    if (TRANSLATION_CACHE[i].key === key) {
      return TRANSLATION_CACHE[i].value;
    }
  }
  return null;
}

function putCachedTranslation(key: string, value: string): void {
  TRANSLATION_CACHE.push({ key: key, value: value });
  if (TRANSLATION_CACHE.length > MAX_CACHE_ENTRIES) {
    TRANSLATION_CACHE.splice(0, TRANSLATION_CACHE.length - MAX_CACHE_ENTRIES);
  }
}

function getPendingTranslation(key: string): Promise<string> | null {
  for (let i = 0; i < PENDING_TRANSLATIONS.length; i++) {
    if (PENDING_TRANSLATIONS[i].key === key) {
      return PENDING_TRANSLATIONS[i].promise;
    }
  }
  return null;
}

function removePendingTranslation(key: string): void {
  for (let i = PENDING_TRANSLATIONS.length - 1; i >= 0; i--) {
    if (PENDING_TRANSLATIONS[i].key === key) {
      PENDING_TRANSLATIONS.splice(i, 1);
    }
  }
}

function acquireTranslationSlot(): Promise<void> {
  if (activeRequests < MAX_ACTIVE_REQUESTS) {
    activeRequests++;
    return Promise.resolve();
  }
  return new Promise<void>((resolve: (value: void | PromiseLike<void>) => void) => {
    SLOT_WAITERS.push({
      resume: () => {
        activeRequests++;
        resolve();
      }
    });
  });
}

function releaseTranslationSlot(): void {
  activeRequests = Math.max(0, activeRequests - 1);
  if (SLOT_WAITERS.length > 0 && activeRequests < MAX_ACTIVE_REQUESTS) {
    const waiter = SLOT_WAITERS.shift();
    if (waiter !== undefined) {
      waiter.resume();
    }
  }
}
