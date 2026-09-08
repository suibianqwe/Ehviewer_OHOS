import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ehSettingsStore } from '../services/EhSettingsStore';
import {
  isDarkTheme,
  themeFieldBackground,
  themeMaterialContentColor,
  themeMaterialSecondaryContentColor,
  themePrimaryColor,
  themeShadowColor,
  themeSurface,
  themeSurfaceVariant
} from './EhTheme';

export const EH_UI_STYLE_CLASSIC: string = 'Classic';
export const EH_UI_STYLE_HARMONY: string = 'Harmony';
const EH_UI_STYLE_HARMONY_LEGACY: string = 'HarmonyOS 7';

let harmony7ChromeMaterial: uiMaterial.Material | undefined;
const harmony7SearchMaterials: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();
const harmony7SegmentMaterials: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();
const harmony7TintedSegmentMaterials: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();
const harmony7ReaderOptionSegmentMaterials: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();
const harmony7PanelMaterials: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();
const harmony7DialogMaterials: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();
const harmony7SelectDialogMaterials: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();
let immersiveMaterialSupport: boolean | undefined;

function supportsImmersiveMaterial(): boolean {
  if (deviceInfo.sdkApiVersion < 26) {
    return false;
  }
  if (immersiveMaterialSupport === undefined) {
    try {
      immersiveMaterialSupport = uiMaterial.isImmersiveMaterialSupported();
    } catch (error) {
      immersiveMaterialSupport = false;
    }
  }
  return immersiveMaterialSupport;
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

export function uiButtonMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    return uiMaterial.Material.empty;
  }
  return undefined;
}

export function uiTintedButtonMaterial(_solidColor: string): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    return uiMaterial.Material.empty;
  }
  return undefined;
}

export function uiChromeMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    if (harmony7ChromeMaterial === undefined) {
      harmony7ChromeMaterial = new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        applyShadow: false,
        interactive: false
      });
    }
    return harmony7ChromeMaterial;
  }
  return undefined;
}

export function uiSearchMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    const materialColor = 'transparent';
    const cached = harmony7SearchMaterials.get(materialColor);
    if (cached !== undefined) {
      return cached;
    }
    const material = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      applyShadow: true,
      interactive: true,
      lightEffect: { color: Color.White }
    });
    harmony7SearchMaterials.set(materialColor, material);
    return material;
  }
  return undefined;
}

// 纯色背景没有可供模糊的纹理，输入区域需要独立于材质的明暗自适应边界。
export function uiInputFieldBorder(hasError: boolean = false): BorderOptions {
  return {
    // Inputs use fill contrast for hierarchy; keep the edge free of strokes.
    width: 0,
    color: Color.Transparent
  };
}

export function uiSegmentMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    const materialColor = 'transparent';
    const cached = harmony7SegmentMaterials.get(materialColor);
    if (cached !== undefined) {
      return cached;
    }
    const material = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: Color.White }
    });
    harmony7SegmentMaterials.set(materialColor, material);
    return material;
  }
  return undefined;
}

function translucentMaterialColor(solidColor: string): string {
  const color = solidColor.trim();
  if (/^#[0-9A-Fa-f]{6}$/.test(color)) {
    return '#73' + color.substring(1);
  }
  const rgba = /^rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*[\d.]+\s*\)$/i.exec(color);
  if (rgba !== null) {
    return 'rgba(' + rgba[1] + ',' + rgba[2] + ',' + rgba[3] + ',0.45)';
  }
  return color;
}

function materialColorWithAlpha(solidColor: string, alpha: string): string {
  const color = solidColor.trim();
  if (/^#[0-9A-Fa-f]{6}$/.test(color)) {
    return '#' + alpha + color.substring(1);
  }
  return color;
}

export function uiTintedSegmentMaterial(solidColor: string): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    const materialColor = translucentMaterialColor(solidColor);
    const cached = harmony7TintedSegmentMaterials.get(materialColor);
    if (cached !== undefined) {
      return cached;
    }
    const material = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: materialColor,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: Color.White }
    });
    harmony7TintedSegmentMaterials.set(materialColor, material);
    return material;
  }
  return undefined;
}

export function uiReaderOptionButtonMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    return uiMaterial.Material.empty;
  }
  return undefined;
}

export function uiReaderOptionSegmentMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    const materialColor = isDarkTheme() ? 'transparent' : 'rgba(255,255,255,0.22)';
    const cached = harmony7ReaderOptionSegmentMaterials.get(materialColor);
    if (cached !== undefined) {
      return cached;
    }
    const material = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: materialColor,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: Color.White }
    });
    harmony7ReaderOptionSegmentMaterials.set(materialColor, material);
    return material;
  }
  return undefined;
}

