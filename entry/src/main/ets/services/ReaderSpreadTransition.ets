export interface ReaderSpreadGeometry {
  scale: number;
  firstX: number;
  firstY: number;
  secondX: number;
  secondY: number;
  joinX: number;
  joinY: number;
  outsideX: number;
}

export function readerSpreadGeometry(width: number, height: number, firstWidth: number, firstHeight: number,
  secondWidth: number, secondHeight: number, reversed: boolean, startPosition: string = 'Center'): ReaderSpreadGeometry {
  const w = Math.max(1, width);
  const h = Math.max(1, height);
  const firstFit = Math.min(w / Math.max(1, firstWidth), h / Math.max(1, firstHeight));
  const secondFit = Math.min(w / Math.max(1, secondWidth), h / Math.max(1, secondHeight));
  const fw = Math.max(1, firstWidth * firstFit);
  const fh = Math.max(1, firstHeight * firstFit);
  const sw = Math.max(1, secondWidth * secondFit);
  const sh = Math.max(1, secondHeight * secondFit);
  const vertical = h >= w;
  const scale = Math.min(1, vertical ? h / (fh + sh) : w / (fw + sw));
  const sign: number = reversed ? -1 : 1;
  const factorX = startPosition.endsWith('left') ? -0.5 : (startPosition.endsWith('right') ? 0.5 : 0);
  const factorY = startPosition.startsWith('Top') ? -0.5 : (startPosition.startsWith('Bottom') ? 0.5 : 0);
  const firstOffsetX = (w - fw) * factorX;
  const firstOffsetY = (h - fh) * factorY;
  const secondOffsetX = (w - sw) * factorX;
  const secondOffsetY = (h - sh) * factorY;
  return {
    scale: scale,
    firstX: (vertical ? 0 : -sign * sw * scale / 2) - firstOffsetX * scale,
    firstY: (vertical ? -sh * scale / 2 : 0) - firstOffsetY * scale,
    secondX: (vertical ? 0 : sign * fw * scale / 2) - secondOffsetX * scale,
    secondY: (vertical ? fh * scale / 2 : 0) - secondOffsetY * scale,
    joinX: (vertical ? 0 : sign * (fw + sw) / 2) + firstOffsetX - secondOffsetX,
    joinY: (vertical ? (fh + sh) / 2 : 0) + firstOffsetY - secondOffsetY,
    outsideX: sign * Math.max(w, (w + sw) / 2 + 1)
  };
}

@Observed
export class ReaderSpreadMotion {
  phase: string = 'single';
  scale: number = 1;
  firstX: number = 0;
  firstY: number = 0;
  secondX: number = 0;
  secondY: number = 0;

  reset(): void {
    this.phase = 'single';
    this.scale = 1;
    this.firstX = 0;
    this.firstY = 0;
    this.secondX = 0;
    this.secondY = 0;
  }

  prepare(geometry: ReaderSpreadGeometry): void {
    this.reset();
    this.phase = 'waiting';
    this.secondX = geometry.outsideX;
    this.secondY = geometry.joinY;
  }

  join(geometry: ReaderSpreadGeometry): void {
    this.phase = 'joining';
    this.secondX = geometry.joinX;
    this.secondY = geometry.joinY;
  }

  settle(geometry: ReaderSpreadGeometry): void {
    this.phase = 'settling';
    this.scale = geometry.scale;
    this.firstX = geometry.firstX;
    this.firstY = geometry.firstY;
    this.secondX = geometry.secondX;
    this.secondY = geometry.secondY;
  }

  finish(): void {
    this.phase = 'paired';
  }
}
