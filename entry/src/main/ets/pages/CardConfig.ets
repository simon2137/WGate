/**
 * The desktop card's tunnel picker.
 *
 * The launcher opens this page from the card's long-press menu (the form config
 * declares `formConfigAbility`, see resources/base/profile/wg_card.json) and
 * hands the edited card's id to EntryAbility, which routes here with it.
 *
 * The choice is written to CardRegistry and the card is redrawn immediately; the
 * page then closes, because the card is the thing the user was looking at.
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { WgTunnel } from '../model/Tunnel';
import { Palette, Type, FONT } from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { TunnelStore } from '../service/TunnelStore';
import { CardRegistry } from '../form/CardRegistry';
import { CardRefresh } from '../form/CardRefresh';
import { Tr } from '../i18n/Tr';

@Entry
@Component
struct CardConfig {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State tunnels: WgTunnel[] = [];
  @State formId: string = '';
  @State chosen: string = '';
  // Resolved once: SurfaceRow takes plain strings, so the labels cannot be
  // handed to it as resources.
  @State title: string = '';
  @State subtitle: string = '';
  @State follow: string = '';
  @State followDesc: string = '';

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    TunnelStore.init(context);
    const params = router.getParams() as Record<string, string>;
    if (params !== undefined && params !== null && params['formId'] !== undefined) {
      this.formId = params['formId'];
    }
    this.tunnels = TunnelStore.list();
    this.chosen = CardRegistry.tunnelOf(this.formId);
    this.title = this.text(context, $r('app.string.card_config_title').id);
    this.subtitle = this.text(context, $r('app.string.card_config_subtitle').id);
    this.follow = this.text(context, $r('app.string.card_config_follow').id);
    this.followDesc = this.text(context, $r('app.string.card_config_follow_desc').id);
  }

  /** One string resource as text, '' when the id does not resolve. */
  private text(context: common.UIAbilityContext, id: number): string {
    try {
      return context.resourceManager.getStringSync(id);
    } catch (err) {
      return '';
    }
  }

  /** Writes the choice, redraws that card, and gets out of the way. */
  private pick(id: string): void {
    if (this.formId.length === 0) {
      router.back();
      return;
    }
    this.chosen = id;
    CardRegistry.bind(this.formId, id);
    CardRefresh.all(getContext(this) as common.UIAbilityContext).catch(() => {
      // The card is redrawn again on the next tick anyway; a refusal from the
      // launcher must not keep this page on screen.
    });
    router.back();
  }

  build() {
    Column() {
      Row() {
        Row() {
          Image($r('app.media.ic_back'))
            .width(24)
            .height(24)
            .fillColor(Palette.ON_SURFACE)
        }
        .width(48)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          router.back();
        })

        Column() {
          Text(this.title)
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
          Text(this.subtitle)
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ right: 16 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          SectionHeader({ label: Tr.t('Tunnels') })

          ForEach(this.tunnels, (tunnel: WgTunnel) => {
            SurfaceRow({
              title: tunnel.name,
              description: tunnel.endpoint(),
              dotColor: this.chosen === tunnel.id ? Palette.PRIMARY : Palette.MUTED,
              trailingText: this.chosen === tunnel.id ? Tr.t('Selected') : '',
              onTap: () => {
                this.pick(tunnel.id);
              }
            })
          }, (tunnel: WgTunnel) => `${tunnel.id}-${this.chosen === tunnel.id}`)

          SurfaceRow({
            title: this.follow,
            description: this.followDesc,
            dotColor: this.chosen.length === 0 ? Palette.PRIMARY : Palette.MUTED,
            trailingText: this.chosen.length === 0 ? Tr.t('Selected') : '',
            onTap: () => {
              this.pick('');
            }
          })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.safeTop })
    .backgroundColor(Palette.BACKGROUND)
  }
}
