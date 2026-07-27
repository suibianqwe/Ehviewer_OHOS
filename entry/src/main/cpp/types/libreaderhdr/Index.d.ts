import { image } from '@kit.ImageKit';

export const isSdrToHdrSupported: () => boolean;
export const convertSdrToHdr: (source: image.PixelMap, destination: image.PixelMap) => Promise<number>;
