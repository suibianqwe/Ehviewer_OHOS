import { ehSettingsStore } from './EhSettingsStore';
import {
  normalizeReaderSuperResolutionEngine,
  READER_SUPER_RESOLUTION_ENGINE_DETAIL
} from './ReaderSuperResolutionSupport';
import {
  cloneReaderImageAdjustmentSettings,
  normalizeReaderMoireReduction,
  ReaderImageAdjustmentSettings,
  readerImageAdjustmentSettingsFromStore,
  saveReaderImageAdjustmentSettings
} from './ReaderImageAdjustmentSupport';

export const READER_CUSTOM_PRESETS_SETTING_KEY: string = 'reader_custom_presets';

export interface ReaderPresetValues {
  screenRotation: string;
  readingDirection: string;
  pageScaling: string;
  adaptiveDualPage: boolean;
  cropWhiteBorders: boolean;
  imageSuperResolution: boolean;
  superResolutionEngine: string;
  sdrToHdr: boolean;
  startPosition: string;
  imageAdjustment: ReaderImageAdjustmentSettings;
}

export interface ReaderPresetProfile {
  id: string;
  name: string;
  summary: string;
  builtIn: boolean;
  values: ReaderPresetValues;
}

export class ReaderPresetSaveResult {
  raw: string = '[]';
  profile: ReaderPresetProfile | null = null;
  error: string = '';
}

interface StoredReaderPresetValues {
  screenRotation?: string;
  readingDirection?: string;
  pageScaling?: string;
  adaptiveDualPage?: boolean;
  cropWhiteBorders?: boolean;
  imageSuperResolution?: boolean;
  superResolutionEngine?: string;
  sdrToHdr?: boolean;
  startPosition?: string;
  imageAdjustment?: ReaderImageAdjustmentSettings;
}

interface StoredReaderPresetProfile {
  id?: string;
  name?: string;
  builtIn?: boolean;
  values?: StoredReaderPresetValues;
}

const BUILT_IN_READER_PRESETS: ReaderPresetProfile[] = [
  {
    id: 'reader_preset_manga',
    name: 'Manga',
    summary: 'Right-to-left single-page reading with screen fitting',
    builtIn: true,
    values: createReaderPresetValues('Default', 'Right to left', 'Fit screen', false, false, false,
      READER_SUPER_RESOLUTION_ENGINE_DETAIL, false,
      'Center')
  },
  {
    id: 'reader_preset_dual_manga',
    name: 'Dual-page manga',
    summary: 'Right-to-left reading with adaptive dual-page layout',
    builtIn: true,
    values: createReaderPresetValues('Default', 'Right to left', 'Fit screen', true, true, false,
      READER_SUPER_RESOLUTION_ENGINE_DETAIL, false,
      'Center')
  },
  {
    id: 'reader_preset_comic',
    name: 'Left-to-right comics',
    summary: 'Left-to-right single-page reading with screen fitting',
    builtIn: true,
    values: createReaderPresetValues('Default', 'Left to right', 'Fit screen', false, false, false,
      READER_SUPER_RESOLUTION_ENGINE_DETAIL, false,
      'Top left')
  },
  {
    id: 'reader_preset_webtoon',
    name: 'Webtoon',
    summary: 'Continuous top-to-bottom reading fitted to screen width',
    builtIn: true,
    values: createReaderPresetValues('Default', 'Top to bottom', 'Fit width', false, false, false,
      READER_SUPER_RESOLUTION_ENGINE_DETAIL, false,
      'Top left')
  }
];

export function builtInReaderPresetProfiles(): ReaderPresetProfile[] {
  return cloneReaderPresetProfiles(BUILT_IN_READER_PRESETS);
}

export function parseCustomReaderPresetProfiles(raw: string): ReaderPresetProfile[] {
  const result: ReaderPresetProfile[] = [];
  const parsed = parseStoredReaderPresetProfiles(raw);
  for (let i = 0; i < parsed.length; i++) {
    const id = typeof parsed[i].id === 'string' ? (parsed[i].id as string).trim() : '';
    const name = typeof parsed[i].name === 'string' ? (parsed[i].name as string).trim() : '';
    const values = parseStoredReaderPresetValues(parsed[i].values);
    if (parsed[i].builtIn !== true && !isBuiltInReaderPresetId(id) && id.length > 0 && name.length > 0 &&
      !isReservedReaderPresetName(name) && values !== null && findReaderPresetProfile(result, id) === null &&
      !readerPresetNameExists(BUILT_IN_READER_PRESETS.concat(result), name)) {
      result.push({ id: id, name: name, summary: 'Custom reading preset', builtIn: false, values: values });
    }
  }
  return result;
}

