import { image } from '@kit.ImageKit';

export const isSdrToHdrSupported: () => boolean;
export const createCompatibleSdrPixelMap: (source: image.PixelMap) => image.PixelMap;
export const createDmaHdrPixelMap: (width: number, height: number) => image.PixelMap;
export const convertSdrToHdr: (source: image.PixelMap, destination: image.PixelMap) => Promise<number>;
export const adjustPixelMap: (source: image.PixelMap, contrast: number, clarity: number, sharpening: number,
  exposure: number, hue: number, saturation: number, temperature: number) => Promise<number>;
