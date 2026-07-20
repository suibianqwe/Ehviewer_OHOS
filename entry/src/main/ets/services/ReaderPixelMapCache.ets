import { image } from '@kit.ImageKit';

interface CachedImageSource {
  key: string;
  imageSource: image.ImageSource;
  lastAccess: number;
}

const IMAGE_SOURCE_CACHE: CachedImageSource[] = [];
const MAX_CACHED_IMAGE_SOURCES: number = 16;

export function acquireImageSource(sourcePath: string): image.ImageSource | undefined {
  for (let i = IMAGE_SOURCE_CACHE.length - 1; i >= 0; i--) {
    if (IMAGE_SOURCE_CACHE[i].key === sourcePath) {
      IMAGE_SOURCE_CACHE[i].lastAccess = Date.now();
      const cached = IMAGE_SOURCE_CACHE.splice(i, 1)[0];
      if (cached !== undefined) {
        return cached.imageSource;
      }
    }
  }
  return undefined;
}

export function releaseImageSource(sourcePath: string, imageSource: image.ImageSource): void {
  // Evict oldest if cache is full
  while (IMAGE_SOURCE_CACHE.length >= MAX_CACHED_IMAGE_SOURCES) {
    let oldestIndex = 0;
    for (let i = 1; i < IMAGE_SOURCE_CACHE.length; i++) {
      if (IMAGE_SOURCE_CACHE[i].lastAccess < IMAGE_SOURCE_CACHE[oldestIndex].lastAccess) {
        oldestIndex = i;
      }
    }
    const evicted = IMAGE_SOURCE_CACHE[oldestIndex];
    IMAGE_SOURCE_CACHE.splice(oldestIndex, 1);
    try {
      evicted.imageSource.release();
    } catch (_error) {
    }
  }
  IMAGE_SOURCE_CACHE.push({
    key: sourcePath,
    imageSource: imageSource,
    lastAccess: Date.now()
  });
}

export function clearImageSourceCache(): void {
  while (IMAGE_SOURCE_CACHE.length > 0) {
    const entry = IMAGE_SOURCE_CACHE.pop();
    if (entry !== undefined) {
      try {
        entry.imageSource.release();
      } catch (_error) {
      }
    }
  }
}
