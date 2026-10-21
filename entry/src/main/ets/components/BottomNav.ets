import { Palette, isLightScheme } from '../theme/Theme';
import { curves } from '@kit.ArkUI';
import { Diag } from '../util/Diag';

const NAV_HEIGHT: number = 56;
const NAV_RADIUS: number = 28;
/** Ignore pointer moves smaller than this so a held press stops repainting the gradient. */
const GLOW_STEP: number = 2;
/** Gap between the screen edge and the floating capsule on each side. */
const NAV_EDGE_GAP: number = 16;
/**
 * Capsule width: the reference app floats a pill that is narrower than the
 * screen (about 74%), so `100%` + margins would add the margins outside a
 * full-width node and push it past both screen edges; instead the inset is
 * expressed as a plain percentage so the capsule centres itself. Shared with
 * the page's highlight so the two stay exactly overlaid.
 */
export const NAV_BAR_WIDTH: string = '74%';

/**
 * The bottom navigation, the one place this build deliberately differs from the
 * reference app: instead of a flat Material container it is a floating capsule
 * drawn as manual frosted glass (a blur of the content scrolling beneath plus a
 * low-alpha tint), so the bar reads as glass on every device instead of only
 * where the platform renders its own material. Everything else - four icon-only
 * tabs, the selected tint, the auto-tunnel dot - follows the original layout.
 */
@Component
export struct BottomNav {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_bottom') safeBottom: number = 40;
  @Prop selected: number = 0;
  @Prop autoActive: boolean = false;
  onSelect: (index: number) => void = () => {};
  // The highlight is drawn by the host page: a child of the node that carries
  // the glass is composited into the blur/tint layer and loses its colour, so
  // the light has to live one level up.
  onGlow: (x: number, on: boolean) => void = () => {};

  private glowX: number = -300;
  /** Fingers currently down on the bar; the light fades only when this hits zero. */
  private pointers: number = 0;
  /**
   * Press-squash of the capsule. Down compresses it towards 0.95 so it reads as
   * a material that gives under the finger; release springs it back through an
   * under-damped curve so it overshoots and settles, the familiar "bounce".
   */
  @State squash: number = 1;

  private springBack(): void {
    animateTo({ curve: curves.springMotion(0.6, 0.7) }, () => {
      this.squash = 1;
    });
  }

  private icon(index: number, on: boolean): Resource {
    if (index === 0) {
      return on ? $r('app.media.ic_home_filled') : $r('app.media.ic_home');
    }
    if (index === 1) {
      return on ? $r('app.media.ic_bolt_filled') : $r('app.media.ic_bolt');
    }
    if (index === 2) {
      return on ? $r('app.media.ic_cog_filled') : $r('app.media.ic_cog');
    }
    return on ? $r('app.media.ic_question_filled') : $r('app.media.ic_question');
  }

  @Builder
  private tabItem(index: number) {
    Stack({ alignContent: Alignment.Center }) {
      Image(this.icon(index, this.selected === index))
        .width(24)
        .height(24)
        .fillColor(this.selected === index ? Palette.PRIMARY : Palette.MUTED)
        .draggable(false)
      if (index === 1 && this.autoActive) {
        Circle()
          .width(6)
          .height(6)
          .fill(Palette.SILVER_TREE)
          .offset({ x: 12, y: -12 })
      }
    }
    .height(NAV_HEIGHT)
    .layoutWeight(1)
    .onClick(() => {
      this.onSelect(index);
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
        ForEach([0, 1, 2, 3] as number[], (index: number) => {
          this.tabItem(index);
        }, (index: number) => index.toString())
      }
      .width('100%')
      .height(NAV_HEIGHT)
      .padding({ left: 8, right: 8 })
    }
    .width(NAV_BAR_WIDTH)
    .height(NAV_HEIGHT)
    // A capsule that floats over the list instead of a bar glued to the edge.
    // The bottom inset lifts it clear of the system gesture bar in full screen.
    .borderRadius(NAV_RADIUS)
    .clip(true)
    .margin({ bottom: NAV_EDGE_GAP + this.safeBottom })
    // Custom frosted glass (canonical pattern): backdropBlur blurs the rows that
    // scroll underneath, and the translucent background supplies the visible glass
    // body. `backgroundBlurStyle` never produced blur on the target device, so an
    // explicit blur radius + semi-transparent tint is used instead.
    .backdropBlur(20)
    .backgroundColor(isLightScheme() ? '#73E9ECEF' : '#661C1B1F')
    .border({ width: 0.5, color: isLightScheme() ? '#33000000' : '#3DFFFFFF' })
    .shadow({ radius: 22, color: '#45000000', offsetX: 0, offsetY: 12 })
    // Press-squash: the whole pill scales in towards its centre, then springs
    // back through the elastic release curve in the touch handler.
    .scale({ x: this.squash, y: this.squash })
    // The glass feedback is driven by pointer events on the capsule itself.
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        // Each new finger counts separately; `touches` is unreliable on release,
        // so the light is keyed to a counter bumped per Down and drained per Up.
        this.pointers++;
        if (event.touches.length > 0) {
          this.glowX = event.touches[0].x;
        }
        this.onGlow(this.glowX, true);
        // Compress the pill while it is held.
        animateTo({ duration: 90, curve: Curve.EaseOut }, () => {
          this.squash = 0.95;
        });
        Diag.write('nav: pointer down on the glass bar');
      } else if (event.type === TouchType.Move) {
        if (event.touches.length > 0) {
          const x: number = event.touches[0].x;
          // Sub-step jitter on a held finger must not repaint the radial
          // gradient every frame; a quick flick always moves past the step.
          if (Math.abs(x - this.glowX) >= GLOW_STEP) {
            this.glowX = x;
            this.onGlow(this.glowX, true);
          }
        }
      } else if (event.type === TouchType.Up) {
        // Dim only when the last finger lifts: a second finger releasing while
        // the first is still held must not switch the light off.
        this.pointers = Math.max(0, this.pointers - 1);
        if (this.pointers === 0) {
          this.onGlow(this.glowX, false);
          this.springBack();
        }
      } else if (event.type === TouchType.Cancel) {
        this.pointers = 0;
        this.onGlow(this.glowX, false);
        this.springBack();
      }
    })
  }
}
