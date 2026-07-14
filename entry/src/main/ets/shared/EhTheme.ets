import { ehSettingsStore } from '../services/EhSettingsStore';

// Keep this file limited to theme color palettes and color accessors only.
// Component styles, modifiers, and window/UI behavior belong in focused helper files.
export const EH_THEME_PRIMARY_COLOR: string = '#2F6F8F';
export const EH_SYSTEM_COLOR_MODE_KEY: string = 'ehviewer_system_color_mode';
export const EH_SYSTEM_COLOR_MODE_DARK: number = 1;

export interface EhColorPalette {
  name: string;
  primary: string;
  pageBackground: string;
  surface: string;
  surfaceVariant: string;
  fieldBackground: string;
  primaryText: string;
  secondaryText: string;
  tertiaryText: string;
  mutedText: string;
  divider: string;
  placeholder: string;
  selectedBackground: string;
  selectedBackgroundLight: string;
  selectedText: string;
  selectedIndicator: string;
  scrim: string;
  shadow: string;
  systemBarContent: string;
  onPrimary: string;
  onPrimarySecondary: string;
  onPrimaryActionBackground: string;
  onPrimaryActionBackgroundStrong: string;
  onPrimaryActionBackgroundDisabled: string;
  onPrimaryDangerBackground: string;
  successText: string;
  successBackground: string;
  dangerText: string;
  dangerBackground: string;
  infoText: string;
  infoBackground: string;
  accentBackground: string;
  onAccent: string;
  favoriteText: string;
  inactiveActionText: string;
  controlNeutralBackground: string;
  controlMutedBackground: string;
  transparent: string;
  downloadStateWait: string;
  downloadStateActive: string;
  downloadStateDone: string;
  downloadStateFailed: string;
  downloadStateIdle: string;
  readerSelectText: string;
  readerSelectBackground: string;
  readerSelectPanel: string;
  readerSelectSelectedBackground: string;
  readerSelectSelectedText: string;
  readerSelectOutline: string;
}

const LIGHT_PALETTE: EhColorPalette = {
  name: 'Light',
  primary: EH_THEME_PRIMARY_COLOR,
  pageBackground: '#F3F5F7',
  surface: '#FFFFFF',
  surfaceVariant: '#F0F4F7',
  fieldBackground: '#EAF4F8',
  primaryText: '#17202A',
  secondaryText: '#667085',
  tertiaryText: '#98A2B3',
  mutedText: '#95A1B0',
  divider: '#E8EDF2',
  placeholder: '#9BB8CB',
  selectedBackground: '#B7DCEB',
  selectedBackgroundLight: '#D3ECF5',
  selectedText: '#174B62',
  selectedIndicator: EH_THEME_PRIMARY_COLOR,
  scrim: 'rgba(0,0,0,0.18)',
  shadow: '#55000000',
  systemBarContent: '#17202A',
  onPrimary: '#FFFFFF',
  onPrimarySecondary: 'rgba(255,255,255,0.72)',
  onPrimaryActionBackground: 'rgba(255,255,255,0.14)',
  onPrimaryActionBackgroundStrong: 'rgba(255,255,255,0.25)',
  onPrimaryActionBackgroundDisabled: 'rgba(255,255,255,0.10)',
  onPrimaryDangerBackground: 'rgba(220,60,50,0.75)',
  successText: '#0A6B45',
  successBackground: '#F0FBF6',
  dangerText: '#B42318',
  dangerBackground: '#FDECEC',
  infoText: '#40566F',
  infoBackground: '#EEF6FA',
  accentBackground: '#F7C948',
  onAccent: '#17202A',
  favoriteText: '#E05C4B',
  inactiveActionText: '#B8CDD8',
  controlNeutralBackground: '#667085',
  controlMutedBackground: '#475467',
  transparent: '#00000000',
  downloadStateWait: '#5A8FA8',
  downloadStateActive: EH_THEME_PRIMARY_COLOR,
  downloadStateDone: '#0A6B45',
  downloadStateFailed: '#B42318',
  downloadStateIdle: '#667085',
  readerSelectText: '#E5E7EB',
  readerSelectBackground: '#1F2937',
  readerSelectPanel: '#111827',
  readerSelectSelectedBackground: '#374151',
  readerSelectSelectedText: '#F9FAFB',
  readerSelectOutline: '#4B5563'
};

