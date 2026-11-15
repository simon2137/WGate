/**
 * The desktop card.
 *
 * Three layouts share one page because the launcher gives the same form a new
 * size instead of asking for a different form: `size` comes in the binding data
 * ('1x2' | '2x2' | '2x4') and picks the layout, and everything visible — the
 * words included — arrives from `CardData` so this file has no catalogue, no
 * store and no engine of its own. Cards run a stripped runtime; the less logic
 * lives here, the fewer ways the launcher can paint a blank rectangle.
 *
 * Two taps: the round switch asks the app to toggle the tunnel ("call" keeps the
 * window down), the rest of the card opens the app ("router").
 */
let storage: LocalStorage = new LocalStorage();

@Entry(storage)
@Component
struct WgCard {
  @LocalStorageProp('layout') cardSize: string = '2x2';
  @LocalStorageProp('dark') dark: boolean = true;
  @LocalStorageProp('state') state: string = 'down';
  @LocalStorageProp('name') name: string = '';
  @LocalStorageProp('tunnelId') tunnelId: string = '';
  @LocalStorageProp('stateText') stateText: string = '';
  @LocalStorageProp('peers') peers: string = '';
  @LocalStorageProp('rx') rx: string = '';
  @LocalStorageProp('tx') tx: string = '';
  @LocalStorageProp('uptime') uptime: string = '';
  @LocalStorageProp('origin') origin: string = '';
  @LocalStorageProp('endpoint') endpoint: string = '';
  @LocalStorageProp('emptyTitle') emptyTitle: string = '';
  @LocalStorageProp('emptyHint') emptyHint: string = '';

  /** The palette, mirroring `theme/Theme.ets`: the card is the app, not a skin. */
  private accent(): string {
    return this.dark ? '#76BEBD' : '#2C7876';
  }

  private warn(): string {
    return this.dark ? '#D4C483' : '#7E6F26';
  }

  private alert(): string {
    return this.dark ? '#CF6679' : '#B3261E';
  }

  private fg(): string {
    return this.dark ? '#F2F2F4' : '#17191B';
  }

  private muted(): string {
    return this.dark ? '#8D9D9F' : '#5A6669';
  }

  private valueColor(): string {
    return this.dark ? '#D8DEE0' : '#2A2E30';
  }

  private cardBg(): string {
    return this.dark ? '#21272A' : '#FFFFFF';
  }

  /** Panel gradient, the same two stops the app's raised surfaces use. */
  private cardTop(): string {
    return this.dark ? '#262E31' : '#FFFFFF';
  }

  private cardBottom(): string {
    return this.dark ? '#1D2326' : '#F7F8F9';
  }

  /** The washed-out accent at the top-left corner while the tunnel is up. */
  private glowPaint(): string {
    return this.dark ? '#2E76BEBD' : '#1F2C7876';
  }

  private glowClear(): string {
    return this.dark ? '#0076BEBD' : '#002C7876';
  }

  private edgeColor(): string {
    return this.dark ? '#14FFFFFF' : '#14000000';
  }

  private lineColor(): string {
    return this.dark ? '#26FFFFFF' : '#1A000000';
  }

  private haloColor(): string {
    return this.dark ? '#1F76BEBD' : '#1A2C7876';
  }

  private dotHalo(): string {
    if (this.state === 'up') {
      return this.dark ? '#2E76BEBD' : '#242C7876';
    }
    if (this.state === 'starting') {
      return this.dark ? '#33D4C483' : '#2E7E6F26';
    }
    if (this.state === 'error') {
      return this.dark ? '#33CF6679' : '#2EB3261E';
    }
    return this.dark ? '#1A5A6468' : '#1AC5CBD1';
  }

  private strokeColor(): string {
    return this.dark ? '#5A6468' : '#C5CBD1';
  }

  private dotColor(): string {
    if (this.state === 'up') {
      return this.accent();
    }
    if (this.state === 'starting') {
      return this.warn();
    }
    if (this.state === 'error') {
      return this.alert();
    }
    return this.strokeColor();
  }

  private stateColor(): string {
    if (this.state === 'up') {
      return this.accent();
    }
    if (this.state === 'starting') {
      return this.warn();
    }
    if (this.state === 'error') {
      return this.alert();
    }
    return this.muted();
  }

  private openApp(): void {
    postCardAction(this, {
      action: 'router',
      bundleName: 'com.wgate.app',
      abilityName: 'EntryAbility',
      params: { from: 'card' }
    });
  }

