import { colorSpaceManager } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import readerHdr from 'libreaderhdr.so';

interface ReaderHdrCacheEntry {
  key: string;
  sourcePath: string;
  references: number;
  cancelled: boolean;
  pixelMap: image.PixelMap | undefined;
  loading: Promise<image.PixelMap | undefined> | undefined;
}

class ReaderHdrService {
  private entries: Map<string, ReaderHdrCacheEntry> = new Map<string, ReaderHdrCacheEntry>();
  private conversionTail: Promise<void> = Promise.resolve();
  private capabilityKnown: boolean = false;
  private capabilitySupported: boolean = false;

  acquire(key: string, sourcePath: string): Promise<image.PixelMap | undefined> {
    if (key.length === 0 || sourcePath.length === 0 || !this.isSupported()) {
      return Promise.resolve(undefined);
    }
    let entry = this.entries.get(key);
    if (entry === undefined || entry.sourcePath !== sourcePath) {
      if (entry !== undefined) {
        this.disposeEntry(entry);
      }
      entry = {
        key: key,
        sourcePath: sourcePath,
        references: 0,
        cancelled: false,
        pixelMap: undefined,
        loading: undefined
      };
      this.entries.set(key, entry);
    }
    entry.references++;
    entry.cancelled = false;
    if (entry.pixelMap !== undefined) {
      return Promise.resolve(entry.pixelMap);
    }
    if (entry.loading !== undefined) {
      return entry.loading;
    }
    entry.loading = this.enqueueConversion(entry);
    return entry.loading;
  }

  release(key: string): void {
    const entry = this.entries.get(key);
    if (entry === undefined) {
      return;
    }
    entry.references = Math.max(0, entry.references - 1);
    if (entry.references > 0) {
      return;
    }
    entry.cancelled = true;
    if (entry.pixelMap !== undefined) {
      this.releasePixelMap(entry.pixelMap);
      entry.pixelMap = undefined;
    }
    if (entry.loading === undefined) {
      this.entries.delete(key);
    }
  }

  private isSupported(): boolean {
    if (!this.capabilityKnown) {
      this.capabilityKnown = true;
      try {
        this.capabilitySupported = readerHdr.isSdrToHdrSupported();
      } catch (_error) {
        this.capabilitySupported = false;
      }
    }
    return this.capabilitySupported;
  }

  private enqueueConversion(entry: ReaderHdrCacheEntry): Promise<image.PixelMap | undefined> {
    let resolveTask: (value: image.PixelMap | undefined) => void = (_value: image.PixelMap | undefined): void => {};
    const result = new Promise<image.PixelMap | undefined>((resolve: (value: image.PixelMap | undefined) => void) => {
      resolveTask = resolve;
    });
    this.conversionTail = this.conversionTail.then(async () => {
      let pixelMap: image.PixelMap | undefined = undefined;
      if (!entry.cancelled && entry.references > 0 && this.entries.get(entry.key) === entry) {
        pixelMap = await this.convert(entry.sourcePath);
      }
      entry.loading = undefined;
      if (pixelMap !== undefined && !entry.cancelled && entry.references > 0 &&
        this.entries.get(entry.key) === entry) {
        entry.pixelMap = pixelMap;
      } else if (pixelMap !== undefined) {
        this.releasePixelMap(pixelMap);
        pixelMap = undefined;
      }
      if (entry.references <= 0 && entry.pixelMap === undefined && this.entries.get(entry.key) === entry) {
        this.entries.delete(entry.key);
      }
      resolveTask(pixelMap);
    }).catch(() => {
      entry.loading = undefined;
      if (entry.references <= 0 && this.entries.get(entry.key) === entry) {
        this.entries.delete(entry.key);
      }
      resolveTask(undefined);
    });
    return result;
  }

  private async convert(sourcePath: string): Promise<image.PixelMap | undefined> {
    let source: image.ImageSource | undefined = undefined;
    let sourcePixelMap: image.PixelMap | undefined = undefined;
    let destinationPixelMap: image.PixelMap | undefined = undefined;
    try {
      const srgb = colorSpaceManager.create(colorSpaceManager.ColorSpace.SRGB);
      const hlg = colorSpaceManager.create(colorSpaceManager.ColorSpace.BT2020_HLG);
      source = image.createImageSource(sourcePath);
      sourcePixelMap = await source.createPixelMapUsingAllocator({
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredColorSpace: srgb,
        desiredDynamicRange: image.DecodingDynamicRange.SDR
      }, image.AllocatorType.DMA);
      const info = sourcePixelMap.getImageInfoSync();
      if (info.size.width < 32 || info.size.height < 32 || info.size.width > 8880 || info.size.height > 8880) {
        return undefined;
      }
      sourcePixelMap.setColorSpace(srgb);
      await sourcePixelMap.setMetadata(image.HdrMetadataKey.HDR_METADATA_TYPE, image.HdrMetadataType.NONE);
      destinationPixelMap = image.createPixelMapUsingAllocatorSync({
        editable: true,
        pixelFormat: image.PixelMapFormat.RGBA_1010102,
        alphaType: image.AlphaType.PREMUL,
        size: {
          width: info.size.width,
          height: info.size.height
        }
      }, image.AllocatorType.DMA);
      destinationPixelMap.setColorSpace(hlg);
      await destinationPixelMap.setMetadata(image.HdrMetadataKey.HDR_METADATA_TYPE,
        image.HdrMetadataType.ALTERNATE);
      const result: number = await readerHdr.convertSdrToHdr(sourcePixelMap, destinationPixelMap);
      if (result !== 0) {
        return undefined;
      }
      const converted = destinationPixelMap;
      destinationPixelMap = undefined;
      return converted;
    } catch (_error) {
      return undefined;
    } finally {
      if (destinationPixelMap !== undefined) {
        this.releasePixelMap(destinationPixelMap);
      }
      if (sourcePixelMap !== undefined) {
        this.releasePixelMap(sourcePixelMap);
      }
      if (source !== undefined) {
        try {
          await source.release();
        } catch (_error) {
        }
      }
    }
  }

  private disposeEntry(entry: ReaderHdrCacheEntry): void {
    entry.references = 0;
    entry.cancelled = true;
    if (entry.pixelMap !== undefined) {
      this.releasePixelMap(entry.pixelMap);
      entry.pixelMap = undefined;
    }
    this.entries.delete(entry.key);
  }

  private releasePixelMap(pixelMap: image.PixelMap): void {
    try {
      pixelMap.release().catch(() => {});
    } catch (_error) {
    }
  }
}

export const readerHdrService: ReaderHdrService = new ReaderHdrService();