const DARK_PALETTE: EhColorPalette = {
  name: 'Dark',
  primary: '#24586F',
  pageBackground: '#101820',
  surface: '#18232D',
  surfaceVariant: '#22303B',
  fieldBackground: '#263642',
  primaryText: '#F2F5F7',
  secondaryText: '#B8C4CC',
  tertiaryText: '#8FA0AB',
  mutedText: '#7D8C96',
  divider: '#2B3A45',
  placeholder: '#6F8490',
  selectedBackground: '#1D3542',
  selectedBackgroundLight: '#24495C',
  selectedText: '#D8F3FF',
  selectedIndicator: '#8ED8F0',
  scrim: 'rgba(0,0,0,0.32)',
  shadow: 'rgba(0,0,0,0.55)',
  systemBarContent: '#F2F5F7',
  onPrimary: '#F2F5F7',
  onPrimarySecondary: 'rgba(242,245,247,0.76)',
  onPrimaryActionBackground: 'rgba(255,255,255,0.16)',
  onPrimaryActionBackgroundStrong: 'rgba(255,255,255,0.28)',
  onPrimaryActionBackgroundDisabled: 'rgba(255,255,255,0.10)',
  onPrimaryDangerBackground: 'rgba(190,58,48,0.78)',
  successText: '#8FE6B8',
  successBackground: '#123326',
  dangerText: '#FFB4AB',
  dangerBackground: '#3A1717',
  infoText: '#B8C4CC',
  infoBackground: '#22303B',
  accentBackground: '#F4C84E',
  onAccent: '#17202A',
  favoriteText: '#FF8A7A',
  inactiveActionText: '#6F8490',
  controlNeutralBackground: '#667085',
  controlMutedBackground: '#475467',
  transparent: '#00000000',
  downloadStateWait: '#6EA7C0',
  downloadStateActive: '#75C4E0',
  downloadStateDone: '#31B47B',
  downloadStateFailed: '#D97066',
  downloadStateIdle: '#8FA0AB',
  readerSelectText: '#E5E7EB',
  readerSelectBackground: '#1F2937',
  readerSelectPanel: '#111827',
  readerSelectSelectedBackground: '#374151',
  readerSelectSelectedText: '#F9FAFB',
  readerSelectOutline: '#4B5563'
};

const BLACK_PALETTE: EhColorPalette = {
  name: 'Black',
  primary: '#173E50',
  pageBackground: '#000000',
  surface: '#070707',
  surfaceVariant: '#111111',
  fieldBackground: '#151515',
  primaryText: '#F7F7F7',
  secondaryText: '#C7CDD1',
  tertiaryText: '#8A949B',
  mutedText: '#747D84',
  divider: '#222222',
  placeholder: '#666666',
  selectedBackground: '#0C2029',
  selectedBackgroundLight: '#102D3A',
  selectedText: '#E7F8FF',
  selectedIndicator: '#A4E7FF',
  scrim: 'rgba(0,0,0,0.42)',
  shadow: 'rgba(0,0,0,0.72)',
  systemBarContent: '#F7F7F7',
  onPrimary: '#F7F7F7',
  onPrimarySecondary: 'rgba(247,247,247,0.74)',
  onPrimaryActionBackground: 'rgba(255,255,255,0.15)',
  onPrimaryActionBackgroundStrong: 'rgba(255,255,255,0.26)',
  onPrimaryActionBackgroundDisabled: 'rgba(255,255,255,0.09)',
  onPrimaryDangerBackground: 'rgba(190,58,48,0.76)',
  successText: '#98E6BD',
  successBackground: '#0B261B',
  dangerText: '#FFB4AB',
  dangerBackground: '#2A1111',
  infoText: '#C7CDD1',
  infoBackground: '#111111',
  accentBackground: '#F4C84E',
  onAccent: '#101010',
  favoriteText: '#FF8A7A',
  inactiveActionText: '#666666',
  controlNeutralBackground: '#596873',
  controlMutedBackground: '#3F4B55',
  transparent: '#00000000',
  downloadStateWait: '#6EA7C0',
  downloadStateActive: '#82D4F0',
  downloadStateDone: '#31B47B',
  downloadStateFailed: '#D97066',
  downloadStateIdle: '#87939B',
  readerSelectText: '#E5E7EB',
  readerSelectBackground: '#1F2937',
  readerSelectPanel: '#111827',
  readerSelectSelectedBackground: '#374151',
  readerSelectSelectedText: '#F9FAFB',
  readerSelectOutline: '#4B5563'
};