export function serializeCustomReaderPresetProfiles(profiles: ReaderPresetProfile[]): string {
  return serializeStoredReaderPresetProfiles(profiles, []);
}

function serializeStoredReaderPresetProfiles(customProfiles: ReaderPresetProfile[],
  builtInOverrides: ReaderPresetProfile[]): string {
  const result: StoredReaderPresetProfile[] = [];
  for (let i = 0; i < customProfiles.length; i++) {
    const profile = customProfiles[i];
    if (profile.builtIn || profile.id.trim().length === 0 || profile.name.trim().length === 0) {
      continue;
    }
    result.push({ id: profile.id, name: profile.name.trim(), builtIn: false,
      values: storedReaderPresetValues(profile.values) });
  }
  for (let i = 0; i < builtInOverrides.length; i++) {
    const profile = builtInOverrides[i];
    if (!profile.builtIn || !isBuiltInReaderPresetId(profile.id)) {
      continue;
    }
    result.push({ id: profile.id, name: profile.name, builtIn: true,
      values: storedReaderPresetValues(profile.values) });
  }
  return JSON.stringify(result);
}

export function allReaderPresetProfiles(customRaw: string): ReaderPresetProfile[] {
  const result = builtInReaderPresetProfiles();
  const overrides = parseBuiltInReaderPresetOverrides(customRaw);
  for (let i = 0; i < overrides.length; i++) {
    const index = result.findIndex((profile: ReaderPresetProfile) => profile.id === overrides[i].id);
    if (index >= 0) {
      result[index].values = cloneReaderPresetValues(overrides[i].values);
    }
  }
  const custom = parseCustomReaderPresetProfiles(customRaw);
  for (let i = 0; i < custom.length; i++) {
    result.push(custom[i]);
  }
  return result;
}

export function findReaderPresetProfile(profiles: ReaderPresetProfile[], id: string): ReaderPresetProfile | null {
  for (let i = 0; i < profiles.length; i++) {
    if (profiles[i].id === id) {
      return profiles[i];
    }
  }
  return null;
}

export function findReaderPresetByName(profiles: ReaderPresetProfile[], name: string): ReaderPresetProfile | null {
  for (let i = 0; i < profiles.length; i++) {
    if (profiles[i].name === name) {
      return profiles[i];
    }
  }
  return null;
}

export function activeReaderPresetProfile(profiles: ReaderPresetProfile[], values: ReaderPresetValues): ReaderPresetProfile | null {
  for (let i = 0; i < profiles.length; i++) {
    if (readerPresetValuesEqual(profiles[i].values, values)) {
      return profiles[i];
    }
  }
  return null;
}

export function readerPresetValuesFromSettings(): ReaderPresetValues {
  return createReaderPresetValues(
    ehSettingsStore.getValue('screen_rotation', 'Default'),
    ehSettingsStore.getValue('reading_direction', 'Right to left'),
    ehSettingsStore.getValue('page_scaling', 'Fit screen'),
    ehSettingsStore.getValue('adaptive_dual_page', 'Off') === 'On',
    ehSettingsStore.getValue('reader_crop_white_borders', 'Off') === 'On',
    ehSettingsStore.getValue('reader_image_super_resolution', 'Off') === 'On',
    ehSettingsStore.getValue('reader_super_resolution_engine', READER_SUPER_RESOLUTION_ENGINE_DETAIL),
    ehSettingsStore.getValue('reader_sdr_to_hdr', 'Off') === 'On',
    ehSettingsStore.getValue('start_position', 'Center'),
    readerImageAdjustmentSettingsFromStore()
  );
}

