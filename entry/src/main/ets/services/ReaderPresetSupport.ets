import { ehSettingsStore } from './EhSettingsStore';

export const READER_CUSTOM_PRESETS_SETTING_KEY: string = 'reader_custom_presets';

export interface ReaderPresetValues {
  screenRotation: string;
  readingDirection: string;
  pageScaling: string;
  adaptiveDualPage: boolean;
  cropWhiteBorders: boolean;
  sdrToHdr: boolean;
  startPosition: string;
}

export interface ReaderPresetProfile {
  id: string;
  name: string;
  summary: string;
  builtIn: boolean;
  values: ReaderPresetValues;
}

interface StoredReaderPresetValues {
  screenRotation?: string;
  readingDirection?: string;
  pageScaling?: string;
  adaptiveDualPage?: boolean;
  cropWhiteBorders?: boolean;
  sdrToHdr?: boolean;
  startPosition?: string;
}

interface StoredReaderPresetProfile {
  id?: string;
  name?: string;
  values?: StoredReaderPresetValues;
}

const BUILT_IN_READER_PRESETS: ReaderPresetProfile[] = [
  {
    id: 'reader_preset_manga',
    name: 'Manga',
    summary: 'Right-to-left single-page reading with screen fitting',
    builtIn: true,
    values: createReaderPresetValues('Default', 'Right to left', 'Fit screen', false, false, false, 'Top right')
  },
  {
    id: 'reader_preset_dual_manga',
    name: 'Dual-page manga',
    summary: 'Right-to-left reading with adaptive dual-page layout',
    builtIn: true,
    values: createReaderPresetValues('Default', 'Right to left', 'Fit screen', true, true, false, 'Top right')
  },
  {
    id: 'reader_preset_comic',
    name: 'Left-to-right comics',
    summary: 'Left-to-right single-page reading with screen fitting',
    builtIn: true,
    values: createReaderPresetValues('Default', 'Left to right', 'Fit screen', false, false, false, 'Top left')
  },
  {
    id: 'reader_preset_webtoon',
    name: 'Webtoon',
    summary: 'Continuous top-to-bottom reading fitted to screen width',
    builtIn: true,
    values: createReaderPresetValues('Default', 'Top to bottom', 'Fit width', false, false, false, 'Top left')
  }
];

export function builtInReaderPresetProfiles(): ReaderPresetProfile[] {
  return cloneReaderPresetProfiles(BUILT_IN_READER_PRESETS);
}

export function parseCustomReaderPresetProfiles(raw: string): ReaderPresetProfile[] {
  const result: ReaderPresetProfile[] = [];
  if (raw.trim().length === 0) {
    return result;
  }
  try {
    const parsed = JSON.parse(raw) as StoredReaderPresetProfile[];
    if (!Array.isArray(parsed)) {
      return result;
    }
    for (let i = 0; i < parsed.length; i++) {
      const id = typeof parsed[i].id === 'string' ? (parsed[i].id as string).trim() : '';
      const name = typeof parsed[i].name === 'string' ? (parsed[i].name as string).trim() : '';
      const values = parseStoredReaderPresetValues(parsed[i].values);
      if (id.length > 0 && name.length > 0 && values !== null && findReaderPresetProfile(result, id) === null) {
        result.push({ id: id, name: name, summary: 'Custom reading preset', builtIn: false, values: values });
      }
    }
  } catch (error) {
  }
  return result;
}

export function serializeCustomReaderPresetProfiles(profiles: ReaderPresetProfile[]): string {
  const result: StoredReaderPresetProfile[] = [];
  for (let i = 0; i < profiles.length; i++) {
    const profile = profiles[i];
    if (profile.builtIn || profile.id.trim().length === 0 || profile.name.trim().length === 0) {
      continue;
    }
    const values: StoredReaderPresetValues = {
      screenRotation: profile.values.screenRotation,
      readingDirection: profile.values.readingDirection,
      pageScaling: profile.values.pageScaling,
      adaptiveDualPage: profile.values.adaptiveDualPage,
      cropWhiteBorders: profile.values.cropWhiteBorders,
      sdrToHdr: profile.values.sdrToHdr,
      startPosition: profile.values.startPosition
    };
    result.push({ id: profile.id, name: profile.name.trim(), values: values });
  }
  return JSON.stringify(result);
}

