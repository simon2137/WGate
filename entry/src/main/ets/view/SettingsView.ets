import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Palette, Type, ROW_PAD_H, BAR_SPACE , FONT} from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { SettingsStore } from '../service/SettingsStore';
import { Tr } from '../i18n/Tr';

/**
 * The Settings tab, following the row order of `ui/screens/settings/SettingsScreen.kt`.
 * Entries that have no HarmonyOS counterpart yet say so instead of pretending.
 */
@Component
export struct SettingsView {
  @StorageProp('theme_tick') themeTick: number = 0;
  onOpenLogs: () => void = () => {};
  onOpenAppearance: () => void = () => {};
  onNote: (message: string) => void = () => {};

  aboutToAppear(): void {
    // The row writes through the same store as the pages, so the component must
    // open it too: without init the write would silently do nothing.
    SettingsStore.init(getContext(this) as common.UIAbilityContext);
  }

  build() {
    Column() {
      Row() {
        Text(Tr.t('Settings'))
          .fontSize(Type.TITLE_LARGE)
          .fontFamily(FONT)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.ON_SURFACE)
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: ROW_PAD_H, right: ROW_PAD_H })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          SurfaceRow({
            title: Tr.t('DNS settings'),
            description: Tr.t('Resolvers handed to the tunnel'),
            icon: $r('app.media.ic_dns'),
            chevron: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/DnsSettings' });
            }
          })
          SurfaceRow({
            title: Tr.t('Tunnel globals'),
            description: Tr.t('MTU, keepalive and interface defaults'),
            icon: $r('app.media.ic_globe'),
            chevron: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/TunnelGlobals' });
            }
          })
          SurfaceRow({
            title: Tr.t('Tunnel recovery'),
            description: Tr.t('Reconnect when the network changes'),
            icon: $r('app.media.ic_autorenew'),
            chevron: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/TunnelRecovery' });
            }
          })

          SurfaceRow({
            title: Tr.t('Tunnel monitoring'),
            description: Tr.t('Live statistics and their refresh rate'),
            icon: $r('app.media.ic_monitor_heart'),
            chevron: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/Monitoring' });
            }
          })

          SectionHeader({ label: Tr.t('General') })

          SurfaceRow({
            title: Tr.t('Appearance'),
            description: Tr.t('Theme and colours'),
            icon: $r('app.media.ic_view_quilt'),
            chevron: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/Appearance' });
            }
          })
          SurfaceRow({
            title: Tr.t('Security'),
            description: Tr.t('PIN lock and biometrics'),
            icon: $r('app.media.ic_security'),
            chevron: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/Security' });
            }
          })
          SurfaceRow({
            title: Tr.t('Local logging'),
            description: Tr.t('Engine and startup trace'),
            icon: $r('app.media.ic_view_headline'),
            chevron: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/Logs' });
            }
          })
          SurfaceRow({
            title: Tr.t('Backup and restore'),
            description: Tr.t('Export tunnels as a file'),
            icon: $r('app.media.ic_backup_restore'),
            chevron: true,
            onTap: () => {
              router.pushUrl({ url: 'pages/Backup' });
            }
          })
        }
        .width('100%')
        .padding({ bottom: BAR_SPACE })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
  }
}