  private toggle(): void {
    postCardAction(this, {
      action: 'call',
      bundleName: 'com.wgate.app',
      abilityName: 'EntryAbility',
      params: { method: 'cardToggle', tunnelId: this.tunnelId }
    });
  }

  /**
   * The halo pads scale with the switch: a flat 12vp ring turned the 46vp button
   * on the 2x2 card into a 58vp blob that out-weighed the name above it.
   */
  private haloPad(diameter: number): number {
    return diameter >= 56 ? 10 : 8;
  }

  private ringPad(diameter: number): number {
    return diameter >= 56 ? 5 : 4;
  }

  @Builder
  private dot(size: number) {
    Stack() {
      Column()
        .width(size + 6)
        .height(size + 6)
        .borderRadius((size + 6) / 2)
        .backgroundColor(this.dotHalo())
      Column()
        .width(size)
        .height(size)
        .borderRadius(size / 2)
        .backgroundColor(this.dotColor())
    }
    .width(size + 6)
    .height(size + 6)
  }

  /**
   * The switch. It is the only filled shape on the card, which is the whole
   * status language: colour means the tunnel is up.
   */
  @Builder
  private powerButton(diameter: number) {
    Stack() {
      // The halo is the "on" signal, so it is drawn only when there is something
      // to signal; an idle switch is a plain ring, exactly as in the design.
      if (this.state === 'up' || this.state === 'starting') {
        Column()
          .width(diameter + this.haloPad(diameter))
          .height(diameter + this.haloPad(diameter))
          .borderRadius((diameter + this.haloPad(diameter)) / 2)
          .backgroundColor(this.state === 'up' ? this.haloColor() : this.dark ? '#26D4C483' : '#1F7E6F26')
      }
      Column() {
        Image($r('app.media.ic_card_power'))
          .width(diameter * 0.46)
          .height(diameter * 0.46)
          .fillColor(this.state === 'up' ? (this.dark ? '#10201F' : '#FFFFFF') : this.muted())
      }
      .width(diameter)
      .height(diameter)
      .borderRadius(diameter / 2)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.state === 'up' ? this.accent() : Color.Transparent)
      .border({
        width: this.state === 'up' ? 0 : 1.5,
        color: this.state === 'starting' ? this.warn() : this.strokeColor()
      })
      // A ring drawn around the filled switch, so it does not read as a flat dot.
      if (this.state === 'up') {
        Column()
          .width(diameter + this.ringPad(diameter))
          .height(diameter + this.ringPad(diameter))
          .borderRadius((diameter + this.ringPad(diameter)) / 2)
          .border({ width: 1, color: this.dark ? '#5976BEBD' : '#4D2C7876' })
      }
    }
    .width(diameter + this.haloPad(diameter))
    .height(diameter + this.haloPad(diameter))
    .onClick(() => {
      this.toggle();
    })
  }

  @Builder
  private stateRow() {
    Row() {
      this.dot(8)
      Text(this.stateText)
        .fontSize(12)
        .fontColor(this.stateColor())
        .fontWeight(FontWeight.Medium)
        .margin({ left: 7 })
        .maxLines(1)
      Blank()
      if (this.peers.length > 0) {
        Text(this.peers)
          .fontSize(10)
          .fontColor(this.muted())
          .maxLines(1)
      }
    }
    .width('100%')
    .height(18)
    .alignItems(VerticalAlign.Center)
  }

  /**
   * The tunnel's address, one line under its name.
   *
   * The same shape the app's own rows use (`Home NAS` / `via nas.home.lan`), so
   * the card answers "which configuration is this" without a second glance.
   */
  @Builder
  private endpointLine(size: number, gap: number) {
    if (this.endpoint.length > 0) {
      Text(this.endpoint)
        .fontSize(size)
        .fontColor(this.muted())
        .margin({ top: gap })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
  }

  @Builder
  private statLine(arrow: string, amount: string) {
    Row() {
      Text(arrow)
        .fontSize(12)
        .fontColor(this.muted())
      Text(amount)
        .fontSize(12)
        .fontColor(this.valueColor())
        .margin({ left: 5 })
        .maxLines(1)
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private traffic() {
    Row() {
      Text('↓')
        .fontSize(12)
        .fontColor(this.muted())
      Text(this.rx)
        .fontSize(12)
        .fontColor(this.valueColor())
        .margin({ left: 5 })
      Text('↑')
        .fontSize(12)
        .fontColor(this.muted())
        .margin({ left: 12 })
      Text(this.tx)
        .fontSize(12)
        .fontColor(this.valueColor())
        .margin({ left: 5 })
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private square() {
    Column() {
      Column() {
        this.stateRow()
        Text(this.name)
          .fontSize(16)
          .fontColor(this.fg())
          .fontWeight(FontWeight.Medium)
          .margin({ top: 8 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        this.endpointLine(10.5, 2)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        this.openApp();
      })

      Blank()

      Row() {
        Column() {
          if (this.state === 'up') {
            this.statLine('↓', this.rx)
            Column() {
              this.statLine('↑', this.tx)
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ top: 3 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .onClick(() => {
          this.openApp();
        })

        this.powerButton(46)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private wide() {
    Row() {
      this.powerButton(62)
      Column() {
        this.stateRow()
        Text(this.name)
          .fontSize(20)
          .fontColor(this.fg())
          .fontWeight(FontWeight.Medium)
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        this.endpointLine(11, 1)
        Blank()
        if (this.state === 'up') {
          this.traffic()
        }
        if (this.uptime.length > 0 || this.origin.length > 0) {
          Column() {
            Column()
              .width('100%')
              .height(1)
              .backgroundColor(this.lineColor())
            if (this.uptime.length > 0) {
              Text(this.uptime)
                .fontSize(11)
                .fontColor(this.muted())
                .margin({ top: 4 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            if (this.origin.length > 0) {
              Text(this.origin)
                .fontSize(11)
                .fontColor(this.muted())
                .margin({ top: 1 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
          }
          .width('100%')
          .margin({ top: 5 })
          .alignItems(HorizontalAlign.Start)
        }
      }
      .layoutWeight(1)
      .height('100%')
      .margin({ left: 14 })
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        this.openApp();
      })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private compact() {
    Row() {
      this.dot(8)
      Text(this.stateText)
        .fontSize(12)
        .fontColor(this.stateColor())
        .margin({ left: 7 })
        .maxLines(1)
        .onClick(() => {
          this.openApp();
        })
      Blank()
      this.powerButton(32)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 10, right: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private emptyMark(size: number) {
    Column() {
      Text('+')
        .fontSize(size * 0.5)
        .fontColor(this.accent())
    }
    .width(size)
    .height(size)
    .borderRadius(size / 2)
    .border({ width: 1.5, color: this.accent() })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .opacity(0.75)
  }

  @Builder
  private empty() {
    if (this.cardSize === '2x4') {
      Row() {
        this.emptyMark(46)
        Column() {
          Text(this.emptyTitle)
            .fontSize(17)
            .fontColor(this.fg())
            .fontWeight(FontWeight.Medium)
          Text(this.emptyHint)
            .fontSize(11)
            .fontColor(this.accent())
            .margin({ top: 5 })
        }
        .margin({ left: 14 })
        .alignItems(HorizontalAlign.Start)
        Blank()
      }
      .width('100%')
      .height('100%')
      .padding(12)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.openApp();
      })
    } else if (this.cardSize === '1x2') {
      Row() {
        Text(this.emptyTitle)
          .fontSize(12)
          .fontColor(this.muted())
        Blank()
        this.emptyMark(26)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 10, right: 10 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.openApp();
      })
    } else {
      Column() {
        this.emptyMark(34)
        Text(this.emptyTitle)
          .fontSize(13)
          .fontColor(this.fg())
          .margin({ top: 9 })
        Text(this.emptyHint)
          .fontSize(11)
          .fontColor(this.accent())
          .margin({ top: 4 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.openApp();
      })
    }
  }

  build() {
    Stack() {
      // Panel: a two-stop gradient rather than a flat fill, so the card reads as
      // a raised surface on a wallpaper instead of a white rectangle.
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 160,
          colors: [[this.cardTop(), 0], [this.cardBottom(), 1]]
        })
      // The accent wash in the top-left corner, the same hint of colour the app's
      // surfaces carry while a tunnel is up. Drawn as a gradient because a card
      // cannot blur.
      if (this.state === 'up') {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 150,
            colors: [[this.glowPaint(), 0], [this.glowClear(), 0.62]]
          })
      }
      Column() {
        if (this.state === 'empty') {
          this.empty()
        } else if (this.cardSize === '1x2') {
          this.compact()
        } else if (this.cardSize === '2x4') {
          this.wide()
        } else {
          this.square()
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.cardBg())
    .borderRadius(16)
    .border({ width: 1, color: this.edgeColor() })
    .clip(true)
  }
}
