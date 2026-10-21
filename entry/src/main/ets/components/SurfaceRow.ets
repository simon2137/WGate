import { Palette, ROW_MIN_H, ROW_PAD_H, ROW_PAD_V, Type, FONT } from '../theme/Theme';

/**
 * The reference app's `SurfaceRow`: a full-width tile with a leading icon or
 * state dot, a title, an optional description and trailing content, all on the
 * surface colour. The optional rows below it are built by the caller.
 */
@Component
export struct SurfaceRow {
  @StorageProp('theme_tick') themeTick: number = 0;
  /**
   * Everything the caller draws has to be `@Prop`: a plain member is assigned
   * once when the child is constructed and is *not* refreshed when the parent
   * rebuilds, so a row whose trailing text comes from page state ("30s", the
   * preferred tunnel name) would keep showing the value it was born with.
   * Callbacks stay plain — they are not rendered.
   */
  @Prop title: string = '';
  @Prop description: string = '';
  @Prop icon: Resource | null = null;
  /** When set, a 14dp state dot is drawn instead of the icon. */
  @Prop dotColor: string = '';
  @Prop tint: string = Palette.ON_SURFACE;
  @Prop highlight: boolean = false;
  @Prop trailingText: string = '';
  @Prop chevron: boolean = false;
  /**
   * A trailing glyph instead of the chevron, for a row that leaves the app
   * instead of opening a page inside it (`Icons.AutoMirrored.Outlined.Launch`
   * in the reference rows).
   */
  @Prop trailingIcon: Resource | null = null;
  @Prop hasSwitch: boolean = false;
  @Prop switchOn: boolean = false;
  onSwitch: (on: boolean) => void = () => {};
  /** Named onTap because `onClick` is a built-in attribute on every component. */
  onTap: () => void = () => {};

  build() {
    Column() {
      Row() {
        if (this.dotColor.length > 0) {
          Circle()
            .width(14)
            .height(14)
            .fill(this.dotColor)
            .margin({ right: 16 })
        } else if (this.icon !== null) {
          // 24vp, the default size of a Material `Icon` in the reference rows.
          Image(this.icon)
            .width(24)
            .height(24)
            .fillColor(this.tint)
            .margin({ right: 16 })
            .draggable(false)
        }
        Text(this.title)
          .fontSize(Type.BODY_LARGE)
          .fontFamily(FONT)
          .fontColor(this.tint)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ right: 8 })
        if (this.trailingText.length > 0) {
          Text(this.trailingText)
            .fontSize(Type.BODY_MEDIUM)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
            .margin({ right: 8 })
        }
        // A row that both toggles and opens a page needs two signals, or the
        // switch reads as the only thing there and the page behind the row is
        // never found: the chevron sits before the switch.
        if (this.hasSwitch && this.chevron) {
          Image($r('app.media.ic_chevron_down'))
            .width(20)
            .height(20)
            .fillColor(Palette.MUTED)
            .rotate({ angle: 270 })
            .margin({ right: 10 })
        }
        if (this.hasSwitch) {
          Toggle({ type: ToggleType.Switch, isOn: this.switchOn })
            .selectedColor(Palette.PRIMARY)
            .switchPointColor(Palette.SURFACE)
            .onChange((on: boolean) => {
              this.onSwitch(on);
            })
        } else if (this.trailingIcon !== null) {
          // 24vp: the trailing icon of a Material row is drawn at the icon size.
          Image(this.trailingIcon)
            .width(24)
            .height(24)
            .fillColor(Palette.MUTED)
            .draggable(false)
        } else if (this.chevron) {
          Image($r('app.media.ic_chevron_down'))
            .width(20)
            .height(20)
            .fillColor(Palette.MUTED)
            .rotate({ angle: 270 })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: ROW_MIN_H })
      .alignItems(VerticalAlign.Center)

      if (this.description.length > 0) {
        Text(this.description)
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontColor(Palette.MUTED)
          .width('100%')
          .margin({ top: 2 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: ROW_PAD_V, bottom: ROW_PAD_V })
    .backgroundColor(this.highlight ? '#1A76BEBD' : Palette.SURFACE)
    .onClick(() => {
      this.onTap();
    })
  }
}

/** A section label ("General"), matching the reference's settings headers. */
@Component
export struct SectionHeader {
  @StorageProp('theme_tick') themeTick: number = 0;
  @Prop label: string = '';

  build() {
    Text(this.label)
      .fontSize(Type.LABEL_MEDIUM)
      .fontFamily(FONT)
      .fontWeight(FontWeight.Medium)
      .fontColor(Palette.MUTED)
      .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 16, bottom: 4 })
      .width('100%')
  }
}

