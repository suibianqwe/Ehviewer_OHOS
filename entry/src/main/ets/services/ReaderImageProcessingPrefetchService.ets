import { image } from '@kit.ImageKit';
import { readerHdrService } from './ReaderHdrService';
import { readerSuperResolutionService } from './ReaderSuperResolutionService';

export interface ReaderImageProcessingPrefetchPlan {
  id: string;
  sourcePath: string;
  superResolutionKey: string;
  hdrKey: string;
  fallbackHdrKey: string;
  superResolution: boolean;
  hdr: boolean;
  priority: number;
}

class ReaderImageProcessingReservation {
  id: string;
  sourcePath: string;
  superResolutionKey: string;
  hdrKey: string;
  fallbackHdrKey: string;
  retainedHdrKey: string = '';
  superResolution: boolean;
  hdr: boolean;
  priority: number;
  active: boolean = true;
  superResolutionRetained: boolean = false;
  hdrRetained: boolean = false;

  constructor(plan: ReaderImageProcessingPrefetchPlan) {
    this.id = plan.id;
    this.sourcePath = plan.sourcePath;
    this.superResolutionKey = plan.superResolutionKey;
    this.hdrKey = plan.hdrKey;
    this.fallbackHdrKey = plan.fallbackHdrKey;
    this.superResolution = plan.superResolution;
    this.hdr = plan.hdr;
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
    if (reservation.superResolution) {
      reservation.superResolutionRetained = true;
      readerSuperResolutionService.acquire(reservation.superResolutionKey, reservation.sourcePath,
        reservation.priority).then((pixelMap: image.PixelMap | undefined) => {
        if (!reservation.active || !reservation.hdr) {
          return;
        }
        if (pixelMap === undefined) {
          this.startFallbackHdr(reservation);
          return;
        }
        reservation.retainedHdrKey = reservation.hdrKey;
        reservation.hdrRetained = true;
        readerHdrService.acquirePixelMap(reservation.retainedHdrKey, pixelMap,
          reservation.priority).catch(() => {});
      }).catch(() => {
        this.startFallbackHdr(reservation);
      });
      return;
    }
    if (reservation.hdr) {
      reservation.retainedHdrKey = reservation.fallbackHdrKey;
      reservation.hdrRetained = true;
      readerHdrService.acquire(reservation.retainedHdrKey, reservation.sourcePath,
        reservation.priority).catch(() => {});
    }
  }

  private startFallbackHdr(reservation: ReaderImageProcessingReservation): void {
    if (!reservation.active || !reservation.hdr || reservation.hdrRetained) {
      return;
    }
    reservation.retainedHdrKey = reservation.fallbackHdrKey;
    reservation.hdrRetained = true;
    readerHdrService.acquire(reservation.retainedHdrKey, reservation.sourcePath,
      reservation.priority).catch(() => {});
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
