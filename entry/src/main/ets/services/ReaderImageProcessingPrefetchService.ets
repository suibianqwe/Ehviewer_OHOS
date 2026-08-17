import { image } from '@kit.ImageKit';
import { readerHdrService } from './ReaderHdrService';
import { readerImageAdjustmentService } from './ReaderImageAdjustmentService';
import { ReaderImageAdjustmentSettings } from './ReaderImageAdjustmentSupport';
import { readerSuperResolutionService } from './ReaderSuperResolutionService';

export interface ReaderImageProcessingPrefetchPlan {
  id: string;
  sourcePath: string;
  superResolutionKey: string;
  hdrKey: string;
  fallbackHdrKey: string;
  adjustmentKey: string;
  fallbackAdjustmentKey: string;
  adjustmentSettings: ReaderImageAdjustmentSettings;
  targetWidth: number;
  targetHeight: number;
  superResolutionEngine: string;
  superResolution: boolean;
  hdr: boolean;
  adjustment: boolean;
  priority: number;
}

class ReaderImageProcessingReservation {
  id: string;
  sourcePath: string;
  superResolutionKey: string;
  hdrKey: string;
  fallbackHdrKey: string;
  adjustmentKey: string;
  fallbackAdjustmentKey: string;
  adjustmentSettings: ReaderImageAdjustmentSettings;
  targetWidth: number;
  targetHeight: number;
  superResolutionEngine: string;
  retainedHdrKey: string = '';
  retainedAdjustmentKey: string = '';
  superResolution: boolean;
  hdr: boolean;
  adjustment: boolean;
  priority: number;
  active: boolean = true;
  superResolutionRetained: boolean = false;
  hdrRetained: boolean = false;
  adjustmentRetained: boolean = false;

  constructor(plan: ReaderImageProcessingPrefetchPlan) {
    this.id = plan.id;
    this.sourcePath = plan.sourcePath;
    this.superResolutionKey = plan.superResolutionKey;
    this.hdrKey = plan.hdrKey;
    this.fallbackHdrKey = plan.fallbackHdrKey;
    this.adjustmentKey = plan.adjustmentKey;
    this.fallbackAdjustmentKey = plan.fallbackAdjustmentKey;
    this.adjustmentSettings = plan.adjustmentSettings;
    this.targetWidth = plan.targetWidth;
    this.targetHeight = plan.targetHeight;
    this.superResolutionEngine = plan.superResolutionEngine;
    this.superResolution = plan.superResolution;
    this.hdr = plan.hdr;
    this.adjustment = plan.adjustment;
    this.priority = plan.priority;
  }
}

/**
 * Holds processed PixelMaps for the whole reader prerender range.
 * View components may be recycled by Swiper, so their references alone cannot
 * define the lifetime of expensive super-resolution and HDR results.
 */
export class ReaderImageProcessingPrefetchScope {
  private reservations: ReaderImageProcessingReservation[] = [];

  sync(plans: ReaderImageProcessingPrefetchPlan[]): void {
    for (let i = this.reservations.length - 1; i >= 0; i--) {
      if (!this.containsPlan(plans, this.reservations[i].id)) {
        this.releaseReservation(this.reservations[i]);
        this.reservations.splice(i, 1);
      }
    }
    for (let i = 0; i < plans.length; i++) {
      const existing = this.findReservation(plans[i].id);
      if (existing !== null) {
        this.updatePriority(existing, plans[i].priority);
        continue;
      }
      const reservation = new ReaderImageProcessingReservation(plans[i]);
      this.reservations.push(reservation);
      this.startReservation(reservation);
    }
  }

  clear(): void {
    for (let i = 0; i < this.reservations.length; i++) {
      this.releaseReservation(this.reservations[i]);
    }
    this.reservations = [];
  }

  private startReservation(reservation: ReaderImageProcessingReservation): void {
    this.startPipeline(reservation).catch(() => {});
  }

