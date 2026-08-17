import { ehSettingsStore } from './EhSettingsStore';

export class ReaderImageAdjustmentSettings {
  enabled: boolean = false;
  contrast: number = 0;
  clarity: number = 0;
  sharpening: number = 0;
  exposure: number = 0;
  brightness: number = 0;
  highlights: number = 0;
  shadows: number = 0;
  hue: number = 0;
  saturation: number = 0;
  vibrance: number = 0;
  temperature: number = 0;
  grayscale: number = 0;

  cacheKey(): string {
    return (this.enabled ? '1' : '0') + ':' + this.contrast + ':' + this.clarity + ':' + this.sharpening + ':' +
      this.exposure + ':' + this.brightness + ':' + this.highlights + ':' + this.shadows + ':' + this.hue + ':' +
      this.saturation + ':' + this.vibrance + ':' + this.temperature + ':' + this.grayscale;
  }

  detailCacheKey(): string {
    return (this.enabled ? '1' : '0') + ':' + this.clarity + ':' + this.sharpening + ':' + this.highlights + ':' +
      this.shadows + ':' + this.vibrance;
  }

  requiresOfflineProcessing(): boolean {
    return this.enabled && (this.clarity > 0 || this.sharpening > 0 || this.highlights !== 0 ||
      this.shadows !== 0 || this.vibrance !== 0);
  }

  hasColorAdjustments(): boolean {
    return this.enabled && (this.contrast !== 0 || this.exposure !== 0 || this.brightness !== 0 ||
      this.hue !== 0 || this.saturation !== 0 || this.temperature !== 0 || this.grayscale !== 0);
  }
}

const IDENTITY_COLOR_MATRIX: number[] = [
  1, 0, 0, 0, 0,
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0
];
const COLOR_FILTER_CACHE: Map<string, ColorFilter> = new Map<string, ColorFilter>();
const COLOR_FILTER_CACHE_LIMIT: number = 48;

function cacheColorFilter(key: string, filter: ColorFilter): ColorFilter {
  if (COLOR_FILTER_CACHE.size >= COLOR_FILTER_CACHE_LIMIT && !COLOR_FILTER_CACHE.has(key)) {
    COLOR_FILTER_CACHE.clear();
  }
  COLOR_FILTER_CACHE.set(key, filter);
  return filter;
}

export function readerImageColorFilter(settings: ReaderImageAdjustmentSettings): ColorFilter {
  const key = settings.hasColorAdjustments() ? settings.cacheKey() : 'identity';
  const cached = COLOR_FILTER_CACHE.get(key);
  if (cached !== undefined) {
    return cached;
  }
  if (!settings.hasColorAdjustments()) {
    const identity = new ColorFilter(IDENTITY_COLOR_MATRIX);
    return cacheColorFilter(key, identity);
  }
  const exposure = Math.pow(2, clamp(settings.exposure, -100, 100) / 50);
  const contrastValue = clamp(settings.contrast, -100, 100) * 1.27;
  const contrast = (259 * (contrastValue + 255)) / (255 * (259 - contrastValue));
  const saturation = 1 + clamp(settings.saturation, -100, 100) / 100;
  const hue = clamp(settings.hue, -180, 180) * Math.PI / 180;
  const hueCos = Math.cos(hue);
  const hueSin = Math.sin(hue);
  const temperature = clamp(settings.temperature, -100, 100);
  const brightness = clamp(settings.brightness, -100, 100) * 0.35 / 100;
  const grayscale = clamp(settings.grayscale, 0, 100) / 100;
  let matrix = multiplyColorMatrices([
    exposure, 0, 0, 0, 0,
    0, exposure, 0, 0, 0,
    0, 0, exposure, 0, 0,
    0, 0, 0, 1, 0
  ], IDENTITY_COLOR_MATRIX);
  matrix = multiplyColorMatrices([
    0.213 + hueCos * 0.787 - hueSin * 0.213,
    0.715 - hueCos * 0.715 - hueSin * 0.715,
    0.072 - hueCos * 0.072 + hueSin * 0.928, 0, 0,
    0.213 - hueCos * 0.213 + hueSin * 0.143,
    0.715 + hueCos * 0.285 + hueSin * 0.140,
    0.072 - hueCos * 0.072 - hueSin * 0.283, 0, 0,
    0.213 - hueCos * 0.213 - hueSin * 0.787,
    0.715 - hueCos * 0.715 + hueSin * 0.715,
    0.072 + hueCos * 0.928 + hueSin * 0.072, 0, 0,
    0, 0, 0, 1, 0
  ], matrix);
  if (grayscale > 0) {
    const color = 1 - grayscale;
    matrix = multiplyColorMatrices([
      0.2126 * grayscale + color, 0.7152 * grayscale, 0.0722 * grayscale, 0, 0,
      0.2126 * grayscale, 0.7152 * grayscale + color, 0.0722 * grayscale, 0, 0,
      0.2126 * grayscale, 0.7152 * grayscale, 0.0722 * grayscale + color, 0, 0,
      0, 0, 0, 1, 0
    ], matrix);
  }
  const inverseSaturation = 1 - saturation;
  matrix = multiplyColorMatrices([
    0.2126 * inverseSaturation + saturation, 0.7152 * inverseSaturation,
    0.0722 * inverseSaturation, 0, 0,
    0.2126 * inverseSaturation, 0.7152 * inverseSaturation + saturation,
    0.0722 * inverseSaturation, 0, 0,
    0.2126 * inverseSaturation, 0.7152 * inverseSaturation,
    0.0722 * inverseSaturation + saturation, 0, 0,
    0, 0, 0, 1, 0
  ], matrix);
  const contrastOffset = 0.5 * (1 - contrast);
  const filter = new ColorFilter(multiplyColorMatrices([
    contrast, 0, 0, 0, contrastOffset + brightness + temperature * 0.28 / 255,
    0, contrast, 0, 0, contrastOffset + brightness + temperature * 0.04 / 255,
    0, 0, contrast, 0, contrastOffset + brightness - temperature * 0.28 / 255,
    0, 0, 0, 1, 0
  ], matrix));
  return cacheColorFilter(key, filter);
}

