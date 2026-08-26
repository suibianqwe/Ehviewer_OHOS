import { themeScrimColor } from '../shared/EhTheme';

/**
 * Draws a modal scrim while leaving the translucent popup itself uncovered.
 * This prevents ArkUI blur/material effects from sampling the gray scrim below.
 */
@Component
export struct PopupScrim {
  @Prop showCutout: boolean = false;
  @Prop cutoutWidth: Length = 0;
  @Prop cutoutHeight: Length = 0;
  @Prop cutoutRadius: number = 0;
  @Prop positionedCutout: boolean = false;
  @Prop cutoutX: Length = 0;
  @Prop cutoutY: Length = 0;
  @Prop scrimOpacity: number = 1;
  @Prop scrimColor: string = '';
  onDismiss: () => void = () => {};

  private resolvedScrimColor(): string {
    return this.scrimColor.length > 0 ? this.scrimColor : themeScrimColor();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Stack() {}
        .width('100%')
        .height('100%')
        .backgroundColor(this.resolvedScrimColor())
        .opacity(this.scrimOpacity)

      if (this.showCutout) {
        if (this.positionedCutout) {
          Stack() {}
            .width(this.cutoutWidth)
            .height(this.cutoutHeight)
            .backgroundColor(Color.Black)
            .borderRadius(this.cutoutRadius)
            .position({ x: this.cutoutX, y: this.cutoutY })
            .blendMode(BlendMode.DST_OUT)
        } else {
          Stack() {}
            .width(this.cutoutWidth)
            .height(this.cutoutHeight)
            .backgroundColor(Color.Black)
            .borderRadius(this.cutoutRadius)
            .blendMode(BlendMode.DST_OUT)
        }
      }
    }
    .width('100%')
    .height('100%')
    .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
    .onClick(() => {
      this.onDismiss();
    })
  }
}