  private async startPipeline(reservation: ReaderImageProcessingReservation): Promise<void> {
    let pixelMap: image.PixelMap | undefined = undefined;
    let pixelMapKey: string = '';
    if (reservation.superResolution) {
      reservation.superResolutionRetained = true;
      try {
        pixelMap = await readerSuperResolutionService.acquire(reservation.superResolutionKey, reservation.sourcePath,
          reservation.priority, reservation.targetWidth, reservation.targetHeight, reservation.superResolutionEngine);
        if (pixelMap !== undefined) {
          pixelMapKey = reservation.superResolutionKey;
        }
      } catch (_error) {
        pixelMap = undefined;
      }
    }
    if (!reservation.active) {
      return;
    }
    if (reservation.adjustment) {
      reservation.adjustmentRetained = true;
      const activeAdjustmentKey = pixelMap !== undefined ? reservation.adjustmentKey :
        reservation.fallbackAdjustmentKey;
      reservation.retainedAdjustmentKey = activeAdjustmentKey;
      try {
        const adjusted = pixelMap !== undefined ?
          await readerImageAdjustmentService.acquirePixelMap(activeAdjustmentKey, pixelMap,
            reservation.adjustmentSettings, reservation.priority) :
          await readerImageAdjustmentService.acquire(activeAdjustmentKey, reservation.sourcePath,
            reservation.adjustmentSettings, reservation.priority);
        if (adjusted !== undefined) {
          pixelMap = adjusted;
          pixelMapKey = activeAdjustmentKey;
        }
      } catch (_error) {
      }
    }
    if (!reservation.active || !reservation.hdr) {
      return;
    }
    reservation.retainedHdrKey = pixelMap !== undefined && pixelMapKey.length > 0 ?
      pixelMapKey + '|hdr' : reservation.fallbackHdrKey;
    reservation.hdrRetained = true;
    if (pixelMap !== undefined) {
      readerHdrService.acquirePixelMap(reservation.retainedHdrKey, pixelMap, reservation.priority).catch(() => {});
    } else {
      readerHdrService.acquire(reservation.retainedHdrKey, reservation.sourcePath, reservation.priority).catch(() => {});
    }
  }

  private updatePriority(reservation: ReaderImageProcessingReservation, priority: number): void {
    if (reservation.priority === priority) {
      return;
    }
    reservation.priority = priority;
    if (reservation.superResolutionRetained) {
      readerSuperResolutionService.updatePriority(reservation.superResolutionKey, priority);
    }
    if (reservation.hdrRetained) {
      readerHdrService.updatePriority(reservation.retainedHdrKey, priority);
    }
    if (reservation.adjustmentRetained) {
      readerImageAdjustmentService.updatePriority(reservation.retainedAdjustmentKey, priority);
    }
  }

  private releaseReservation(reservation: ReaderImageProcessingReservation): void {
    if (!reservation.active) {
      return;
    }
    reservation.active = false;
    if (reservation.hdrRetained) {
      readerHdrService.release(reservation.retainedHdrKey);
      reservation.hdrRetained = false;
      reservation.retainedHdrKey = '';
    }
    if (reservation.adjustmentRetained) {
      readerImageAdjustmentService.release(reservation.retainedAdjustmentKey);
      reservation.adjustmentRetained = false;
      reservation.retainedAdjustmentKey = '';
    }
    if (reservation.superResolutionRetained) {
      readerSuperResolutionService.release(reservation.superResolutionKey);
      reservation.superResolutionRetained = false;
    }
  }

  private containsPlan(plans: ReaderImageProcessingPrefetchPlan[], id: string): boolean {
    for (let i = 0; i < plans.length; i++) {
      if (plans[i].id === id) {
        return true;
      }
    }
    return false;
  }

  private findReservation(id: string): ReaderImageProcessingReservation | null {
    for (let i = 0; i < this.reservations.length; i++) {
      if (this.reservations[i].id === id) {
        return this.reservations[i];
      }
    }
    return null;
  }
}
