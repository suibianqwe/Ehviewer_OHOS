import { ehSettingsStore } from '../services/EhSettingsStore';

// Keep this file limited to theme color palettes and color accessors only.
// Component styles, modifiers, and window/UI behavior belong in focused helper files.
export const EH_THEME_PRIMARY_COLOR: string = '#2F6F8F';

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
  scrim: string;
}

const LIGHT_PALETTE: EhColorPalette = {
  name: 'Light',
  primary: EH_THEME_PRIMARY_COLOR,
  pageBackground: '#F3F5F7',
  surface: '#FFFFFF',
  surfaceVariant: '#F0F4F7',
  fieldBackground: '#DCECF3',
  primaryText: '#17202A',
  secondaryText: '#667085',
  tertiaryText: '#98A2B3',
  mutedText: '#95A1B0',
  divider: '#E8EDF2',
  placeholder: '#9BB8CB',
  selectedBackground: '#D6EBF5',
  selectedBackgroundLight: '#EAF4FA',
  scrim: 'rgba(0,0,0,0.18)'
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
  selectedBackground: '#244354',
  selectedBackgroundLight: '#1C3441',
  scrim: 'rgba(0,0,0,0.32)'
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
  selectedBackground: '#17313F',
  selectedBackgroundLight: '#101F27',
  scrim: 'rgba(0,0,0,0.42)'
};

export function currentThemeName(): string {
  return ehSettingsStore.getValue('theme', 'Light');
}

export function currentThemePalette(): EhColorPalette {
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
  return currentThemePalette().primary;
}

export function themeSurface(): string {
  return currentThemePalette().surface;
}

export function themeSurfaceVariant(): string {
  return currentThemePalette().surfaceVariant;
}

export function themeFieldBackground(): string {
  return currentThemePalette().fieldBackground;
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
  return currentThemePalette().selectedBackground;
}

export function themeSelectedBackgroundLight(): string {
  return currentThemePalette().selectedBackgroundLight;
}

export function themeScrimColor(): string {
  return currentThemePalette().scrim;
}
