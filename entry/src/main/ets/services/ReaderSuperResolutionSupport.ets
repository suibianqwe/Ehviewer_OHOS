import { deviceInfo } from '@kit.BasicServicesKit';

export const READER_SUPER_RESOLUTION_ENGINE_DETAIL: string = 'Detail enhancer';
export const READER_SUPER_RESOLUTION_ENGINE_CORE_VISION: string = 'Core Vision AI';

export function coreVisionSuperResolutionAvailable(): boolean {
  return deviceInfo.apiAvailable('26.0.0');
}

export function normalizeReaderSuperResolutionEngine(value: string): string {
  return value === READER_SUPER_RESOLUTION_ENGINE_CORE_VISION ?
    READER_SUPER_RESOLUTION_ENGINE_CORE_VISION : READER_SUPER_RESOLUTION_ENGINE_DETAIL;
}

export function effectiveReaderSuperResolutionEngine(value: string): string {
  const normalized = normalizeReaderSuperResolutionEngine(value);
  if (normalized === READER_SUPER_RESOLUTION_ENGINE_CORE_VISION && !coreVisionSuperResolutionAvailable()) {
    return READER_SUPER_RESOLUTION_ENGINE_DETAIL;
  }
  return normalized;
}

export function readerSuperResolutionEngineOptions(): string[] {
  const options: string[] = [READER_SUPER_RESOLUTION_ENGINE_DETAIL];
  if (coreVisionSuperResolutionAvailable()) {
    options.push(READER_SUPER_RESOLUTION_ENGINE_CORE_VISION);
  }
  return options;
}

export function readerSuperResolutionEngineCacheKey(value: string): string {
  return effectiveReaderSuperResolutionEngine(value) === READER_SUPER_RESOLUTION_ENGINE_CORE_VISION ?
    'core-vision' : 'detail';
}