export function allReaderPresetProfiles(customRaw: string): ReaderPresetProfile[] {
  const result = builtInReaderPresetProfiles();
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
    ehSettingsStore.getValue('reader_sdr_to_hdr', 'Off') === 'On',
    ehSettingsStore.getValue('start_position', 'Top right')
  );
}

export function applyReaderPresetValues(values: ReaderPresetValues): void {
  // 先关闭双页约束，再写入其余字段，最后恢复目标双页状态，避免中间值被设置仓库校正。
  ehSettingsStore.setValue('adaptive_dual_page', 'Off');
  ehSettingsStore.setValue('screen_rotation', values.screenRotation);
  ehSettingsStore.setValue('reading_direction', values.readingDirection);
  ehSettingsStore.setValue('page_scaling', values.pageScaling);
  ehSettingsStore.setValue('reader_crop_white_borders', values.cropWhiteBorders ? 'On' : 'Off');
  ehSettingsStore.setValue('reader_sdr_to_hdr', values.sdrToHdr ? 'On' : 'Off');
  ehSettingsStore.setValue('start_position', values.startPosition);
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

export function uniqueReaderPresetName(profiles: ReaderPresetProfile[], preferred: string): string {
  const base = preferred.trim().length > 0 ? preferred.trim() : 'Custom preset';
  let candidate = base;
  let suffix = 2;
  while (readerPresetNameExists(profiles, candidate)) {
    candidate = base + ' ' + suffix.toString();
    suffix++;
  }
  return candidate;
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
    values.adaptiveDualPage, values.cropWhiteBorders, values.sdrToHdr, values.startPosition);
}

export function createReaderPresetValues(screenRotation: string, readingDirection: string, pageScaling: string,
  adaptiveDualPage: boolean, cropWhiteBorders: boolean, sdrToHdr: boolean,
  startPosition: string): ReaderPresetValues {
  return {
    screenRotation: normalizeOption(screenRotation, ['Default', 'Portrait', 'Landscape', 'Auto rotate', 'Match image'], 'Default'),
    readingDirection: normalizeOption(readingDirection, ['Left to right', 'Right to left', 'Top to bottom'], 'Right to left'),
    pageScaling: normalizeOption(pageScaling, ['Actual size', 'Fit width', 'Fit height', 'Fit screen', 'Fixed scale'], 'Fit screen'),
    adaptiveDualPage: adaptiveDualPage,
    cropWhiteBorders: cropWhiteBorders,
    sdrToHdr: sdrToHdr,
    startPosition: normalizeOption(startPosition, ['Top left', 'Top right', 'Bottom left', 'Bottom right', 'Center'], 'Top right')
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
    value.sdrToHdr === true,
    typeof value.startPosition === 'string' ? value.startPosition : 'Top right'
  );
}

function readerPresetValuesEqual(left: ReaderPresetValues, right: ReaderPresetValues): boolean {
  return left.screenRotation === right.screenRotation && left.readingDirection === right.readingDirection &&
    left.pageScaling === right.pageScaling && left.adaptiveDualPage === right.adaptiveDualPage &&
    left.cropWhiteBorders === right.cropWhiteBorders && left.sdrToHdr === right.sdrToHdr &&
    left.startPosition === right.startPosition;
}

function readerPresetNameExists(profiles: ReaderPresetProfile[], name: string): boolean {
  for (let i = 0; i < profiles.length; i++) {
    if (profiles[i].name === name) {
      return true;
    }
  }
  return false;
}

function normalizeOption(value: string, options: string[], fallback: string): string {
  return options.indexOf(value) >= 0 ? value : fallback;
}
