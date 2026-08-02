import { image } from '@kit.ImageKit';

export const isSdrToHdrSupported: () => boolean;
export const createCompatibleSdrPixelMap: (source: image.PixelMap) => image.PixelMap;
export const createDmaHdrPixelMap: (width: number, height: number) => image.PixelMap;
export const convertSdrToHdr: (source: image.PixelMap, destination: image.PixelMap) => Promise<number>;
