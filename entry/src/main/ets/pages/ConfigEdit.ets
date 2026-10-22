import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { Palette, Type, ROW_PAD_H, BAR_SPACE, FONT } from '../theme/Theme';
import { SectionHeader } from '../components/SurfaceRow';
import { SettingsStore } from '../service/SettingsStore';
import { TunnelStore } from '../service/TunnelStore';
import { WgTunnel, WgPeer, toWgQuick } from '../model/Tunnel';
import { Diag } from '../util/Diag';
import { Tr } from '../i18n/Tr';

/** One labelled input, matching the reference's ConfigurationTextBox. */
@Builder
function field(label: string, value: string, hint: string, secret: boolean,
               onEdit: (v: string) => void, action: string, onAction: () => void) {
  Column() {
    Text(label)
      .fontSize(Type.BODY_SMALL)
      .fontFamily(FONT)
      .fontColor(Palette.MUTED)
      .width('100%')
    Row() {
      TextInput({ text: value, placeholder: hint })
        .fontSize(Type.BODY_MEDIUM)
        .fontFamily(FONT)
        .fontColor(Palette.ON_SURFACE)
        .placeholderColor(Palette.OUTLINE)
        .backgroundColor(Palette.RAISED)
        .borderRadius(8)
        .height(44)
        .type(secret ? InputType.Password : InputType.Normal)
        .layoutWeight(1)
        .onChange((v: string) => {
          onEdit(v);
        })
      if (action.length > 0) {
        Text(action)
          .fontSize(Type.LABEL_MEDIUM)
          .fontFamily(FONT)
          .fontColor(Palette.PRIMARY)
          .margin({ left: 12 })
          .onClick(() => {
            onAction();
          })
      }
    }
    .width('100%')
  }
  .alignItems(HorizontalAlign.Start)
  .width('100%')
}

/**
 * `ui/screens/tunnels/settings/config/edit/ConfigEditScreen.kt`: the form behind
 * the Edit action on the configuration screen - interface, DNS/MTU, the wg-quick
 * hooks and every peer, with add and remove.
 */
