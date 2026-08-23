import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ehSettingsStore } from '../services/EhSettingsStore';

export const EH_UI_STYLE_CLASSIC: string = 'Classic';
export const EH_UI_STYLE_HARMONY_7: string = 'HarmonyOS 7';

let harmony7FloatingMaterial: uiMaterial.Material | undefined;
let harmony7PanelMaterial: uiMaterial.Material | undefined;
let harmony7DialogMaterial: uiMaterial.Material | undefined;

function supportsHarmonyOs7Material(): boolean {
  return deviceInfo.sdkApiVersion >= 26;
}

export function currentUiStyleName(): string {
  return ehSettingsStore.getValue('ui_style', EH_UI_STYLE_CLASSIC) === EH_UI_STYLE_HARMONY_7 ?
    EH_UI_STYLE_HARMONY_7 : EH_UI_STYLE_CLASSIC;
}

export function isHarmonyOs7UiStyle(): boolean {
  return currentUiStyleName() === EH_UI_STYLE_HARMONY_7;
}

export function uiControlRadius(classicRadius: number = 6): number {
  return isHarmonyOs7UiStyle() ? Math.max(12, classicRadius) : classicRadius;
}

export function uiCardRadius(classicRadius: number = 8): number {
  return isHarmonyOs7UiStyle() ? Math.max(16, classicRadius) : classicRadius;
}

export function uiPanelRadius(classicRadius: number = 12): number {
  return isHarmonyOs7UiStyle() ? Math.max(24, classicRadius) : classicRadius;
}

export function uiPillRadius(classicRadius: number = 18): number {
  return isHarmonyOs7UiStyle() ? Math.max(22, classicRadius) : classicRadius;
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
  if (!isHarmonyOs7UiStyle() || !supportsHarmonyOs7Material()) {
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

export function uiPanelMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyOs7UiStyle() || !supportsHarmonyOs7Material()) {
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
  if (!isHarmonyOs7UiStyle() || !supportsHarmonyOs7Material()) {
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
