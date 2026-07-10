import { common } from '@kit.AbilityKit';
import { colorSpaceManager } from '@kit.ArkGraphics2D';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { readerImageCache, readerImageCacheDirectory } from './ReaderImageCache';

interface PendingGalleryThumbnailColor {
  key: string;
  promise: Promise<string>;
}

const PENDING_GALLERY_THUMBNAILS: PendingGalleryThumbnailColor[] = [];
const WAITING_GALLERY_THUMBNAILS: (() => void)[] = [];
const MAX_ACTIVE_GALLERY_THUMBNAILS: number = 2;
const GALLERY_THUMBNAIL_RETRY_LIMIT: number = 2;
let activeGalleryThumbnails: number = 0;
let srgbColorSpace: colorSpaceManager.ColorSpaceManager | undefined = undefined;

export class GalleryThumbnailColorCache {
  async ensureSrgb(context: common.UIAbilityContext, imageUrl: string, referer: string): Promise<string> {
    if (imageUrl.length === 0) {
      return '';
    }

    const srgbPath = this.pathFor(context, imageUrl);
    if (exists(srgbPath)) {
      return srgbPath;
    }

    const pending = getPending(srgbPath);
    if (pending !== null) {
      return pending;
    }

    const promise = this.normalizeColor(context, imageUrl, referer, srgbPath);
    putPending(srgbPath, promise);
    try {
      return await promise;
    } finally {
      removePending(srgbPath);
    }
  }

  getSrgbPath(context: common.UIAbilityContext, imageUrl: string): string {
    if (imageUrl.length === 0) {
      return '';
    }

    const path = this.pathFor(context, imageUrl);
    return exists(path) ? path : '';
  }

  private async normalizeColor(context: common.UIAbilityContext, imageUrl: string, referer: string,
    outputPath: string): Promise<string> {
    const sourcePath = await readerImageCache.ensureCached(context, imageUrl, referer, false, undefined, '',
      { retryLimit: GALLERY_THUMBNAIL_RETRY_LIMIT });
    if (sourcePath.length === 0) {
      return '';
    }

    ensureDirectory(readerImageCacheDirectory(context));
    await acquireGalleryThumbnailSlot();
    let imageSource: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    let imagePacker: image.ImagePacker | undefined = undefined;
    try {
      const srgb = getSrgbColorSpace();
      if (srgb === undefined) {
        return sourcePath;
      }
      imageSource = image.createImageSource(sourcePath);
      const options: image.DecodingOptions = {
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredColorSpace: srgb,
        desiredDynamicRange: image.DecodingDynamicRange.SDR,
        index: 0
      };
      pixelMap = await imageSource.createPixelMap(options);
      pixelMap.setColorSpace(srgb);
      await pixelMap.setMetadata(image.HdrMetadataKey.HDR_METADATA_TYPE, image.HdrMetadataType.NONE);
      imagePacker = image.createImagePacker();
      const packOptions: image.PackingOption = {
        format: 'image/png',
        quality: 100,
        desiredDynamicRange: image.PackingDynamicRange.SDR
      };
      const data = await imagePacker.packToData(pixelMap, packOptions);
      writeArrayBuffer(outputPath, data);
      return outputPath;
    } catch (error) {
      removeFileQuietly(outputPath);
      return sourcePath;
    } finally {
      if (imagePacker !== undefined) {
        try {
          await imagePacker.release();
        } catch (error) {
        }
      }
      if (pixelMap !== undefined) {
        try {
          await pixelMap.release();
        } catch (error) {
        }
      }
      if (imageSource !== undefined) {
        try {
          await imageSource.release();
        } catch (error) {
        }
      }
      releaseGalleryThumbnailSlot();
    }
  }

  private pathFor(context: common.UIAbilityContext, imageUrl: string): string {
    return readerImageCacheDirectory(context) + '/gallery_thumb_srgb_' + stableGalleryThumbnailKey(imageUrl) + '.png';
  }
}

function getSrgbColorSpace(): colorSpaceManager.ColorSpaceManager | undefined {
  if (srgbColorSpace === undefined) {
    try {
      srgbColorSpace = colorSpaceManager.create(colorSpaceManager.ColorSpace.SRGB);
    } catch (error) {
      return undefined;
    }
  }
  return srgbColorSpace;
}

function writeArrayBuffer(path: string, data: ArrayBuffer): void {
  let fd = -1;
  try {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    fd = file.fd;
    fs.writeSync(fd, data);
  } catch (error) {
    removeFileQuietly(path);
    throw new Error(String(error));
  } finally {
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (error) {
      }
    }
  }
}

function ensureDirectory(path: string): void {
  if (exists(path)) {
    return;
  }
  try {
    fs.mkdirSync(path);
  } catch (error) {
  }
}

function removeFileQuietly(path: string): void {
  try {
    if (exists(path)) {
      fs.unlinkSync(path);
    }
  } catch (error) {
  }
}

function exists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (error) {
    return false;
  }
}

function getPending(key: string): Promise<string> | null {
  for (let i = 0; i < PENDING_GALLERY_THUMBNAILS.length; i++) {
    if (PENDING_GALLERY_THUMBNAILS[i].key === key) {
      return PENDING_GALLERY_THUMBNAILS[i].promise;
    }
  }
  return null;
}

function putPending(key: string, promise: Promise<string>): void {
  removePending(key);
  PENDING_GALLERY_THUMBNAILS.push({ key: key, promise: promise });
}

function removePending(key: string): void {
  for (let i = PENDING_GALLERY_THUMBNAILS.length - 1; i >= 0; i--) {
    if (PENDING_GALLERY_THUMBNAILS[i].key === key) {
      PENDING_GALLERY_THUMBNAILS.splice(i, 1);
    }
  }
}

function acquireGalleryThumbnailSlot(): Promise<void> {
  if (activeGalleryThumbnails < MAX_ACTIVE_GALLERY_THUMBNAILS) {
    activeGalleryThumbnails++;
    return Promise.resolve();
  }

  return new Promise<void>((resolve: (value: void | PromiseLike<void>) => void) => {
    const resume = () => {
      activeGalleryThumbnails++;
      resolve();
    };
    WAITING_GALLERY_THUMBNAILS.push(resume);
  });
}

function releaseGalleryThumbnailSlot(): void {
  activeGalleryThumbnails = Math.max(0, activeGalleryThumbnails - 1);
  const next = WAITING_GALLERY_THUMBNAILS.shift();
  if (next !== undefined) {
    next();
  }
}

function stableGalleryThumbnailKey(value: string): string {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16);
}

export const galleryThumbnailColorCache: GalleryThumbnailColorCache = new GalleryThumbnailColorCache();
