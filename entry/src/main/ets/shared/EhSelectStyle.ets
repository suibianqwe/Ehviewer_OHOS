import { SymbolGlyphModifier } from '@kit.ArkUI';
import {
  themeAccentTextColor,
  themeDividerColor,
  themeFieldBackground,
  themePrimaryText,
  themeSelectedBackground,
  themeSurface
} from './EhTheme';
import { uiListItemSelectedBackground } from './EhUiStyle';

export interface SelectColorSet {
  buttonText: ResourceColor;
  buttonBackground: string;
  menuBackground: string;
  optionBackground: ResourceColor;
  optionText: ResourceColor;
  selectedOptionBackground: ResourceColor;
  selectedOptionText: ResourceColor;
  arrow: ResourceColor;
  outline: ResourceColor;
}

export function themedSelectColors(): SelectColorSet {
  return {
    buttonText: themePrimaryText(),
    buttonBackground: themeFieldBackground(),
    menuBackground: themeFieldBackground(),
    optionBackground: themeFieldBackground(),
    optionText: themePrimaryText(),
    selectedOptionBackground: themeSelectedBackground(),
    selectedOptionText: themePrimaryText(),
    arrow: themePrimaryText(),
    outline: themeDividerColor()
  };
}

export function readerSelectColors(): SelectColorSet {
  return {
    buttonText: themePrimaryText(),
    buttonBackground: themeFieldBackground(),
    menuBackground: themeSurface(),
    optionBackground: Color.Transparent,
    optionText: themePrimaryText(),
    selectedOptionBackground: uiListItemSelectedBackground(themeSelectedBackground()),
    selectedOptionText: themeAccentTextColor(),
    arrow: themePrimaryText(),
    outline: themeDividerColor()
  };
}

export function selectArrowModifier(color: ResourceColor = themePrimaryText(), size: number = 16): SymbolGlyphModifier {
  const modifier = new SymbolGlyphModifier();
  modifier
    .fontSize(size)
    .fontColor([color]);
  return modifier;
}

export function themedSelectButtonBackground(): ResourceColor {
  return themedSelectColors().buttonBackground;
}

export function themedSelectButtonText(): ResourceColor {
  return themedSelectColors().buttonText;
}

export function themedSelectMenuBackground(): ResourceColor {
  return themedSelectColors().menuBackground;
}

export function themedSelectOptionBackground(): ResourceColor {
  return themedSelectColors().optionBackground;
}


export function themedSelectOptionText(): ResourceColor {
  return themedSelectColors().optionText;
}

export function themedSelectSelectedOptionBackground(): ResourceColor {
  return themedSelectColors().selectedOptionBackground;
}

export function themedSelectSelectedOptionText(): ResourceColor {
  return themedSelectColors().selectedOptionText;
}

export function themedSelectOutlineColor(): ResourceColor {
  return themedSelectColors().outline;
}