export function applyReaderPresetValues(values: ReaderPresetValues): void {
  // 先关闭双页约束，再写入其余字段，最后恢复目标双页状态，避免中间值被设置仓库校正。
  ehSettingsStore.setValue('adaptive_dual_page', 'Off');
  ehSettingsStore.setValue('screen_rotation', values.screenRotation);
  ehSettingsStore.setValue('reading_direction', values.readingDirection);
  ehSettingsStore.setValue('page_scaling', values.pageScaling);
  ehSettingsStore.setValue('reader_crop_white_borders', values.cropWhiteBorders ? 'On' : 'Off');
  ehSettingsStore.setValue('reader_image_super_resolution', values.imageSuperResolution ? 'On' : 'Off');
  ehSettingsStore.setValue('reader_super_resolution_engine', values.superResolutionEngine);
  ehSettingsStore.setValue('reader_sdr_to_hdr', values.sdrToHdr ? 'On' : 'Off');
  ehSettingsStore.setValue('start_position', values.startPosition);
  saveReaderImageAdjustmentSettings(values.imageAdjustment);
  ehSettingsStore.setValue('adaptive_dual_page', values.adaptiveDualPage ? 'On' : 'Off');
}

export function createCustomReaderPreset(name: string, values: ReaderPresetValues): ReaderPresetProfile {
  return {
    id: 'reader_custom_' + Date.now().toString(),
    name: name.trim(),
    summary: 'Custom reading preset',
    builtIn: false,
    values: cloneReaderPresetValues(values)
  };
}

export function saveCustomReaderPreset(raw: string, profileId: string, preferredName: string,
  values: ReaderPresetValues): ReaderPresetSaveResult {
  const result = new ReaderPresetSaveResult();
  result.raw = raw;
  const custom = cloneReaderPresetProfiles(parseCustomReaderPresetProfiles(raw));
  const overrides = parseBuiltInReaderPresetOverrides(raw);
  let targetIndex = -1;
  for (let i = 0; i < custom.length; i++) {
    if (custom[i].id === profileId) {
      targetIndex = i;
      break;
    }
  }
  const profiles = allReaderPresetProfiles(raw);
  const name = preferredName.trim();
  if (name.length === 0) {
    result.error = 'Preset name is required';
    return result;
  }
  if (isReservedReaderPresetName(name)) {
    result.error = 'Preset name is reserved';
    return result;
  }
  if (readerPresetNameExistsExcept(profiles, name, profileId)) {
    result.error = 'Preset name already exists';
    return result;
  }
  if (targetIndex >= 0) {
    custom[targetIndex].name = name;
    custom[targetIndex].values = cloneReaderPresetValues(values);
    result.profile = cloneReaderPresetProfiles([custom[targetIndex]])[0];
  } else {
    const profile = createCustomReaderPreset(name, values);
    custom.push(profile);
    result.profile = cloneReaderPresetProfiles([profile])[0];
  }
  result.raw = serializeStoredReaderPresetProfiles(custom, overrides);
  return result;
}

export function saveReaderPreset(raw: string, profileId: string, preferredName: string,
  values: ReaderPresetValues): ReaderPresetSaveResult {
  const builtIn = findReaderPresetProfile(BUILT_IN_READER_PRESETS, profileId);
  if (builtIn === null) {
    return saveCustomReaderPreset(raw, profileId, preferredName, values);
  }
  const result = new ReaderPresetSaveResult();
  const custom = cloneReaderPresetProfiles(parseCustomReaderPresetProfiles(raw));
  const overrides = parseBuiltInReaderPresetOverrides(raw);
  let targetIndex = overrides.findIndex((profile: ReaderPresetProfile) => profile.id === profileId);
  const updated: ReaderPresetProfile = {
    id: builtIn.id,
    name: builtIn.name,
    summary: builtIn.summary,
    builtIn: true,
    values: cloneReaderPresetValues(values)
  };
  if (targetIndex >= 0) {
    overrides[targetIndex] = updated;
  } else {
    overrides.push(updated);
  }
  result.raw = serializeStoredReaderPresetProfiles(custom, overrides);
  result.profile = cloneReaderPresetProfiles([updated])[0];
  return result;
}

