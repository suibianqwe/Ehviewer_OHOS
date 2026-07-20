import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { GalleryPreview } from '../model/GalleryModels';
import {
  IMAGE_DOWNLOAD_PRIORITY_BACKGROUND,
  readerImageCache,
  readerImageCacheDirectory
} from './ReaderImageCache';
import { acquireImageSource, releaseImageSource } from './ReaderPixelMapCache';

interface PendingPreviewCrop {
  key: string;
  promise: Promise<string>;
}

const PENDING_PREVIEW_CROPS: PendingPreviewCrop[] = [];
const WAITING_PREVIEW_CROPS: (() => void)[] = [];
const MAX_ACTIVE_PREVIEW_CROPS: number = 4;
let activePreviewCrops: number = 0;

export class PreviewThumbnailCache {
  async ensureCropped(context: common.UIAbilityContext, preview: GalleryPreview, referer: string): Promise<string> {
    if (preview.imageUrl.length === 0) {
      return '';
    }
    if (!canCropPreview(preview)) {
      return readerImageCache.ensureCached(context, preview.imageUrl, referer, IMAGE_DOWNLOAD_PRIORITY_BACKGROUND);
    }

    const path = this.pathFor(context, preview);
    if (exists(path)) {
      return path;
    }

    const pending = getPending(path);
    if (pending !== null) {
      return pending;
    }

    const promise = this.crop(context, preview, referer, path);
    putPending(path, promise);
    try {
      return await promise;
    } finally {
      removePending(path);
    }
  }

  getCroppedPath(context: common.UIAbilityContext, preview: GalleryPreview): string {
    if (preview.imageUrl.length === 0 || !canCropPreview(preview)) {
      return '';
    }

    const path = this.pathFor(context, preview);
    return exists(path) ? path : '';
  }

  private async crop(context: common.UIAbilityContext, preview: GalleryPreview, referer: string,
    outputPath: string): Promise<string> {
    const sourcePath = await readerImageCache.ensureCached(context, preview.imageUrl, referer,
      IMAGE_DOWNLOAD_PRIORITY_BACKGROUND);
    if (sourcePath.length === 0) {
      return '';
    }

    ensureDirectory(readerImageCacheDirectory(context));
    await acquirePreviewCropSlot();
    let imageSource: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    let imagePacker: image.ImagePacker | undefined = undefined;
    let cachedSource: boolean = false;
    try {
      const reused = acquireImageSource(sourcePath);
      if (reused !== undefined) {
        imageSource = reused;
        cachedSource = true;
      } else {
        imageSource = image.createImageSource(sourcePath);
      }
      const options: image.DecodingOptions = {
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredRegion: {
          x: Math.max(0, preview.xOffset),
          y: Math.max(0, preview.yOffset),
          size: {
            width: Math.max(1, preview.width),
            height: Math.max(1, preview.height)
          }
        },
        cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST,
        index: 0
      };
      pixelMap = await imageSource.createPixelMap(options);
      imagePacker = image.createImagePacker();
      const packOptions: image.PackingOption = { format: 'image/png', quality: 100 };
      const data = await imagePacker.packToData(pixelMap, packOptions);
      writeArrayBuffer(outputPath, data);
      return outputPath;
    } catch (error) {
      removeFileQuietly(outputPath);
      throw new Error(String(error));
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
        if (cachedSource) {
          releaseImageSource(sourcePath, imageSource);
        } else {
          try {
            await imageSource.release();
          } catch (error) {
          }
        }
      }
      releasePreviewCropSlot();
    }
  }

  private pathFor(context: common.UIAbilityContext, preview: GalleryPreview): string {
    const key = preview.imageUrl + '#' + preview.xOffset.toString() + ',' + preview.yOffset.toString() + ',' +
      preview.width.toString() + 'x' + preview.height.toString();
    return readerImageCacheDirectory(context) + '/preview_png_' + stablePreviewKey(key) + '.png';
  }
}

function canCropPreview(preview: GalleryPreview): boolean {
  return preview.width > 0 && preview.height > 0;
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
  for (let i = 0; i < PENDING_PREVIEW_CROPS.length; i++) {
    if (PENDING_PREVIEW_CROPS[i].key === key) {
      return PENDING_PREVIEW_CROPS[i].promise;
    }
  }
  return null;
}

function putPending(key: string, promise: Promise<string>): void {
  removePending(key);
  PENDING_PREVIEW_CROPS.push({ key: key, promise: promise });
}

function removePending(key: string): void {
  for (let i = PENDING_PREVIEW_CROPS.length - 1; i >= 0; i--) {
    if (PENDING_PREVIEW_CROPS[i].key === key) {
      PENDING_PREVIEW_CROPS.splice(i, 1);
    }
  }
}

function acquirePreviewCropSlot(): Promise<void> {
  if (activePreviewCrops < MAX_ACTIVE_PREVIEW_CROPS) {
    activePreviewCrops++;
    return Promise.resolve();
  }

  return new Promise<void>((resolve: (value: void | PromiseLike<void>) => void) => {
    const resume = () => {
      activePreviewCrops++;
      resolve();
    };
    WAITING_PREVIEW_CROPS.push(resume);
  });
}

function releasePreviewCropSlot(): void {
  activePreviewCrops = Math.max(0, activePreviewCrops - 1);
  const next = WAITING_PREVIEW_CROPS.shift();
  if (next !== undefined) {
    next();
  }
}

function stablePreviewKey(value: string): string {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16);
}

export const previewThumbnailCache: PreviewThumbnailCache = new PreviewThumbnailCache();
