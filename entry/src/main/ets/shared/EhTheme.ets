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

export function themeSelectedText(): string {
  return currentThemePalette().selectedText;
}

export function themeSelectedIndicatorColor(): string {
  return currentThemePalette().selectedIndicator;
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
  return currentThemePalette().downloadStateActive;
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