export function deleteCustomReaderPreset(raw: string, profileId: string): string {
  const custom = cloneReaderPresetProfiles(parseCustomReaderPresetProfiles(raw));
  const overrides = parseBuiltInReaderPresetOverrides(raw);
  for (let i = custom.length - 1; i >= 0; i--) {
    if (custom[i].id === profileId) {
      custom.splice(i, 1);
    }
  }
  return serializeStoredReaderPresetProfiles(custom, overrides);
}

export function cloneReaderPresetProfiles(profiles: ReaderPresetProfile[]): ReaderPresetProfile[] {
  const result: ReaderPresetProfile[] = [];
  for (let i = 0; i < profiles.length; i++) {
    result.push({
      id: profiles[i].id,
      name: profiles[i].name,
      summary: profiles[i].summary,
      builtIn: profiles[i].builtIn,
      values: cloneReaderPresetValues(profiles[i].values)
    });
  }
  return result;
}

export function cloneReaderPresetValues(values: ReaderPresetValues): ReaderPresetValues {
  return createReaderPresetValues(values.screenRotation, values.readingDirection, values.pageScaling,
    values.adaptiveDualPage, values.cropWhiteBorders, values.imageSuperResolution, values.superResolutionEngine,
    values.sdrToHdr,
    values.startPosition, values.imageAdjustment);
}

export function createReaderPresetValues(screenRotation: string, readingDirection: string, pageScaling: string,
  adaptiveDualPage: boolean, cropWhiteBorders: boolean, imageSuperResolution: boolean,
  superResolutionEngine: string, sdrToHdr: boolean, startPosition: string,
  imageAdjustment: ReaderImageAdjustmentSettings = new ReaderImageAdjustmentSettings()): ReaderPresetValues {
  return {
    screenRotation: normalizeOption(screenRotation, ['Default', 'Portrait', 'Landscape', 'Auto rotate', 'Match image'], 'Default'),
    readingDirection: normalizeOption(readingDirection, ['Left to right', 'Right to left', 'Top to bottom'], 'Right to left'),
    pageScaling: normalizeOption(pageScaling, ['Actual size', 'Fit width', 'Fit height', 'Fit screen', 'Fixed scale'], 'Fit screen'),
    adaptiveDualPage: adaptiveDualPage,
    cropWhiteBorders: cropWhiteBorders,
    imageSuperResolution: imageSuperResolution,
    superResolutionEngine: normalizeReaderSuperResolutionEngine(superResolutionEngine),
    sdrToHdr: sdrToHdr,
    startPosition: normalizeOption(startPosition, ['Top left', 'Top right', 'Bottom left', 'Bottom right', 'Center'], 'Center'),
    imageAdjustment: cloneReaderImageAdjustmentSettings(imageAdjustment)
  };
}

function parseStoredReaderPresetValues(value: StoredReaderPresetValues | undefined): ReaderPresetValues | null {
  if (value === undefined || typeof value !== 'object') {
    return null;
  }
  return createReaderPresetValues(
    typeof value.screenRotation === 'string' ? value.screenRotation : 'Default',
    typeof value.readingDirection === 'string' ? value.readingDirection : 'Right to left',
    typeof value.pageScaling === 'string' ? value.pageScaling : 'Fit screen',
    value.adaptiveDualPage === true,
    value.cropWhiteBorders === true,
    value.imageSuperResolution === true,
    typeof value.superResolutionEngine === 'string' ? value.superResolutionEngine :
      READER_SUPER_RESOLUTION_ENGINE_DETAIL,
    value.sdrToHdr === true,
    typeof value.startPosition === 'string' ? value.startPosition : 'Center',
    parseStoredImageAdjustment(value.imageAdjustment)
  );
}

function readerPresetValuesEqual(left: ReaderPresetValues, right: ReaderPresetValues): boolean {
  return left.screenRotation === right.screenRotation && left.readingDirection === right.readingDirection &&
    left.pageScaling === right.pageScaling && left.adaptiveDualPage === right.adaptiveDualPage &&
    left.cropWhiteBorders === right.cropWhiteBorders &&
    left.imageSuperResolution === right.imageSuperResolution &&
    left.superResolutionEngine === right.superResolutionEngine && left.sdrToHdr === right.sdrToHdr &&
    left.startPosition === right.startPosition &&
    left.imageAdjustment.cacheKey() === right.imageAdjustment.cacheKey();
}