interface EhThemeAccent {
  name: string;
  light: string;
  dark: string;
  black: string;
  indicator: string;
}

const THEME_ACCENTS: EhThemeAccent[] = [
  { name: 'Blue', light: '#2F6F8F', dark: '#24586F', black: '#173E50', indicator: '#8ED8F0' },
  { name: 'Sky Blue', light: '#1976B8', dark: '#155A8A', black: '#0D3B5C', indicator: '#7ED2FF' },
  { name: 'Teal', light: '#287D78', dark: '#205F5B', black: '#153F3D', indicator: '#79DDD5' },
  { name: 'Green', light: '#397A48', dark: '#2E613A', black: '#1D4127', indicator: '#91DDA1' },
  { name: 'Purple', light: '#74549C', dark: '#594178', black: '#3B2B51', indicator: '#C8ABEC' },
  { name: 'Orange', light: '#A85B24', dark: '#7D461F', black: '#533016', indicator: '#F3B37D' },
  { name: 'Rose', light: '#A64D72', dark: '#7C3B57', black: '#52273B', indicator: '#EFA5C3' }
];

function normalizeThemeColorName(colorName: string): string {
  for (let i = 0; i < THEME_ACCENTS.length; i++) {
    if (THEME_ACCENTS[i].name === colorName) {
      return colorName;
    }
  }
  return 'Blue';
}

function currentThemeAccent(): EhThemeAccent {
  const colorName = normalizeThemeColorName(ehSettingsStore.getValue('theme_color', 'Blue'));
  for (let i = 0; i < THEME_ACCENTS.length; i++) {
    if (THEME_ACCENTS[i].name === colorName) {
      return THEME_ACCENTS[i];
    }
  }
  return THEME_ACCENTS[0];
}

function accentPrimaryColor(): string {
  const accent = currentThemeAccent();
  const themeName = currentThemeName();
  if (themeName === 'Black') {
    return accent.black;
  }
  if (themeName === 'Dark') {
    return accent.dark;
  }
  return accent.light;
}

function accentIndicatorColor(): string {
  return currentThemeName() === 'Light' ? currentThemeAccent().light : currentThemeAccent().indicator;
}

function colorChannel(color: string, start: number): number {
  const value = Number.parseInt(color.substring(start, start + 2), 16);
  return Number.isNaN(value) ? 0 : value;
}

function colorChannelHex(value: number): string {
  const normalized = Math.max(0, Math.min(255, Math.round(value)));
  const hex = normalized.toString(16).toUpperCase();
  return hex.length === 1 ? '0' + hex : hex;
}

