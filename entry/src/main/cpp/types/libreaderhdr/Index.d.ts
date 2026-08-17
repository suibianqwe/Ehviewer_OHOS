import { image } from '@kit.ImageKit';

export const isSdrToHdrSupported: () => boolean;
export const createCompatibleSdrPixelMap: (source: image.PixelMap) => image.PixelMap;
export const createDmaHdrPixelMap: (width: number, height: number) => image.PixelMap;
export const convertSdrToHdr: (source: image.PixelMap, destination: image.PixelMap) => Promise<number>;
export const adjustPixelMap: (source: image.PixelMap, contrast: number, clarity: number, sharpening: number,
  exposure: number, brightness: number, highlights: number, shadows: number, hue: number, saturation: number,
  vibrance: number, temperature: number, grayscale: number, moireReduction: number,
  targetWidth: number, targetHeight: number) => Promise<number>;
