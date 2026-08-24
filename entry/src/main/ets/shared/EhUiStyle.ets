import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ehSettingsStore } from '../services/EhSettingsStore';
import {
  isDarkTheme,
  themeMaterialContentColor,
  themeMaterialSecondaryContentColor
} from './EhTheme';

export const EH_UI_STYLE_CLASSIC: string = 'Classic';
export const EH_UI_STYLE_HARMONY_7: string = 'HarmonyOS 7';

let harmony7FloatingMaterial: uiMaterial.Material | undefined;
let harmony7ButtonMaterial: uiMaterial.Material | undefined;
let harmony7ChromeMaterial: uiMaterial.Material | undefined;
let harmony7SearchMaterial: uiMaterial.Material | undefined;
let harmony7SegmentMaterial: uiMaterial.Material | undefined;
let harmony7PanelMaterial: uiMaterial.Material | undefined;
let harmony7DialogMaterial: uiMaterial.Material | undefined;

function supportsHarmonyOs7Material(): boolean {
  return deviceInfo.sdkApiVersion >= 26;
}

export function isHarmonyOs7MaterialEnabled(): boolean {
  return isHarmonyOs7UiStyle() && supportsHarmonyOs7Material();
}

export function currentUiStyleName(): string {
  return ehSettingsStore.getValue('ui_style', EH_UI_STYLE_CLASSIC) === EH_UI_STYLE_HARMONY_7 ?
    EH_UI_STYLE_HARMONY_7 : EH_UI_STYLE_CLASSIC;
}

export function isHarmonyOs7UiStyle(): boolean {
  return currentUiStyleName() === EH_UI_STYLE_HARMONY_7;
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
  if (!isHarmonyOs7MaterialEnabled()) {
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
  if (!isHarmonyOs7MaterialEnabled()) {
    return undefined;
  }
  if (harmony7ButtonMaterial === undefined) {
    harmony7ButtonMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      applyShadow: true,
      interactive: true,
      lightEffect: { color: undefined }
    });
  }
  return harmony7ButtonMaterial;
}

export function uiChromeMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyOs7MaterialEnabled()) {
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
  if (!isHarmonyOs7MaterialEnabled()) {
    return undefined;
  }
  if (harmony7SearchMaterial === undefined) {
    harmony7SearchMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      applyShadow: true,
      interactive: true,
      lightEffect: { color: undefined }
    });
  }
  return harmony7SearchMaterial;
}

export function uiSegmentMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyOs7MaterialEnabled()) {
    return undefined;
  }
  if (harmony7SegmentMaterial === undefined) {
    harmony7SegmentMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: undefined }
    });
  }
  return harmony7SegmentMaterial;
}

export function uiMaterialBackground(solidColor: string): string {
  return isHarmonyOs7MaterialEnabled() ? 'rgba(0,0,0,0)' : solidColor;
}

export function uiMaterialForegroundColor(fallbackColor: ResourceColor): ResourceColor {
  return isHarmonyOs7MaterialEnabled() ? themeMaterialContentColor() : fallbackColor;
}

export function uiMaterialSecondaryForegroundColor(fallbackColor: ResourceColor): ResourceColor {
  return isHarmonyOs7MaterialEnabled() ? themeMaterialSecondaryContentColor() : fallbackColor;
}

export function uiTitleBarBlurStyle(): BlurStyle {
  return isHarmonyOs7MaterialEnabled() ? BlurStyle.COMPONENT_ULTRA_THIN : BlurStyle.NONE;
}

export function uiTitleBarFadeHeight(): number {
  return isHarmonyOs7UiStyle() ? 6 : 3;
}

export function uiTitleBarFadeStartColor(): string {
  if (!isHarmonyOs7UiStyle()) {
    return 'rgba(0,0,0,0)';
  }
  return isDarkTheme() ? 'rgba(12,13,16,0.12)' : 'rgba(248,249,252,0.16)';
}

export function uiPopupBlurStyle(): BlurStyle {
  return isHarmonyOs7MaterialEnabled() ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE;
}

export function uiSearchFieldHeight(): number {
  return isHarmonyOs7UiStyle() ? 44 : 40;
}

export function uiSwitchWidth(): number {
  return isHarmonyOs7UiStyle() ? 56 : 52;
}

export function uiSwitchHeight(): number {
  return isHarmonyOs7UiStyle() ? 34 : 32;
}

export function uiSelectorHeight(): number {
  return isHarmonyOs7UiStyle() ? 42 : 38;
}

export function uiTabHeight(): number {
  return isHarmonyOs7UiStyle() ? 42 : 38;
}

export function uiListGap(): number {
  return isHarmonyOs7UiStyle() ? 12 : 8;
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
  if (!isHarmonyOs7UiStyle()) {
    return fallbackColor;
  }
  return isDarkTheme() ? 'rgba(255,255,255,0.055)' : 'rgba(255,255,255,0.78)';
}

export function uiListItemSelectedBackground(fallbackColor: string): string {
  if (!isHarmonyOs7UiStyle()) {
    return fallbackColor;
  }
  return isDarkTheme() ? 'rgba(86,192,235,0.18)' : 'rgba(45,134,168,0.14)';
}

export function uiListItemBorderColor(fallbackColor: ResourceColor): ResourceColor {
  if (!isHarmonyOs7UiStyle()) {
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
  if (!isHarmonyOs7MaterialEnabled()) {
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
  if (!isHarmonyOs7MaterialEnabled()) {
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