export function uiMaterialBackground(solidColor: ResourceColor): ResourceColor {
  if (!isHarmonyMaterialEnabled()) {
    return solidColor;
  }
  // An opaque backgroundColor is documented to cover the system material.
  // Keep the authored color only as the pre-API-26 fallback; API 26 uses the
  // material's own tint and filter.
  return Color.Transparent;
}

export function uiMaterialLayerBackground(solidColor: string): string {
  if (!isHarmonyUiStyle()) {
    return solidColor;
  }
  return isHarmonyMaterialEnabled() ? 'rgba(0,0,0,0)' : solidColor;
}

export function uiButtonHighlightBorderColor(): ResourceColor {
  if (!isHarmonyUiStyle()) {
    return Color.Transparent;
  }
  return isDarkTheme() ? 'rgba(255,255,255,0.30)' : materialColorWithAlpha(themePrimaryColor(), '52');
}

export function uiPopupMaterialBackground(solidColor: string): string {
  if (!isHarmonyUiStyle()) {
    return solidColor;
  }
  if (isHarmonyMaterialEnabled()) {
    return 'rgba(0,0,0,0)';
  }
  return isDarkTheme() ? 'rgba(17,24,39,0.84)' : 'rgba(248,249,252,0.84)';
}

export function uiPopupContentBackground(solidColor: string): string {
  if (!isHarmonyUiStyle()) {
    return solidColor;
  }
  return isHarmonyMaterialEnabled() ? materialColorWithAlpha(solidColor, 'F2') : solidColor;
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

export function uiTransparentButtonBackgroundEffect(): BackgroundEffectOptions | undefined {
  if (!isHarmonyUiStyle() || !supportsBackgroundEffect()) {
    return undefined;
  }
  return {
    radius: 40,
    saturation: 1.08,
    brightness: isDarkTheme() ? 0.92 : 1.04,
    color: isDarkTheme() ? 'rgba(16,22,30,0.48)' : 'rgba(255,255,255,0.62)',
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
    brightness: effectEnabled ? (isDarkTheme() ? 0.98 : 1.04) : 1,
    color: effectEnabled ?
      (isDarkTheme() ? 'rgba(11,16,25,0.56)' : 'rgba(255,255,255,0.52)') : Color.Transparent,
    adaptiveColor: AdaptiveColor.DEFAULT
  };
}

export function uiReaderProgressBackgroundEffect(): BackgroundEffectOptions {
  return uiPopupBackgroundEffect();
}

export function uiReaderProgressBackgroundColor(fallbackColor: string): string {
  if (!isHarmonyUiStyle()) {
    return fallbackColor;
  }
  return supportsBackgroundEffect() ? 'rgba(0,0,0,0)' : themeSurface();
}

function uiSurfaceBlurStyle(style: BlurStyle): BlurStyle {
  return isHarmonyUiStyle() && supportsBackgroundBlur() ? style : BlurStyle.NONE;
}

function uiSurfaceBlurOptions(): BackgroundBlurStyleOptions {
  return {
    colorMode: isDarkTheme() ? ThemeColorMode.DARK : ThemeColorMode.LIGHT,
    adaptiveColor: AdaptiveColor.DEFAULT,
    scale: 0.82
  };
}

export function uiPopupBlurStyle(): BlurStyle {
  return uiSurfaceBlurStyle(BlurStyle.COMPONENT_THICK);
}

export function uiPopupBlurOptions(): BackgroundBlurStyleOptions {
  return uiSurfaceBlurOptions();
}

export function uiPopupBackgroundEffect(): BackgroundEffectOptions {
  const effectEnabled = isHarmonyUiStyle() && supportsBackgroundEffect();
  return {
    radius: effectEnabled ? 24 : 0,
    saturation: effectEnabled ? 1.08 : 1,
    brightness: effectEnabled ? (isDarkTheme() ? 0.84 : 1.04) : 1,
    color: Color.Transparent,
    adaptiveColor: AdaptiveColor.DEFAULT
  };
}

export function uiFloatingButtonBackgroundEffect(tintColor: string = ''): BackgroundEffectOptions | undefined {
  if (tintColor.length === 0) {
    return uiTransparentButtonBackgroundEffect();
  }
  if (!isHarmonyUiStyle() || !supportsBackgroundEffect()) {
    return undefined;
  }
  return {
    radius: 22,
    saturation: 1.12,
    brightness: isDarkTheme() ? 0.9 : 1.04,
    color: materialColorWithAlpha(tintColor, '34'),
    adaptiveColor: AdaptiveColor.DEFAULT
  };
}

export function uiReaderOptionControlBackground(
  fallbackColor: ResourceColor = Color.Transparent
): ResourceColor {
  if (!isHarmonyUiStyle()) {
    return fallbackColor;
  }
  if (isDarkTheme() || isHarmonyMaterialEnabled()) {
    return Color.Transparent;
  }
  return 'rgba(255,255,255,0.22)';
}

export function uiReaderSelectControlBackground(fallbackColor: ResourceColor): ResourceColor {
  if (!isHarmonyUiStyle()) {
    return fallbackColor;
  }
  if (isDarkTheme() || isHarmonyMaterialEnabled()) {
    return Color.Transparent;
  }
  return 'rgba(255,255,255,0.58)';
}

export function uiPopupEffectBackground(solidColor: string): string {
  return isHarmonyUiStyle() && (supportsBackgroundEffect() || supportsBackgroundBlur()) ?
    'rgba(0,0,0,0)' : solidColor;
}

export function uiSelectPopupBackground(solidColor: string): string {
  if (!isHarmonyUiStyle()) {
    return solidColor;
  }
  if (!isDarkTheme() && (supportsBackgroundEffect() || supportsBackgroundBlur())) {
    return 'rgba(255,255,255,0.82)';
  }
  return uiPopupEffectBackground(solidColor);
}

export function uiReaderSelectPopupBackground(solidColor: string): string {
  if (!isHarmonyUiStyle()) {
    return solidColor;
  }
  if (!isDarkTheme() && (supportsBackgroundEffect() || supportsBackgroundBlur())) {
    return 'rgba(255,255,255,0.90)';
  }
  // 旧系统无法为 Select 菜单单独指定模糊色调，底色也须保证暗色文字对比度。
  return uiPopupMaterialBackground(solidColor);
}

export function uiSearchFieldHeight(): number {
  return isHarmonyUiStyle() ? 44 : 40;
}

export function uiSwitchWidth(): number {
  return 52;
}

export function uiSwitchHeight(): number {
  return 32;
}

export function uiSelectorHeight(): number {
  return isHarmonyUiStyle() ? 42 : 38;
}

export function uiReaderOptionRowHeight(): number {
  return isHarmonyUiStyle() ? 50 : 52;
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

export function uiAdaptiveColumnCount(contentWidth: number, preferredWidth: number, gap: number = uiListGap(),
  horizontalPadding: number = 0): number {
  if (contentWidth <= 0 || preferredWidth <= 0) {
    return 1;
  }
  const edgePadding = horizontalPadding > 0 ? horizontalPadding : uiPageHorizontalPadding(contentWidth);
  const padding = edgePadding * 2;
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
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    const materialColor = materialColorWithAlpha(themeSurface(), isDarkTheme() ? 'E6' : 'F0');
    const cached = harmony7PanelMaterials.get(materialColor);
    if (cached !== undefined) {
      return cached;
    }
    const material = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THICK,
      materialColor: materialColor,
      applyShadow: true,
      interactive: false
    });
    harmony7PanelMaterials.set(materialColor, material);
    return material;
  }
  return undefined;
}

