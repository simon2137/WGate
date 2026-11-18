/**
 * The sheet that asks for a tunnel's name right after an import.
 *
 * Same shape as the "Default DNS" sheet (`pages/DnsSettings.ets`): a title on the
 * left, the save icon on the right, one field, and a line of help underneath. No
 * confirm/cancel pair — the icon saves, dragging the sheet away or the back key
 * keeps the endpoint-derived name, and the help line says so with the real name.
 *
 * A body, not a dialog: the caller opens it with `bindSheet`, so the import and
 * its naming step are the same surface and the keyboard only covers empty space
 * below the help line.
 */
import { WgTunnel } from '../model/Tunnel';
import { Palette, Type, FONT } from '../theme/Theme';
import { Tr } from '../i18n/Tr';

@Component
export struct NameTunnelSheet {
  /** The tunnel exactly as it was stored; `tunnel.name` is what the help shows. */
  tunnel: WgTunnel = new WgTunnel();
  /** Called once, with the trimmed name — '' when the endpoint name is kept. */
  onDone: (name: string) => void = () => {};

  @State private text: string = '';

  build() {
    Column() {
      Row() {
        Text(Tr.t('Name this tunnel'))
          .fontSize(Type.TITLE_MEDIUM)
          .fontFamily(FONT)
          .fontColor(Palette.ON_SURFACE)
          .layoutWeight(1)
        // `Icons.Rounded.Save` as an icon button, the way every settings sheet in
        // this app saves; the word stays in the accessibility label.
        Row() {
          Image($r('app.media.ic_save'))
            .width(24)
            .height(24)
            .fillColor(Palette.PRIMARY)
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .accessibilityText(Tr.t('Save'))
        .onClick(() => {
          this.onDone(this.text.trim());
        })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8, bottom: 12 })

      // The promise the feature is about: empty is allowed, and this is the name
      // it would leave behind. It sits above the field on purpose — the keyboard
      // rises over the bottom of a bottom sheet, and this line is the one place
      // the fallback is explained.
      Text(Tr.tf('Leave it empty and the tunnel is named after its endpoint: %1$s',
        this.tunnel.name))
        .fontSize(Type.BODY_SMALL)
        .fontFamily(FONT)
        .fontColor(Palette.MUTED)
        .maxLines(2)
        .width('100%')
        .padding({ left: 24, right: 24, bottom: 10 })
        .accessibilityLevel('no')

      TextInput({ placeholder: Tr.t('Name'), text: this.text })
        .height(48)
        .margin({ left: 24, right: 24 })
        .backgroundColor(Palette.SURFACE)
        .fontSize(Type.BODY_LARGE)
        .fontFamily(FONT)
        .fontColor(Palette.ON_SURFACE)
        .placeholderColor(Palette.MUTED)
        .maxLength(64)
        .accessibilityText(Tr.t('Tunnel name'))
        .onChange((value: string) => {
          this.text = value;
        })
        .onSubmit(() => {
          this.onDone(this.text.trim());
        })
    }
    // The sheet is `SheetSize.FIT_CONTENT`: the body sizes itself instead of
    // filling the half screen a MEDIUM sheet would hand it. No `Blank()` and no
    // `height('100%')` — those are what left two thirds of the sheet empty. The
    // 48vp foot keeps the field off the sheet's rounded bottom edge.
    .width('100%')
    .padding({ bottom: 48 })
    .backgroundColor(Palette.BACKGROUND)
  }
}
