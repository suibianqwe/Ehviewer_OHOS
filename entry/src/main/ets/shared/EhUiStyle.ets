import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ehSettingsStore } from '../services/EhSettingsStore';
import {
  isDarkTheme,
  themeMaterialContentColor,
  themeMaterialSecondaryContentColor
} from './EhTheme';

export const EH_UI_STYLE_CLASSIC: string = 'Classic';
export const EH_UI_STYLE_HARMONY: string = 'Harmony';
const EH_UI_STYLE_HARMONY_LEGACY: string = 'HarmonyOS 7';

let harmony7FloatingMaterial: uiMaterial.Material | undefined;
let harmony7ButtonMaterial: uiMaterial.Material | undefined;
let harmony7ChromeMaterial: uiMaterial.Material | undefined;
let harmony7SearchMaterial: uiMaterial.Material | undefined;
let harmony7SegmentMaterial: uiMaterial.Material | undefined;
let harmony7PanelMaterial: uiMaterial.Material | undefined;
let harmony7DialogMaterial: uiMaterial.Material | undefined;

function supportsImmersiveMaterial(): boolean {
  return deviceInfo.apiAvailable('26.0.0');
}

function supportsBackgroundBlur(): boolean {
  return deviceInfo.apiAvailable(9);
}

function supportsBackgroundEffect(): boolean {
  return deviceInfo.apiAvailable(11);
}

export function isHarmonyMaterialEnabled(): boolean {
  return isHarmonyUiStyle() && supportsImmersiveMaterial();
}

export function normalizeUiStyleName(value: string): string {
  return value === EH_UI_STYLE_HARMONY || value === EH_UI_STYLE_HARMONY_LEGACY ?
    EH_UI_STYLE_HARMONY : EH_UI_STYLE_CLASSIC;
}

export function currentUiStyleName(): string {
  return normalizeUiStyleName(ehSettingsStore.getValue('ui_style', EH_UI_STYLE_CLASSIC));
}

export function isHarmonyUiStyle(): boolean {
  return currentUiStyleName() === EH_UI_STYLE_HARMONY;
}

export function uiControlRadius(classicRadius: number = 6): number {
  return Math.max(12, classicRadius);
}

export function uiCardRadius(classicRadius: number = 8): number {
  return Math.max(16, classicRadius);
}

export function uiPanelRadius(classicRadius: number = 12): number {
  return Math.max(24, classicRadius);
}

export function uiPillRadius(classicRadius: number = 18): number {
  return Math.max(22, classicRadius);
}

export function uiRadius(classicRadius: number): number {
  if (classicRadius >= 18) {
    return uiPillRadius(classicRadius);
  }
  if (classicRadius >= 8) {
    return uiCardRadius(classicRadius);
  }
  return uiControlRadius(classicRadius);
}

export function uiFloatingMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyMaterialEnabled()) {
    return undefined;
  }
  if (harmony7FloatingMaterial === undefined) {
    harmony7FloatingMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      applyShadow: true,
      interactive: false,
      lightEffect: { color: undefined }
    });
  }
  return harmony7FloatingMaterial;
}

export function uiButtonMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyMaterialEnabled()) {
    return undefined;
  }
  if (harmony7ButtonMaterial === undefined) {
    harmony7ButtonMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      applyShadow: true,
      interactive: true,
      lightEffect: { color: Color.White }
    });
  }
  return harmony7ButtonMaterial;
}

export function uiChromeMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyMaterialEnabled()) {
    return undefined;
  }
  if (harmony7ChromeMaterial === undefined) {
    harmony7ChromeMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      applyShadow: false,
      interactive: false
    });
  }
  return harmony7ChromeMaterial;
}

export function uiSearchMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyMaterialEnabled()) {
    return undefined;
  }
  if (harmony7SearchMaterial === undefined) {
    harmony7SearchMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      applyShadow: true,
      interactive: true,
      lightEffect: { color: Color.White }
    });
  }
  return harmony7SearchMaterial;
}

export function uiSegmentMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyMaterialEnabled()) {
    return undefined;
  }
  if (harmony7SegmentMaterial === undefined) {
    harmony7SegmentMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: Color.White }
    });
  }
  return harmony7SegmentMaterial;
}

export function uiMaterialBackground(solidColor: string): string {
  return isHarmonyMaterialEnabled() ? 'rgba(0,0,0,0)' : solidColor;
}

export function uiMaterialForegroundColor(fallbackColor: ResourceColor): ResourceColor {
  return isHarmonyMaterialEnabled() ? themeMaterialContentColor() : fallbackColor;
}

export function uiMaterialSecondaryForegroundColor(fallbackColor: ResourceColor): ResourceColor {
  return isHarmonyMaterialEnabled() ? themeMaterialSecondaryContentColor() : fallbackColor;
}

export function uiTitleBarBlurStyle(): BlurStyle {
  return isHarmonyUiStyle() && supportsBackgroundBlur() ? BlurStyle.COMPONENT_ULTRA_THIN : BlurStyle.NONE;
}