export function uiDialogMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    // Keep the dialog surface transparent so the blur filter can sample the
    // page behind the modal. An opaque materialColor turns API 26 dialogs into
    // flat panels and hides the background blur.
    const materialColor = 'transparent';
    const cached = harmony7DialogMaterials.get(materialColor);
    if (cached !== undefined) {
      return cached;
    }
    const material = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      applyShadow: false,
      interactive: false
    });
    harmony7DialogMaterials.set(materialColor, material);
    return material;
  }
  return undefined;
}

export function uiSelectDialogMaterial(): uiMaterial.Material | undefined {
  if (!isHarmonyUiStyle()) {
    return undefined;
  }
  if (supportsImmersiveMaterial()) {
    const materialColor = isDarkTheme() ? 'rgba(17,24,39,0.88)' : 'rgba(255,255,255,0.82)';
    const cached = harmony7SelectDialogMaterials.get(materialColor);
    if (cached !== undefined) {
      return cached;
    }
    const material = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: materialColor,
      applyShadow: false,
      interactive: false
    });
    harmony7SelectDialogMaterials.set(materialColor, material);
    return material;
  }
  return undefined;
}

export function uiDialogSurfaceBackground(): string {
  return uiPopupEffectBackground(themeSurface());
}

export function uiDialogBlurStyle(): BlurStyle {
  // ConfirmActionOverlay and the other in-app dialogs are custom Stack layers,
  // not framework Dialog components. Their systemMaterial call is out of scope,
  // so disabling this blur on API 26 turns the panel into plain transparency.
  return isHarmonyUiStyle() ? uiSurfaceBlurStyle(BlurStyle.BACKGROUND_THICK) : BlurStyle.NONE;
}

export function uiDialogBlurOptions(): BackgroundBlurStyleOptions {
  return uiSurfaceBlurOptions();
}

export function uiDialogSurfaceRadius(): number {
  return uiPanelRadius(12);
}

export function uiDialogSurfaceShadow(): ShadowOptions {
  return {
    radius: 18,
    color: themeShadowColor(),
    offsetX: 0,
    offsetY: 8
  };
}