function multiplyColorMatrices(left: number[], right: number[]): number[] {
  const result: number[] = new Array<number>(20).fill(0);
  for (let row = 0; row < 4; row++) {
    for (let column = 0; column < 4; column++) {
      let value = 0;
      for (let index = 0; index < 4; index++) {
        value += left[row * 5 + index] * right[index * 5 + column];
      }
      result[row * 5 + column] = value;
    }
    let offset = left[row * 5 + 4];
    for (let index = 0; index < 4; index++) {
      offset += left[row * 5 + index] * right[index * 5 + 4];
    }
    result[row * 5 + 4] = offset;
  }
  return result;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

export function readerImageAdjustmentSettingsFromStore(): ReaderImageAdjustmentSettings {
  const value = new ReaderImageAdjustmentSettings();
  value.enabled = ehSettingsStore.getValue('reader_image_adjustment', 'Off') === 'On';
  value.contrast = parseAdjustmentValue('reader_image_contrast', -100, 100);
  value.clarity = parseAdjustmentValue('reader_image_clarity', 0, 100);
  value.sharpening = parseAdjustmentValue('reader_image_sharpening', 0, 100);
  value.exposure = parseAdjustmentValue('reader_image_exposure', -100, 100);
  value.brightness = parseAdjustmentValue('reader_image_brightness', -100, 100);
  value.highlights = parseAdjustmentValue('reader_image_highlights', -100, 100);
  value.shadows = parseAdjustmentValue('reader_image_shadows', -100, 100);
  value.hue = parseAdjustmentValue('reader_image_hue', -180, 180);
  value.saturation = parseAdjustmentValue('reader_image_saturation', -100, 100);
  value.vibrance = parseAdjustmentValue('reader_image_vibrance', -100, 100);
  value.temperature = parseAdjustmentValue('reader_image_temperature', -100, 100);
  value.grayscale = parseAdjustmentValue('reader_image_grayscale', 0, 100);
  return value;
}

export function cloneReaderImageAdjustmentSettings(
  source: ReaderImageAdjustmentSettings): ReaderImageAdjustmentSettings {
  const value = new ReaderImageAdjustmentSettings();
  value.enabled = source.enabled;
  value.contrast = source.contrast;
  value.clarity = source.clarity;
  value.sharpening = source.sharpening;
  value.exposure = source.exposure;
  value.brightness = source.brightness;
  value.highlights = source.highlights;
  value.shadows = source.shadows;
  value.hue = source.hue;
  value.saturation = source.saturation;
  value.vibrance = source.vibrance;
  value.temperature = source.temperature;
  value.grayscale = source.grayscale;
  return value;
}

export function saveReaderImageAdjustmentSettings(value: ReaderImageAdjustmentSettings): void {
  ehSettingsStore.setValue('reader_image_adjustment', value.enabled ? 'On' : 'Off');
  ehSettingsStore.setValue('reader_image_contrast', clampRound(value.contrast, -100, 100).toString());
  ehSettingsStore.setValue('reader_image_clarity', clampRound(value.clarity, 0, 100).toString());
  ehSettingsStore.setValue('reader_image_sharpening', clampRound(value.sharpening, 0, 100).toString());
  ehSettingsStore.setValue('reader_image_exposure', clampRound(value.exposure, -100, 100).toString());
  ehSettingsStore.setValue('reader_image_brightness', clampRound(value.brightness, -100, 100).toString());
  ehSettingsStore.setValue('reader_image_highlights', clampRound(value.highlights, -100, 100).toString());
  ehSettingsStore.setValue('reader_image_shadows', clampRound(value.shadows, -100, 100).toString());
  ehSettingsStore.setValue('reader_image_hue', clampRound(value.hue, -180, 180).toString());
  ehSettingsStore.setValue('reader_image_saturation', clampRound(value.saturation, -100, 100).toString());
  ehSettingsStore.setValue('reader_image_vibrance', clampRound(value.vibrance, -100, 100).toString());
  ehSettingsStore.setValue('reader_image_temperature', clampRound(value.temperature, -100, 100).toString());
  ehSettingsStore.setValue('reader_image_grayscale', clampRound(value.grayscale, 0, 100).toString());
}

export function resetReaderImageAdjustmentSettings(value: ReaderImageAdjustmentSettings): void {
  value.contrast = 0;
  value.clarity = 0;
  value.sharpening = 0;
  value.exposure = 0;
  value.brightness = 0;
  value.highlights = 0;
  value.shadows = 0;
  value.hue = 0;
  value.saturation = 0;
  value.vibrance = 0;
  value.temperature = 0;
  value.grayscale = 0;
}

function parseAdjustmentValue(key: string, min: number, max: number): number {
  const parsed = Number.parseInt(ehSettingsStore.getValue(key, '0'));
  return Number.isNaN(parsed) ? 0 : clampRound(parsed, min, max);
}

function clampRound(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, Math.round(value)));
}
