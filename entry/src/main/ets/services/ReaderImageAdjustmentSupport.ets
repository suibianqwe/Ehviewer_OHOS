import { ehSettingsStore } from './EhSettingsStore';

export class ReaderImageAdjustmentSettings {
  enabled: boolean = false;
  contrast: number = 0;
  clarity: number = 0;
  sharpening: number = 0;
  exposure: number = 0;
  hue: number = 0;
  saturation: number = 0;
  temperature: number = 0;

  cacheKey(): string {
    return (this.enabled ? '1' : '0') + ':' + this.contrast + ':' + this.clarity + ':' + this.sharpening + ':' +
      this.exposure + ':' + this.hue + ':' + this.saturation + ':' + this.temperature;
  }
}

export function readerImageAdjustmentSettingsFromStore(): ReaderImageAdjustmentSettings {
  const value = new ReaderImageAdjustmentSettings();
  value.enabled = ehSettingsStore.getValue('reader_image_adjustment', 'Off') === 'On';
  value.contrast = parseAdjustmentValue('reader_image_contrast', -100, 100);
  value.clarity = parseAdjustmentValue('reader_image_clarity', 0, 100);
  value.sharpening = parseAdjustmentValue('reader_image_sharpening', 0, 100);
  value.exposure = parseAdjustmentValue('reader_image_exposure', -100, 100);
  value.hue = parseAdjustmentValue('reader_image_hue', -180, 180);
  value.saturation = parseAdjustmentValue('reader_image_saturation', -100, 100);
  value.temperature = parseAdjustmentValue('reader_image_temperature', -100, 100);
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
  value.hue = source.hue;
  value.saturation = source.saturation;
  value.temperature = source.temperature;
  return value;
}

export function saveReaderImageAdjustmentSettings(value: ReaderImageAdjustmentSettings): void {
  ehSettingsStore.setValue('reader_image_adjustment', value.enabled ? 'On' : 'Off');
  ehSettingsStore.setValue('reader_image_contrast', clampRound(value.contrast, -100, 100).toString());
  ehSettingsStore.setValue('reader_image_clarity', clampRound(value.clarity, 0, 100).toString());
  ehSettingsStore.setValue('reader_image_sharpening', clampRound(value.sharpening, 0, 100).toString());
  ehSettingsStore.setValue('reader_image_exposure', clampRound(value.exposure, -100, 100).toString());
  ehSettingsStore.setValue('reader_image_hue', clampRound(value.hue, -180, 180).toString());
  ehSettingsStore.setValue('reader_image_saturation', clampRound(value.saturation, -100, 100).toString());
  ehSettingsStore.setValue('reader_image_temperature', clampRound(value.temperature, -100, 100).toString());
}

export function resetReaderImageAdjustmentSettings(value: ReaderImageAdjustmentSettings): void {
  value.contrast = 0;
  value.clarity = 0;
  value.sharpening = 0;
  value.exposure = 0;
  value.hue = 0;
  value.saturation = 0;
  value.temperature = 0;
}

function parseAdjustmentValue(key: string, min: number, max: number): number {
  const parsed = Number.parseInt(ehSettingsStore.getValue(key, '0'));
  return Number.isNaN(parsed) ? 0 : clampRound(parsed, min, max);
}

function clampRound(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, Math.round(value)));
}