function readerPresetNameExists(profiles: ReaderPresetProfile[], name: string): boolean {
  return readerPresetNameExistsExcept(profiles, name, '');
}

function readerPresetNameExistsExcept(profiles: ReaderPresetProfile[], name: string, excludedId: string): boolean {
  const normalized = name.trim().toLowerCase();
  for (let i = 0; i < profiles.length; i++) {
    if (profiles[i].id !== excludedId && profiles[i].name.trim().toLowerCase() === normalized) {
      return true;
    }
  }
  return false;
}

function parseStoredReaderPresetProfiles(raw: string): StoredReaderPresetProfile[] {
  if (raw.trim().length === 0) {
    return [];
  }
  try {
    const parsed = JSON.parse(raw) as StoredReaderPresetProfile[];
    return Array.isArray(parsed) ? parsed : [];
  } catch (_error) {
    return [];
  }
}

function parseBuiltInReaderPresetOverrides(raw: string): ReaderPresetProfile[] {
  const result: ReaderPresetProfile[] = [];
  const parsed = parseStoredReaderPresetProfiles(raw);
  for (let i = 0; i < parsed.length; i++) {
    const id = typeof parsed[i].id === 'string' ? (parsed[i].id as string).trim() : '';
    const builtIn = findReaderPresetProfile(BUILT_IN_READER_PRESETS, id);
    const values = parseStoredReaderPresetValues(parsed[i].values);
    if (parsed[i].builtIn === true && builtIn !== null && values !== null &&
      findReaderPresetProfile(result, id) === null) {
      result.push({ id: builtIn.id, name: builtIn.name, summary: builtIn.summary, builtIn: true, values: values });
    }
  }
  return result;
}

function storedReaderPresetValues(values: ReaderPresetValues): StoredReaderPresetValues {
  return {
    screenRotation: values.screenRotation,
    readingDirection: values.readingDirection,
    pageScaling: values.pageScaling,
    adaptiveDualPage: values.adaptiveDualPage,
    cropWhiteBorders: values.cropWhiteBorders,
    imageSuperResolution: values.imageSuperResolution,
    superResolutionEngine: values.superResolutionEngine,
    sdrToHdr: values.sdrToHdr,
    startPosition: values.startPosition,
    imageAdjustment: cloneReaderImageAdjustmentSettings(values.imageAdjustment)
  };
}

function parseStoredImageAdjustment(value: ReaderImageAdjustmentSettings | undefined): ReaderImageAdjustmentSettings {
  if (value === undefined || typeof value !== 'object') {
    return new ReaderImageAdjustmentSettings();
  }
  const result = new ReaderImageAdjustmentSettings();
  result.enabled = value.enabled === true;
  result.moireReduction = normalizeReaderMoireReduction(
    typeof value.moireReduction === 'string' ? value.moireReduction : 'Off');
  result.contrast = storedNumber(value.contrast, -100, 100);
  result.clarity = storedNumber(value.clarity, 0, 100);
  result.sharpening = storedNumber(value.sharpening, 0, 100);
  result.exposure = storedNumber(value.exposure, -100, 100);
  result.brightness = storedNumber(value.brightness, -100, 100);
  result.highlights = storedNumber(value.highlights, -100, 100);
  result.shadows = storedNumber(value.shadows, -100, 100);
  result.hue = storedNumber(value.hue, -180, 180);
  result.saturation = storedNumber(value.saturation, -100, 100);
  result.vibrance = storedNumber(value.vibrance, -100, 100);
  result.temperature = storedNumber(value.temperature, -100, 100);
  result.grayscale = storedNumber(value.grayscale, 0, 100);
  return result;
}

function storedNumber(value: number, min: number, max: number): number {
  return typeof value === 'number' && !Number.isNaN(value) ? Math.max(min, Math.min(max, Math.round(value))) : 0;
}

function isBuiltInReaderPresetId(id: string): boolean {
  return findReaderPresetProfile(BUILT_IN_READER_PRESETS, id) !== null;
}

function isReservedReaderPresetName(name: string): boolean {
  return name.trim().toLowerCase() === 'current settings';
}

function normalizeOption(value: string, options: string[], fallback: string): string {
  return options.indexOf(value) >= 0 ? value : fallback;
}
