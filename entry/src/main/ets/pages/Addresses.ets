import { router } from '@kit.ArkUI';
import { common, Want } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { Palette, Type, ROW_PAD_H, BAR_SPACE, FONT } from '../theme/Theme';
import { SurfaceRow, SectionHeader } from '../components/SurfaceRow';
import { Tr } from '../i18n/Tr';

/**
 * `support/donate/crypto/Address.kt`: the same thirteen coins, in the same
 * order, with the same addresses. Tapping a row copies it.
 */
interface Coin {
  name: string;
  address: string;
}

const COINS: Coin[] = [
  { name: 'Bitcoin (BTC)', address: 'bc1qu6dwlwhav7cwp5gv3kyv3cpwrjrra80p75js6u' },
  { name: 'Bitcoin Lightning', address: 'wgtunnel@cake.cash' },
  {
    name: 'Monero (XMR)',
    address: '44D1vWL4CqmEGiRhwtUy6MT2SgaCYpk5o3Nh6YxBFyoCXLZ5eZMLiDGj9uoo51mGjeiLxHWyV28MxDPUzQZN4PoqML16ZB9'
  },
  { name: 'Ethereum (ETH)', address: '0xd711c24D0E355d9D694F60B42FdDAFd8653D2786' },
  {
    name: 'Zcash (ZEC)',
    address: 'u1fkx80l0mr7cgzmj5xusnf4fa0hlvttaedlqjzl657dyyfqq4tzq49v4ru53u8re0kfnlah7s363msewcva43v8a2' +
      'rn8zqs56jeeu6m7snrfljs343kfkgv7gsa76xg005wz95855uwlrvgan0er8n3sp75mmmj44n3fnjar5y7jy0pd2k5yw' +
      '33lgwpuectuknkwstdkkfyqvxh9xq6c'
  },
  { name: 'Litecoin (LTC)', address: 'ltc1q983jnz3n2zshp2xyme8ant45aah5hv337k8nm7' },
  { name: 'eCash (XEC)', address: 'ecash:qrnnvzhezgm9unazue2mw7np5qhdk2874g996nd2zw' },
  { name: 'Polygon (POL)', address: '0xd711c24D0E355d9D694F60B42FdDAFd8653D2786' },
  { name: 'Avalanche (AVAX)', address: '0xd711c24D0E355d9D694F60B42FdDAFd8653D2786' },
  { name: 'Solana (SOL)', address: '5qPMZa2Y2R6D6AUzrofS4o2M1nzNpbMiAkcRcBkjsmwQ' },
  { name: 'Stellar (XLM)', address: 'GAOHREIPAOKSTD4ELXCMM7LDZPRGKJ2DNHEIXLU752PJS6CDPBAEM75B' },
  { name: 'Tron (TRX)', address: 'TCbR2SqstTLxCA9zp52iC7G2DfHUGD9ak2' },
  { name: 'Bitcoin Cash (BCH)', address: 'bitcoincash:qp6xacvswha2tjfp2rscguq3gd4eecxeuvcgtyjv58' }
];

@Entry
@Component
struct Addresses {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State toast: string = '';

  private copy(text: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setDataSync(data);
    this.flash('Address copied');
  }

  private flash(message: string): void {
    this.toast = message;
    setTimeout(() => {
      this.toast = '';
    }, 1400);
  }

  build() {
    Stack() {
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
            Text(Tr.t('Donate'))
              .fontSize(Type.TITLE_LARGE)
              .fontFamily(FONT)
              .fontWeight(FontWeight.Medium)
              .fontColor(Palette.ON_SURFACE)
            Text(Tr.t('Tap an address to copy it'))
              .fontSize(Type.BODY_SMALL)
              .fontFamily(FONT)
              .fontColor(Palette.MUTED)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .height(64)
        .padding({ left: ROW_PAD_H, right: ROW_PAD_H })
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            SectionHeader({ label: Tr.t('Cryptocurrency addresses') })

            ForEach(COINS, (coin: Coin) => {
              Column() {
                Text(coin.name)
                  .fontSize(Type.BODY_MEDIUM)
                  .fontFamily(FONT)
                  .fontColor(Palette.ON_SURFACE)
                  .width('100%')
                Text(coin.address)
                  .fontSize(Type.BODY_SMALL)
                  .fontFamily(FONT)
                  .fontColor(Palette.MUTED)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 10, bottom: 10 })
              .backgroundColor(Palette.SURFACE)
              .onClick(() => {
                this.copy(coin.address);
              })
            }, (coin: Coin) => coin.name)

            Column().height(BAR_SPACE)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Palette.BACKGROUND)

      if (this.toast.length > 0) {
        Row() {
          Text(this.toast)
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.ON_SURFACE)
        }
        .backgroundColor(Palette.RAISED)
        .borderRadius(20)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .margin({ bottom: 40 })
        .align(Alignment.Bottom)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.safeTop })
  }
}