function mixThemeColor(from: string, to: string, amount: number): string {
  const ratio = Math.max(0, Math.min(1, amount));
  const red = colorChannel(from, 1) + (colorChannel(to, 1) - colorChannel(from, 1)) * ratio;
  const green = colorChannel(from, 3) + (colorChannel(to, 3) - colorChannel(from, 3)) * ratio;
  const blue = colorChannel(from, 5) + (colorChannel(to, 5) - colorChannel(from, 5)) * ratio;
  return '#' + colorChannelHex(red) + colorChannelHex(green) + colorChannelHex(blue);
}

function accentFieldBackground(): string {
  const themeName = currentThemeName();
  if (themeName === 'Black') {
    return mixThemeColor(accentIndicatorColor(), BLACK_PALETTE.surface, 0.88);
  }
  if (themeName === 'Dark') {
    return mixThemeColor(accentIndicatorColor(), DARK_PALETTE.surface, 0.82);
  }
  return mixThemeColor(accentPrimaryColor(), LIGHT_PALETTE.surface, 0.90);
}

function accentSelectedBackground(lightVariant: boolean): string {
  const themeName = currentThemeName();
  if (themeName === 'Black') {
    return mixThemeColor(accentIndicatorColor(), BLACK_PALETTE.surface, lightVariant ? 0.66 : 0.78);
  }
  if (themeName === 'Dark') {
    return mixThemeColor(accentIndicatorColor(), DARK_PALETTE.surface, lightVariant ? 0.60 : 0.74);
  }
  return mixThemeColor(accentPrimaryColor(), LIGHT_PALETTE.surface, lightVariant ? 0.82 : 0.70);
}

function accentSelectedText(): string {
  if (currentThemeName() === 'Light') {
    return mixThemeColor(accentPrimaryColor(), '#000000', 0.28);
  }
  return mixThemeColor(accentIndicatorColor(), '#FFFFFF', 0.20);
}

export function currentThemeName(): string {
  const storedThemeName = normalizeThemeName(ehSettingsStore.getValue('theme', 'Light'));
  if (ehSettingsStore.getValue('follow_system_dark_mode', 'Off') !== 'On') {
    return storedThemeName;
  }
  const colorMode = AppStorage.get<number>(EH_SYSTEM_COLOR_MODE_KEY);
  if (colorMode === EH_SYSTEM_COLOR_MODE_DARK) {
    return storedThemeName === 'Black' ? 'Black' : 'Dark';
  }
  return 'Light';
}

export function currentDarkModeThemeName(): string {
  const storedThemeName = normalizeThemeName(ehSettingsStore.getValue('theme', 'Dark'));
  return storedThemeName === 'Black' ? 'Black' : 'Dark';
}

function normalizeThemeName(themeName: string): string {
  if (themeName === 'Black') {
    return 'Black';
  }
  if (themeName === 'Dark') {
    return 'Dark';
  }
  return 'Light';
}

function currentThemePalette(): EhColorPalette {
  const themeName = currentThemeName();
  if (themeName === 'Black') {
    return BLACK_PALETTE;
  }
  if (themeName === 'Dark') {
    return DARK_PALETTE;
  }
  return LIGHT_PALETTE;
}

export function isDarkTheme(): boolean {
  const themeName = currentThemeName();
  return themeName === 'Dark' || themeName === 'Black';
}

export function isBlackTheme(): boolean {
  return currentThemeName() === 'Black';
}

export function themePageBackground(): string {
  return currentThemePalette().pageBackground;
}

export function themePrimaryColor(): string {
  return accentPrimaryColor();
}

export function themeDetailActionColor(): string {
  return isDarkTheme() ? accentIndicatorColor() : accentPrimaryColor();
}

export function themeSurface(): string {
  return currentThemePalette().surface;
}

export function themeSurfaceVariant(): string {
  return currentThemePalette().surfaceVariant;
}

export function themeFieldBackground(): string {
  return accentFieldBackground();
}

export function themePrimaryText(): string {
  return currentThemePalette().primaryText;
}

export function themeSecondaryText(): string {
  return currentThemePalette().secondaryText;
}

