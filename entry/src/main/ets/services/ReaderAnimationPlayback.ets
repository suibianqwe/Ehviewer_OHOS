// Keep static pre-rendering, but never mount an offscreen animated Image.
// Native Image owns frame scheduling; descriptor teardown can block the UI thread.
@Observed
export class ReaderAnimationPlayback {
  frameCount: number = 0;

  reset(): void {
    this.frameCount = 0;
  }

  classify(frameCount: number): void {
    this.frameCount = frameCount;
  }

  shouldMountImage(visible: boolean): boolean {
    // Unknown offscreen sources wait for asynchronous metadata classification.
    return visible || this.frameCount === 1;
  }
}