export function uiTitleBarBackgroundEffect(): BackgroundEffectOptions {
  return {
    radius: isHarmonyUiStyle() && supportsBackgroundEffect() ? 8 : 0,
    saturation: 1,
    brightness: 1,
    color: Color.Transparent,
    adaptiveColor: AdaptiveColor.DEFAULT
  };
}

export function uiTitleBarFadeHeight(): number {
  return isHarmonyUiStyle() ? 36 : 8;
}

export function uiTitleBarFadeStartColor(): string {
  if (!isHarmonyUiStyle()) {
    return 'rgba(0,0,0,0)';
  }
  return isDarkTheme() ? 'rgba(12,13,16,0.16)' : 'rgba(248,249,252,0.16)';
}

export function uiTitleBarFadeMiddleColor(): string {
  return isDarkTheme() ? 'rgba(12,13,16,0.10)' : 'rgba(248,249,252,0.10)';
}

export function uiTitleBarFadeTailColor(): string {
  return isDarkTheme() ? 'rgba(12,13,16,0.03)' : 'rgba(248,249,252,0.03)';
}

export function uiReaderMenuBackgroundEffect(): BackgroundEffectOptions {
  const effectEnabled = isHarmonyUiStyle() && supportsBackgroundEffect();
  return {
    radius: effectEnabled ? 10 : 0,
    saturation: 1.04,
    brightness: 0.98,
    color: effectEnabled ? 'rgba(11,16,25,0.18)' : Color.Transparent,
    adaptiveColor: AdaptiveColor.DEFAULT
  };
}

export function uiReaderProgressBackgroundEffect(): BackgroundEffectOptions {
  const effectEnabled = isHarmonyUiStyle() && supportsBackgroundEffect();
  return {
    radius: effectEnabled ? 18 : 0,
    saturation: effectEnabled ? 1.08 : 1,
    brightness: effectEnabled ? 0.92 : 1,
    color: effectEnabled ? 'rgba(11,16,25,0.22)' : Color.Transparent,
    adaptiveColor: AdaptiveColor.DEFAULT
  };
}

export function uiReaderProgressBackgroundColor(fallbackColor: string): string {
  return isHarmonyUiStyle() && supportsBackgroundEffect() ? 'rgba(11,16,25,0.42)' : fallbackColor;
}

export function uiPopupBlurStyle(): BlurStyle {
  return isHarmonyUiStyle() && supportsBackgroundBlur() ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE;
}

export function uiSearchFieldHeight(): number {
  return isHarmonyUiStyle() ? 44 : 40;
}

export function uiSwitchWidth(): number {
  return isHarmonyUiStyle() ? 56 : 52;
}

export function uiSwitchHeight(): number {
  return isHarmonyUiStyle() ? 34 : 32;
}

export function uiSelectorHeight(): number {
  return isHarmonyUiStyle() ? 42 : 38;
}

export function uiTabHeight(): number {
  return isHarmonyUiStyle() ? 42 : 38;
}

export function uiListGap(): number {
  return isHarmonyUiStyle() ? 12 : 8;
}

export function uiPageHorizontalPadding(contentWidth: number): number {
  if (contentWidth >= 840) {
    return 24;
  }
  if (contentWidth >= 600) {
    return 20;
  }
  return 12;
}

export function uiAdaptiveColumnCount(contentWidth: number, preferredWidth: number, gap: number = uiListGap()): number {
  if (contentWidth <= 0 || preferredWidth <= 0) {
    return 1;
  }
  const padding = uiPageHorizontalPadding(contentWidth) * 2;
  return Math.max(1, Math.floor((Math.max(0, contentWidth - padding) + gap) / (preferredWidth + gap)));
}

export function uiListItemBackground(fallbackColor: string): string {
  if (!isHarmonyUiStyle()) {
    return fallbackColor;
  }
  return isDarkTheme() ? 'rgba(255,255,255,0.055)' : 'rgba(255,255,255,0.78)';
}

export function uiListItemSelectedBackground(fallbackColor: string): string {
  if (!isHarmonyUiStyle()) {
    return fallbackColor;
  }
  return isDarkTheme() ? 'rgba(86,192,235,0.18)' : 'rgba(45,134,168,0.14)';
}

export function uiListItemBorderColor(fallbackColor: ResourceColor): ResourceColor {
  if (!isHarmonyUiStyle()) {
    return fallbackColor;
  }
  return isDarkTheme() ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.08)';
}

export function uiAdaptiveTitleSize(contentWidth: number): number {
  return contentWidth >= 600 ? 22 : 20;
}

export function uiAdaptiveToolbarHeight(contentWidth: number): number {
  return contentWidth >= 600 ? 64 : 60;
}

export function uiPanelMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyMaterialEnabled()) {
    return undefined;
  }
  if (harmony7PanelMaterial === undefined) {
    harmony7PanelMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      applyShadow: true,
      interactive: false
    });
  }
  return harmony7PanelMaterial;
}

export function uiDialogMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyMaterialEnabled()) {
    return undefined;
  }
  if (harmony7DialogMaterial === undefined) {
    harmony7DialogMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THICK,
      applyShadow: true,
      interactive: false
    });
  }
  return harmony7DialogMaterial;
}