export function themeTertiaryText(): string {
  return currentThemePalette().tertiaryText;
}

export function themeMutedText(): string {
  return currentThemePalette().mutedText;
}

export function themeDividerColor(): string {
  return currentThemePalette().divider;
}

export function themePlaceholderColor(): string {
  return currentThemePalette().placeholder;
}

export function themeSelectedBackground(): string {
  return accentSelectedBackground(false);
}

export function themeSelectedBackgroundLight(): string {
  return accentSelectedBackground(true);
}

export function themeSelectedText(): string {
  return accentSelectedText();
}

export function themeSelectedIndicatorColor(): string {
  return accentIndicatorColor();
}

export function themeScrimColor(): string {
  return currentThemePalette().scrim;
}

export function themeShadowColor(): string {
  return currentThemePalette().shadow;
}

export function themeSystemBarContentColor(): string {
  return currentThemePalette().systemBarContent;
}

export function themeOnPrimaryText(): string {
  return currentThemePalette().onPrimary;
}

export function themeOnPrimarySecondaryText(): string {
  return currentThemePalette().onPrimarySecondary;
}

export function themeOnPrimaryActionBackground(): string {
  return currentThemePalette().onPrimaryActionBackground;
}

export function themeOnPrimaryActionStrongBackground(): string {
  return currentThemePalette().onPrimaryActionBackgroundStrong;
}

export function themeOnPrimaryActionDisabledBackground(): string {
  return currentThemePalette().onPrimaryActionBackgroundDisabled;
}

export function themeOnPrimaryDangerBackground(): string {
  return currentThemePalette().onPrimaryDangerBackground;
}

export function themeSuccessText(): string {
  return currentThemePalette().successText;
}

export function themeSuccessBackground(): string {
  return currentThemePalette().successBackground;
}

export function themeDangerText(): string {
  return currentThemePalette().dangerText;
}

export function themeDangerBackground(): string {
  return currentThemePalette().dangerBackground;
}

export function themeInfoText(): string {
  return currentThemePalette().infoText;
}

export function themeInfoBackground(): string {
  return currentThemePalette().infoBackground;
}

export function themeAccentBackground(): string {
  return currentThemePalette().accentBackground;
}

export function themeOnAccentText(): string {
  return currentThemePalette().onAccent;
}

export function themeFavoriteText(): string {
  return currentThemePalette().favoriteText;
}

export function themeInactiveActionText(): string {
  return currentThemePalette().inactiveActionText;
}

export function themeControlNeutralBackground(): string {
  return currentThemePalette().controlNeutralBackground;
}

export function themeControlMutedBackground(): string {
  return currentThemePalette().controlMutedBackground;
}

export function themeTransparentColor(): string {
  return currentThemePalette().transparent;
}

export function themeDownloadStateWaitColor(): string {
  return currentThemePalette().downloadStateWait;
}

export function themeDownloadStateActiveColor(): string {
  return isDarkTheme() ? accentIndicatorColor() : accentPrimaryColor();
}

export function themeDownloadStateDoneColor(): string {
  return currentThemePalette().downloadStateDone;
}

export function themeDownloadStateFailedColor(): string {
  return currentThemePalette().downloadStateFailed;
}

export function themeDownloadStateIdleColor(): string {
  return currentThemePalette().downloadStateIdle;
}

export function themeReaderSelectText(): string {
  return currentThemePalette().readerSelectText;
}

export function themeReaderSelectBackground(): string {
  return currentThemePalette().readerSelectBackground;
}

export function themeReaderSelectPanel(): string {
  return currentThemePalette().readerSelectPanel;
}

export function themeReaderSelectSelectedBackground(): string {
  return currentThemePalette().readerSelectSelectedBackground;
}

export function themeReaderSelectSelectedText(): string {
  return currentThemePalette().readerSelectSelectedText;
}

export function themeReaderSelectOutline(): string {
  return currentThemePalette().readerSelectOutline;
}