@Entry
@Component
struct ConfigEdit {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State tunnelId: string = '';
  @State name: string = '';
  @State privateKey: string = '';
  @State publicKey: string = '';
  @State addresses: string = '';
  @State listenPort: string = '';
  @State dns: string = '';
  @State mtu: string = '';
  @State excludedApps: string = '';
  @State preUp: string = '';
  @State postUp: string = '';
  @State preDown: string = '';
  @State postDown: string = '';
  @State peers: WgPeer[] = [];
  @State showSensitive: boolean = false;
  @State showScripts: boolean = false;
  @State showAmnezia: boolean = false;
  @State awg: boolean = false;
  @State jc: string = '';
  @State jmin: string = '';
  @State jmax: string = '';
  @State s1: string = '';
  @State s2: string = '';
  @State s3: string = '';
  @State h1: string = '';
  @State h2: string = '';
  @State h3: string = '';
  @State h4: string = '';
  @State toast: string = '';

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    SettingsStore.init(context);
    TunnelStore.init(context);
    Diag.init(context);
    const params = router.getParams() as Record<string, string>;
    if (params !== undefined && params !== null && params.id !== undefined) {
      this.tunnelId = params.id;
    }
    this.load();
  }

  private load(): void {
    const t: WgTunnel | null = TunnelStore.find(this.tunnelId);
    if (t === null) {
      return;
    }
    this.name = t.name;
    this.privateKey = t.privateKey;
    this.publicKey = t.publicKey;
    this.addresses = t.address;
    this.listenPort = t.listenPort > 0 ? t.listenPort.toString() : '';
    this.dns = t.dns;
    this.mtu = t.mtu > 0 ? t.mtu.toString() : '';
    this.excludedApps = t.excludedApps;
    this.preUp = t.preUp;
    this.postUp = t.postUp;
    this.preDown = t.preDown;
    this.postDown = t.postDown;
    this.awg = t.awg;
    this.jc = t.jc.toString();
    this.jmin = t.jmin.toString();
    this.jmax = t.jmax.toString();
    this.s1 = t.s1.toString();
    this.s2 = t.s2.toString();
    this.s3 = t.s3.toString();
    this.h1 = t.h1.toString();
    this.h2 = t.h2.toString();
    this.h3 = t.h3.toString();
    this.h4 = t.h4.toString();
    this.peers = t.peers.map((p: WgPeer) => p.clone());
  }

  private static number(value: string, fallback: number): number {
    const n: number = Number.parseInt(value.trim(), 10);
    return Number.isNaN(n) ? fallback : n;
  }

  private flash(message: string): void {
    this.toast = message;
    setTimeout(() => {
      if (this.toast === message) {
        this.toast = '';
      }
    }, 2400);
  }

  /** A fresh Curve25519 pair, the same rotate action as the reference. */
  private async rotateKeys(): Promise<void> {
    try {
      const generator = cryptoFramework.createAsyKeyGenerator('X25519');
      const pair = await generator.generateKeyPair();
      const priv: cryptoFramework.DataBlob = await (pair.priKey as cryptoFramework.PriKey)
        .getEncoded();
      const pub: cryptoFramework.DataBlob = await (pair.pubKey as cryptoFramework.PubKey)
        .getEncoded();
      const b64 = new util.Base64Helper();
      // X25519 private keys come out as the raw 32 byte scalar, which is what
      // wg-quick writes; the DER wrapper is stripped when present.
      const raw = (bytes: Uint8Array) => bytes.length > 32 ?
        bytes.subarray(bytes.length - 32) : bytes;
      this.privateKey = b64.encodeToStringSync(raw(priv.data));
      this.publicKey = b64.encodeToStringSync(raw(pub.data));
      Diag.write('config-edit: rotated keys');
      this.flash('New key pair generated');
    } catch (e) {
      Diag.write(`config-edit: key generation failed: ${e}`);
      this.flash('Key generation is not available on this device');
    }
  }

  private copyPublicKey(): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.publicKey);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.flash('Public key copied');
    }).catch(() => {
      this.flash('Could not copy the public key');
    });
  }

  private addPeer(): void {
    const next: WgPeer[] = this.peers.slice();
    next.push(new WgPeer('', '', '', 51820, '0.0.0.0/0', 25));
    this.peers = next;
  }

  private removePeer(index: number): void {
    const next: WgPeer[] = this.peers.slice();
    next.splice(index, 1);
    this.peers = next;
  }

  private updatePeer(index: number, mutate: (p: WgPeer) => void): void {
    const next: WgPeer[] = this.peers.map((p: WgPeer) => p.clone());
    mutate(next[index]);
    this.peers = next;
  }

  private save(): void {
    const t: WgTunnel | null = TunnelStore.find(this.tunnelId);
    if (t === null) {
      return;
    }
    const trimmed: string = this.name.trim();
    t.name = trimmed.length > 0 ? trimmed : t.name;
    t.privateKey = this.privateKey.trim();
    t.publicKey = this.publicKey.trim();
    t.address = this.addresses.trim();
    t.listenPort = ConfigEdit.number(this.listenPort, 0);
    t.dns = this.dns.trim();
    t.mtu = ConfigEdit.number(this.mtu, 1420);
    t.excludedApps = this.excludedApps.trim();
    t.preUp = this.preUp;
    t.postUp = this.postUp;
    t.preDown = this.preDown;
    t.postDown = this.postDown;
    t.awg = this.awg;
    t.jc = ConfigEdit.number(this.jc, 0);
    t.jmin = ConfigEdit.number(this.jmin, 0);
    t.jmax = ConfigEdit.number(this.jmax, 0);
    t.s1 = ConfigEdit.number(this.s1, 0);
    t.s2 = ConfigEdit.number(this.s2, 0);
    t.s3 = ConfigEdit.number(this.s3, 0);
    t.h1 = ConfigEdit.number(this.h1, 1);
    t.h2 = ConfigEdit.number(this.h2, 2);
    t.h3 = ConfigEdit.number(this.h3, 3);
    t.h4 = ConfigEdit.number(this.h4, 4);
    t.peers = this.peers.filter((p: WgPeer) => p.publicKey.trim().length > 0);
    if (t.peers.length === 0) {
      t.peers = this.peers;
    }
    TunnelStore.save(t);
    Diag.write(`config-edit: saved ${t.name} (${toWgQuick(t).split('\n').length} lines)`);
    this.flash('Saved');
    router.back();
  }

  @Builder
  peerCard(peer: WgPeer, index: number) {
    Column() {
      Row() {
        Text(`Peer ${index + 1}`)
          .fontSize(Type.LABEL_MEDIUM)
          .fontFamily(FONT)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.MUTED)
          .layoutWeight(1)
        Text(Tr.t('Delete'))
          .fontSize(Type.LABEL_MEDIUM)
          .fontFamily(FONT)
          .fontColor(Palette.ALERT)
          .onClick(() => {
            this.removePeer(index);
          })
      }
      .width('100%')
      .padding({ top: 8, bottom: 4 })

      field(Tr.t('Public key'), peer.publicKey, 'base64 key', false, (v: string) => {
        this.updatePeer(index, (p: WgPeer) => {
          p.publicKey = v;
        });
      }, '', () => {})

      field('Preshared key', peer.presharedKey, 'optional', true, (v: string) => {
        this.updatePeer(index, (p: WgPeer) => {
          p.presharedKey = v;
        });
      }, '', () => {})

      field('Persistent keepalive', peer.keepalive > 0 ? peer.keepalive.toString() : '',
        '25 or 22-30, seconds', false, (v: string) => {
          this.updatePeer(index, (p: WgPeer) => {
            p.keepalive = ConfigEdit.number(v, 0);
          });
        }, '', () => {})

      field(Tr.t('Endpoint'), peer.host.length > 0 ? `${peer.host}:${peer.port}` : '',
        'server:port', false, (v: string) => {
          const text: string = v.trim();
          const idx: number = text.lastIndexOf(':');
          this.updatePeer(index, (p: WgPeer) => {
            if (idx > 0) {
              p.host = text.substring(0, idx);
              p.port = ConfigEdit.number(text.substring(idx + 1), 51820);
            } else {
              p.host = text;
            }
          });
        }, '', () => {})

      field(Tr.t('Allowed IPs'), peer.allowedIPs, 'comma separated', false, (v: string) => {
        this.updatePeer(index, (p: WgPeer) => {
          p.allowedIPs = v;
        });
      }, '', () => {})
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 8, bottom: 8 })
    .backgroundColor(Palette.SURFACE)
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
          .margin({ right: 8 })
          .onClick(() => {
            router.back();
          })
          Column() {
            Text(Tr.t('Edit tunnel'))
              .fontSize(Type.TITLE_LARGE)
              .fontFamily(FONT)
              .fontWeight(FontWeight.Medium)
              .fontColor(Palette.ON_SURFACE)
              .width('100%')
            Text(this.name)
              .fontSize(Type.BODY_SMALL)
              .fontFamily(FONT)
              .fontColor(Palette.MUTED)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          // `Icons.Rounded.Save`, the reference app's top-bar save action
          // (`topTrailing` for `ConfigEdit` and `ConfigGlobal`).
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
          .margin({ right: ROW_PAD_H })
          .onClick(() => {
            this.save();
          })
        }
        .width('100%')
        .height(64)
        .padding({ left: ROW_PAD_H })
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            SectionHeader({ label: Tr.t('Interface') })

            Column() {
              field(Tr.t('Name'), this.name, 'tunnel name', false, (v: string) => {
                this.name = v;
              }, '', () => {})
              field(Tr.t('Private key'), this.privateKey, 'base64 key', !this.showSensitive,
                (v: string) => {
                  this.privateKey = v;
                }, 'Rotate', () => {
                  this.rotateKeys();
                })
              Column() {
                Row() {
                  Text(Tr.t('Public key'))
                    .fontSize(Type.BODY_SMALL)
                    .fontFamily(FONT)
                    .fontColor(Palette.MUTED)
                    .layoutWeight(1)
                  Text(Tr.t('Copy'))
                    .fontSize(Type.LABEL_MEDIUM)
                    .fontFamily(FONT)
                    .fontColor(Palette.PRIMARY)
                    .onClick(() => {
                      this.copyPublicKey();
                    })
                }
                .width('100%')
                TextInput({ text: this.publicKey, placeholder: Tr.t('derived from the private key') })
                  .fontSize(Type.BODY_MEDIUM)
                  .fontFamily(FONT)
                  .fontColor(Palette.MUTED)
                  .backgroundColor(Palette.RAISED)
                  .borderRadius(8)
                  .height(44)
                  .enabled(false)
                  .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              field('Addresses', this.addresses, 'comma separated', false, (v: string) => {
                this.addresses = v;
              }, '', () => {})
              field('Listen port', this.listenPort, 'random', false, (v: string) => {
                this.listenPort = v;
              }, '', () => {})
              field('DNS servers', this.dns, 'comma separated', false, (v: string) => {
                this.dns = v;
              }, '', () => {})
              field(Tr.t('MTU'), this.mtu, 'auto', false, (v: string) => {
                this.mtu = v;
              }, '', () => {})
              // Apps listed here bypass the tunnel; everything else goes through
              // it. The engine passes the list as `blockedApplications`, so the
              // bundle names have to be typed: HarmonyOS does not let an ordinary
              // app enumerate the other installed applications.
              field(Tr.t('Excluded apps'), this.excludedApps,
                Tr.t('Excluded apps (bundle names, comma separated)'), false, (v: string) => {
                  this.excludedApps = v;
                }, '', () => {})

              Row() {
                Text(this.showAmnezia ? 'Hide Amnezia options' : 'Show Amnezia options')
                  .fontSize(Type.LABEL_MEDIUM)
                  .fontFamily(FONT)
                  .fontColor(Palette.PRIMARY)
                  .layoutWeight(1)
                Text(this.showScripts ? 'Hide scripts' : 'Show scripts')
                  .fontSize(Type.LABEL_MEDIUM)
                  .fontFamily(FONT)
                  .fontColor(Palette.PRIMARY)
                  .onClick(() => {
                    this.showScripts = !this.showScripts;
                  })
              }
              .width('100%')
              .height(36)
              .onClick(() => {
                this.showAmnezia = !this.showAmnezia;
              })

              if (this.showAmnezia) {
                field('Jc', this.jc, 'junk packet count', false, (v: string) => {
                  this.jc = v;
                }, '', () => {})
                field('Jmin', this.jmin, 'min junk size', false, (v: string) => {
                  this.jmin = v;
                }, '', () => {})
                field('Jmax', this.jmax, 'max junk size', false, (v: string) => {
                  this.jmax = v;
                }, '', () => {})
                field('S1', this.s1, 'init packet junk size', false, (v: string) => {
                  this.s1 = v;
                }, '', () => {})
                field('S2', this.s2, 'response junk size', false, (v: string) => {
                  this.s2 = v;
                }, '', () => {})
                field('S3', this.s3, 'cookie reply junk size', false, (v: string) => {
                  this.s3 = v;
                }, '', () => {})
                field('H1', this.h1, 'init header type', false, (v: string) => {
                  this.h1 = v;
                }, '', () => {})
                field('H2', this.h2, 'response header type', false, (v: string) => {
                  this.h2 = v;
                }, '', () => {})
                field('H3', this.h3, 'cookie reply header type', false, (v: string) => {
                  this.h3 = v;
                }, '', () => {})
                field('H4', this.h4, 'transport header type', false, (v: string) => {
                  this.h4 = v;
                }, '', () => {})
              }

              if (this.showScripts) {
                field('PreUp', this.preUp, 'comma separated', false, (v: string) => {
                  this.preUp = v;
                }, '', () => {})
                field('PostUp', this.postUp, 'comma separated', false, (v: string) => {
                  this.postUp = v;
                }, '', () => {})
                field('PreDown', this.preDown, 'comma separated', false, (v: string) => {
                  this.preDown = v;
                }, '', () => {})
                field('PostDown', this.postDown, 'comma separated', false, (v: string) => {
                  this.postDown = v;
                }, '', () => {})
              }
            }
            .width('100%')
            .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 8, bottom: 12 })
            .backgroundColor(Palette.SURFACE)

            if (this.peers.length > 0) {
              SectionHeader({ label: this.peers.length === 1 ? 'Peer' : 'Peers' })
            }
            ForEach(this.peers, (peer: WgPeer, index: number) => {
              this.peerCard(peer, index);
            }, (peer: WgPeer, index: number) => `${index}-${peer.publicKey}`)

            Row() {
              Text(Tr.t('Add peer'))
                .fontSize(Type.BODY_MEDIUM)
                .fontFamily(FONT)
                .fontColor(Palette.PRIMARY)
            }
            .width('100%')
            .height(52)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(Palette.SURFACE)
            .margin({ top: 8 })
            .onClick(() => {
              this.addPeer();
            })

            Text(Tr.t('The engine brings one interface up at a time; the hooks are written to the ') +
              Tr.t('configuration text and are not executed by this build.'))
              .fontSize(Type.BODY_SMALL)
              .fontFamily(FONT)
              .fontColor(Palette.MUTED)
              .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 12 })
              .width('100%')
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

      if (this.toast.length > 0) {
        Text(this.toast)
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontColor(Palette.ON_SURFACE)
          .backgroundColor(Palette.RAISED)
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .borderRadius(20)
          .margin({ bottom: 40 })
          .align(Alignment.Bottom)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.safeTop })
  }

  onBackPress(): boolean {
    return false;
  }
}
