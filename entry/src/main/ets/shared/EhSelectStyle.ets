import { SymbolGlyphModifier } from '@kit.ArkUI';
import { themePrimaryText } from './EhTheme';

export function selectArrowModifier(color: ResourceColor = themePrimaryText(), size: number = 16): SymbolGlyphModifier {
  const modifier = new SymbolGlyphModifier();
  modifier
    .fontSize(size)
    .fontColor([color]);
  return modifier;
}
