import { pasteboard } from '@kit.BasicServicesKit';
import { taskpool } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import wgcore from 'libwgcore.so';
import { WgTunnel, WgPeer, toWgQuick } from '../model/Tunnel';
import { Palette, Type, ROW_MIN_H, ROW_PAD_H, ROW_PAD_V, BAR_SPACE , FONT} from '../theme/Theme';
import {
  EngineStatus, readStatus, stateLabel, formatBytes, ago, maskKey, duration,
  publishedTunnelId, isRunning
} from '../service/EngineStatus';
import { startTunnel, stopTunnel, startupProblem } from '../service/VpnControl';
import { TunnelStore } from '../service/TunnelStore';
import { SettingsStore } from '../service/SettingsStore';
import { Diag } from '../util/Diag';
import { Tr } from '../i18n/Tr';
import { sheetWillDismiss } from '../components/SheetGestures';

const SHEET_NONE: string = '';
const SHEET_ACTIONS: string = 'actions';
const SHEET_GROUPS: string = 'groups';
const SHEET_GROUP_ACTIONS: string = 'groupActions';
const SHEET_SORT: string = 'sort';

/**
 * `wgcore.probe()` blocks: it resolves the endpoint and then waits for a
 * handshake reply on the socket. Running that on the UI thread, once per
 * tunnel, froze the list until the system killed the app, so it runs in a
 * taskpool worker and hands back the RTTs as JSON (-1 for no answer).
 */
@Concurrent
function probeLatencies(configs: string[]): string {
  const rtts: number[] = [];
  for (let i = 0; i < configs.length; i++) {
    let rtt: number = -1;
    try {
      const report = JSON.parse(wgcore.probe(configs[i])) as Record<string, Object>;
      if ((report.handshake as boolean) === true && typeof report.rttMs === 'number') {
        rtt = report.rttMs as number;
      }
    } catch (err) {
      rtt = -1;
    }
    rtts.push(rtt);
  }
  return JSON.stringify(rtts);
}

/**
 * The Tunnels tab, following `ui/screens/tunnels/TunnelList.kt`: groups with
 * their children, one row per tunnel with a state dot and the switch on the
 * right, the statistics block expanded under a running tunnel, and long-press
 * selection with the reference app's actions.
 */
@Component
export struct TunnelsView {
  @StorageProp('theme_tick') themeTick: number = 0;
  @Link tunnels: WgTunnel[];
  @Link activeId: string;
  onOpenTunnel: (id: string) => void = () => {};
  onAdd: () => void = () => {};
  onError: (message: string) => void = () => {};
  onChanged: () => void = () => {};

  @State status: EngineStatus | null = null;
  @State busyId: string = '';
  @State epoch: number = 0;
  @State groups: string[] = [];
  @State collapsed: string = '';
  @State selecting: boolean = false;
  @State selected: string[] = [];
  @State sheet: string = SHEET_NONE;
  @State groupDraft: string = '';
  @State groupTarget: string = '';
  @State renameDraft: string = '';
  @State sortMode: string = 'manual';
  /** True while the taskpool is out measuring handshakes. */
  @State probing: boolean = false;

  private timer: number = -1;
  private connectedAt: number = 0;
  /**
   * When an optimistic switch-on stops being taken at face value. The extension
   * publishes its first snapshot a moment after it is asked to start, and the
   * row must not flip back to off while that is still in flight.
   */
  private graceUntil: number = 0;
  /** Long-press bookkeeping: a held row enters selection, its release is not a tap. */
  private pressTimer: number = -1;
  private longPressed: boolean = false;

  private cancelPress(): void {
    if (this.pressTimer >= 0) {
      clearTimeout(this.pressTimer);
      this.pressTimer = -1;
    }
  }

  aboutToAppear(): void {
    this.refresh();
    this.adoptOrphanGroups();
    this.groups = SettingsStore.groups();
    this.sortMode = SettingsStore.sortMode();
    // Tunnel monitoring owns the refresh rate, so the list follows the setting.
    this.timer = setInterval(() => {
      this.refresh();
    }, SettingsStore.statsInterval());
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private refresh(): void {
    const status: EngineStatus | null = readStatus();
    this.status = status;
    // The switch means "this tunnel is running", so it follows the id the
    // extension publishes. A tunnel that was merely wanted — the last session
    // was killed with it up — must not paint as started while the engine says
    // it is stopped; that mismatch is what "switch on, status Disconnected"
    // looked like.
    const published: string = publishedTunnelId();
    if (published.length > 0) {
      this.graceUntil = 0;
      if (this.activeId !== published) {
        this.activeId = published;
        TunnelStore.setActive(published);
      }
    } else if (this.activeId.length > 0 && Date.now() > this.graceUntil &&
      (status === null || !isRunning(status.state))) {
      this.activeId = '';
      this.connectedAt = 0;
      TunnelStore.setActive('');
    }
    if (this.activeId.length > 0 && status !== null && status.state === 'up') {
      if (this.connectedAt === 0) {
        this.connectedAt = Date.now();
      }
    } else if (this.activeId.length === 0) {
      this.connectedAt = 0;
    }
  }

  private running(tunnel: WgTunnel): boolean {
    return this.activeId === tunnel.id;
  }

  private dotColor(tunnel: WgTunnel): string {
    if (!this.running(tunnel)) {
      return Palette.OUTLINE;
    }
    if (this.status !== null && this.status.state === 'error') {
      return Palette.ALERT;
    }
    if (this.status !== null && this.status.state === 'up') {
      return Palette.SILVER_TREE;
    }
    return Palette.STRAW;
  }

  /** Tunnels that belong to a group, in list order. */
  private inGroup(name: string): WgTunnel[] {
    const out: WgTunnel[] = [];
    for (let i = 0; i < this.tunnels.length; i++) {
      if (this.tunnels[i].group === name) {
        out.push(this.tunnels[i]);
      }
    }
    return this.ordered(out);
  }

  /** Sort mode from the reference app's reorder sheet: name, latency or manual. */
  private ordered(list: WgTunnel[]): WgTunnel[] {
    if (this.sortMode === 'name') {
      const copy: WgTunnel[] = list.slice(0);
      copy.sort((a: WgTunnel, b: WgTunnel) => a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1);
      return copy;
    }
    if (this.sortMode === 'latency') {
      const copy: WgTunnel[] = list.slice(0);
      copy.sort((a: WgTunnel, b: WgTunnel) => {
        const ra: number = SettingsStore.latency(a.id);
        const rb: number = SettingsStore.latency(b.id);
        if (ra < 0 && rb < 0) {
          return 0;
        }
        if (ra < 0) {
          return 1;
        }
        if (rb < 0) {
          return -1;
        }
        return ra - rb;
      });
      return copy;
    }
    return list;
  }

  /**
   * Re-registers groups that tunnels still point at but the group list lost, so
   * the grouping comes back instead of the tunnels disappearing from the list.
   */
  private adoptOrphanGroups(): void {
    const known: string[] = SettingsStore.groups();
    for (let i = 0; i < this.tunnels.length; i++) {
      const group: string = this.tunnels[i].group;
      if (group.length > 0 && known.indexOf(group) < 0) {
        SettingsStore.addGroup(group);
        known.push(group);
        Diag.write(`groups: adopted ${group}`);
      }
    }
  }

  private ungrouped(): WgTunnel[] {
    const out: WgTunnel[] = [];
    for (let i = 0; i < this.tunnels.length; i++) {
      const group: string = this.tunnels[i].group;
      // A tunnel whose group is no longer registered (the group list lives in
      // its own preference and can be lost separately) would otherwise render
      // nowhere at all, so it falls back to the ungrouped section.
      if (group.length === 0 || this.groups.indexOf(group) < 0) {
        out.push(this.tunnels[i]);
      }
    }
    return this.ordered(out);
  }

  private activeIn(name: string): number {
    const list: WgTunnel[] = this.inGroup(name);
    let count: number = 0;
    for (let i = 0; i < list.length; i++) {
      if (this.running(list[i])) {
        count++;
      }
    }
    return count;
  }

  private isCollapsed(name: string): boolean {
    return this.collapsed.split('\n').indexOf(name) >= 0;
  }

  private toggleCollapsed(name: string): void {
    const items: string[] = this.collapsed.split('\n').filter((s: string) => s.length > 0);
    const at: number = items.indexOf(name);
    if (at >= 0) {
      items.splice(at, 1);
    } else {
      items.push(name);
    }
    this.collapsed = items.join('\n');
  }

  private isSelected(id: string): boolean {
    return this.selected.indexOf(id) >= 0;
  }

  private beginSelection(id: string): void {
    this.selecting = true;
    this.selected = [id];
  }

  private toggleSelected(id: string): void {
    const items: string[] = this.selected.filter((s: string) => s.length > 0);
    const at: number = items.indexOf(id);
    if (at >= 0) {
      items.splice(at, 1);
    } else {
      items.push(id);
    }
    this.selected = items;
    if (items.length === 0) {
      this.selecting = false;
    }
  }

  private endSelection(): void {
    this.selecting = false;
    this.selected = [];
  }

  private selectedTunnels(): WgTunnel[] {
    const out: WgTunnel[] = [];
    for (let i = 0; i < this.tunnels.length; i++) {
      if (this.isSelected(this.tunnels[i].id)) {
        out.push(this.tunnels[i]);
      }
    }
    return out;
  }

  private deleteSelected(): void {
    const list: WgTunnel[] = this.selectedTunnels();
    if (this.activeId.length > 0) {
      for (let i = 0; i < list.length; i++) {
        if (list[i].id === this.activeId) {
          this.onError(Tr.t('Disconnect the tunnel before deleting it'));
          return;
        }
      }
    }
    for (let i = 0; i < list.length; i++) {
      TunnelStore.remove(list[i].id);
    }
    const removed: string[] = this.selected.filter((s: string) => s.length > 0);
    for (let i = 0; i < this.groups.length; i++) {
      if (this.inGroup(this.groups[i]).length === 0) {
        SettingsStore.removeGroup(this.groups[i]);
      }
    }
    this.groups = SettingsStore.groups();
    this.endSelection();
    this.sheet = SHEET_NONE;
    this.onChanged();
    this.onError(removed.length === 1 ? Tr.t('Tunnel deleted') : `${removed.length} tunnels deleted`);
  }

  private copySelected(): void {
    const list: WgTunnel[] = this.selectedTunnels();
    if (list.length === 0) {
      return;
    }
    let text: string = '';
    for (let i = 0; i < list.length; i++) {
      if (i > 0) {
        text += '\n\n';
      }
      text += toWgQuick(list[i]);
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.sheet = SHEET_NONE;
      this.onError(list.length === 1 ? Tr.t('Configuration copied') : `${list.length} configurations copied`);
    }).catch(() => {
      this.onError(Tr.t('Could not copy the configuration'));
    });
  }

  private moveSelectedTo(name: string): void {
    const trimmed: string = name.trim();
    if (trimmed.length === 0) {
      return;
    }
    SettingsStore.addGroup(trimmed);
    const list: WgTunnel[] = this.selectedTunnels();
    for (let i = 0; i < list.length; i++) {
      list[i].group = trimmed;
      TunnelStore.save(list[i]);
    }
    this.groups = SettingsStore.groups();
    this.groupDraft = '';
    this.sheet = SHEET_NONE;
    this.endSelection();
    this.onChanged();
    this.onError(`Moved to ${trimmed}`);
  }

  private async toggle(tunnel: WgTunnel, on: boolean): Promise<void> {
    if (this.busyId.length > 0) {
      return;
    }
    this.busyId = tunnel.id;
    if (on) {
      const problem: string = await startTunnel(tunnel);
      if (problem.length > 0) {
        this.onError(problem);
      } else {
        this.activeId = tunnel.id;
        this.graceUntil = Date.now() + 8000;
        TunnelStore.setActive(tunnel.id);
        setTimeout(() => {
          const late: string = startupProblem();
          if (late.length > 0) {
            this.onError(late);
          }
        }, 6000);
      }
    } else {
      await stopTunnel(tunnel);
      this.activeId = '';
      this.graceUntil = 0;
      this.connectedAt = 0;
    }
    this.busyId = '';
    this.epoch++;
    this.refresh();
  }

  @Builder
  private statistics(tunnel: WgTunnel) {
    Column() {
      Row() {
        Text(stateLabel(this.status === null ? 'connecting' : this.status.state))
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontColor(Palette.MUTED)
          .layoutWeight(1)
        if (this.connectedAt > 0) {
          Text(Tr.tf('uptime: %1$s', duration(Date.now() - this.connectedAt)))
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
        }
      }
      .width('100%')

      Row() {
        Image($r('app.media.ic_arrow_down'))
          .width(12)
          .height(12)
          .fillColor(Palette.MUTED)
          .margin({ right: 4 })
        Text(this.status === null ? '0 B' : formatBytes(this.status.rxBytes))
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontColor(Palette.MUTED)
          .margin({ right: 16 })
        Image($r('app.media.ic_arrow_up'))
          .width(12)
          .height(12)
          .fillColor(Palette.MUTED)
          .margin({ right: 4 })
        Text(this.status === null ? '0 B' : formatBytes(this.status.txBytes))
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontColor(Palette.MUTED)
      }
      .width('100%')
      .margin({ top: 4 })

      ForEach(tunnel.peers, (peer: WgPeer, index: number) => {
        Column() {
          Text(peer.publicKey.length > 0 ?
            Tr.tf('peer: %1$s', maskKey(peer.publicKey).toLowerCase()) :
            Tr.tf('peer: %1$s', `${index + 1}`))
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
            .width('100%')
          Text(`${Tr.tf('handshake: %1$s', ago(this.status === null ? 0 : this.status.handshakeMs))} · ${peer.host}:${peer.port}`)
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
            .width('100%')
            .margin({ top: 2 })
        }
        .width('100%')
        .margin({ top: 6 })
      }, (peer: WgPeer, index: number) => `${index}`)
    }
    .width('100%')
    .padding({ left: 30, top: 2, bottom: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private tunnelRow(tunnel: WgTunnel, indented: boolean) {
    Column() {
      Row() {
        if (this.selecting) {
          if (this.isSelected(tunnel.id)) {
            Image($r('app.media.ic_check_circle'))
              .width(18)
              .height(18)
              .fillColor(Palette.PRIMARY)
              .margin({ right: 14 })
          } else {
            Circle()
              .width(18)
              .height(18)
              .fill(Color.Transparent)
              .stroke(Palette.MUTED)
              .strokeWidth(1.5)
              .margin({ right: 14 })
          }
        } else {
          Circle()
            .width(14)
            .height(14)
            .fill(this.dotColor(tunnel))
            .margin({ right: 16 })
        }
        Column() {
          Text(tunnel.name)
            .fontSize(Type.BODY_LARGE)
            .fontFamily(FONT)
            .fontColor(Palette.ON_SURFACE)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(Tr.tf('via %1$s', tunnel.peers.length > 0 && tunnel.peers[0].host.length > 0 ? tunnel.peers[0].host : tunnel.address))
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
            .maxLines(1)
            .width('100%')
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (!this.selecting) {
          Toggle({ type: ToggleType.Switch, isOn: this.running(tunnel) })
            .selectedColor(Palette.PRIMARY)
            .switchPointColor(Palette.SURFACE)
            .margin({ left: 8 })
            .onChange((on: boolean) => {
              this.toggle(tunnel, on);
            })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: ROW_MIN_H })
      .alignItems(VerticalAlign.Center)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.cancelPress();
          this.pressTimer = setTimeout(() => {
            this.pressTimer = -1;
            this.longPressed = true;
            this.beginSelection(tunnel.id);
          }, 420);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.cancelPress();
        }
      })
      .onClick(() => {
        if (this.longPressed) {
          this.longPressed = false;
          return;
        }
        if (this.selecting) {
          this.toggleSelected(tunnel.id);
        } else {
          this.onOpenTunnel(tunnel.id);
        }
      })

      if (this.running(tunnel) && !this.selecting && SettingsStore.statisticsEnabled()) {
        this.statistics(tunnel);
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: indented ? ROW_PAD_H + 24 : ROW_PAD_H,
      right: ROW_PAD_H,
      top: ROW_PAD_V,
      bottom: ROW_PAD_V
    })
    .backgroundColor(this.running(tunnel) ? '#1A76BEBD' : Palette.SURFACE)
    .onClick(() => {
      if (this.selecting) {
        this.toggleSelected(tunnel.id);
      }
    })
  }

  @Builder
  private groupHeader(name: string) {
    Row() {
      Image(this.isCollapsed(name) ? $r('app.media.ic_folder') : $r('app.media.ic_folder_open'))
        .width(20)
        .height(20)
        .fillColor(Palette.ON_SURFACE)
        .margin({ right: 16 })
      Column() {
        Text(name)
          .fontSize(Type.BODY_LARGE)
          .fontFamily(FONT)
          .fontColor(Palette.ON_SURFACE)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row() {
          Text(`${this.inGroup(name).length} ${this.inGroup(name).length === 1 ? 'tunnel' : 'tunnels'}`)
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
          if (this.activeIn(name) > 0) {
            Text(` · ${this.activeIn(name)} active`)
              .fontSize(Type.BODY_SMALL)
              .fontFamily(FONT)
              .fontColor(Palette.PRIMARY)
          }
        }
        .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.inGroup(name).length > 0) {
        Image(this.isCollapsed(name) ? $r('app.media.ic_chevron_down') : $r('app.media.ic_chevron_up'))
          .width(20)
          .height(20)
          .fillColor(Palette.MUTED)
      }
    }
    .width('100%')
    .constraintSize({ minHeight: ROW_MIN_H })
    .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: ROW_PAD_V, bottom: ROW_PAD_V })
    .backgroundColor(Palette.SURFACE)
    .alignItems(VerticalAlign.Center)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.longPressed = false;
        this.cancelPress();
        this.pressTimer = setTimeout(() => {
          this.pressTimer = -1;
          this.longPressed = true;
          this.groupTarget = name;
          this.renameDraft = name;
          this.sheet = SHEET_GROUP_ACTIONS;
        }, 420);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.cancelPress();
      }
    })
    .onClick(() => {
      if (this.longPressed) {
        this.longPressed = false;
        return;
      }
      this.toggleCollapsed(name);
    })
  }

  /** `GroupActionsSheet.kt`: rename, export, delete the group or delete both. */
  @Builder
  private groupActionsSheet() {
    Column() {
      Row() {
        Text(this.groupTarget)
          .fontSize(Type.TITLE_MEDIUM)
          .fontFamily(FONT)
          .fontColor(Palette.ON_SURFACE)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8, bottom: 8 })

      Row() {
        TextInput({ placeholder: Tr.t('Group name'), text: this.renameDraft })
          .layoutWeight(1)
          .height(44)
          .padding({ left: 12, right: 12 })
          .backgroundColor(Palette.SURFACE)
          .fontColor(Palette.ON_SURFACE)
          .placeholderColor(Palette.MUTED)
          .onChange((value: string) => {
            this.renameDraft = value;
          })
        Text(Tr.t('Rename'))
          .fontSize(Type.BODY_MEDIUM)
          .fontFamily(FONT)
          .fontColor(this.renameDraft.trim().length > 0 ? Palette.PRIMARY : Palette.MUTED)
          .margin({ left: 16 })
          .onClick(() => {
            this.renameGroupTo(this.renameDraft.trim());
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 8 })

      this.actionRow(Tr.t('Export group'), $r('app.media.ic_doc'), Palette.ON_SURFACE, () => {
        this.exportGroup(this.groupTarget);
      })
      this.actionRow(Tr.t('Delete group'), $r('app.media.ic_delete'), Palette.ON_SURFACE, () => {
        this.deleteGroupOnly();
      })
      this.actionRow(Tr.t('Delete group and tunnels'), $r('app.media.ic_delete'), Palette.ALERT, () => {
        this.deleteGroupAndTunnels();
      })
      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
  }

  @Builder
  private sortSheet() {
    Column() {
      Row() {
        Text(Tr.t('Reorder'))
          .fontSize(Type.TITLE_MEDIUM)
          .fontFamily(FONT)
          .fontColor(Palette.ON_SURFACE)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8, bottom: 8 })

      this.actionRow(Tr.t('Sort'), $r('app.media.ic_doc'), Palette.ON_SURFACE, () => {
        this.sortMode = 'name';
        SettingsStore.setSortMode('name');
        this.sheet = SHEET_NONE;
        this.onError(Tr.t('Sorted by name'));
      })
      this.actionRow(Tr.t('Sort by latency'), $r('app.media.ic_bolt'), Palette.ON_SURFACE, () => {
        this.sortByLatency();
      })
      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
  }

  private renameGroupTo(name: string): void {
    if (name.length === 0 || name === this.groupTarget) {
      this.sheet = SHEET_NONE;
      return;
    }
    SettingsStore.renameGroup(this.groupTarget, name);
    this.groups = SettingsStore.groups();
    this.groupTarget = name;
    this.sheet = SHEET_NONE;
    this.onChanged();
  }

  private deleteGroupOnly(): void {
    SettingsStore.removeGroup(this.groupTarget);
    this.groups = SettingsStore.groups();
    this.sheet = SHEET_NONE;
    this.onChanged();
    this.onError(Tr.t('Group removed, its tunnels are ungrouped'));
  }

  private deleteGroupAndTunnels(): void {
    const list: WgTunnel[] = this.inGroup(this.groupTarget);
    for (let i = 0; i < list.length; i++) {
      if (list[i].id !== this.activeId) {
        TunnelStore.remove(list[i].id);
      }
    }
    SettingsStore.removeGroup(this.groupTarget);
    this.groups = SettingsStore.groups();
    this.sheet = SHEET_NONE;
    this.epoch++;
    this.onChanged();
  }

  private async exportGroup(name: string): Promise<void> {
    const list: WgTunnel[] = this.inGroup(name);
    if (list.length === 0) {
      this.sheet = SHEET_NONE;
      this.onError(Tr.t('This group has no tunnels'));
      return;
    }
    const parts: string[] = [];
    for (let i = 0; i < list.length; i++) {
      parts.push(toWgQuick(list[i]));
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options = new picker.DocumentSaveOptions();
      const stamp: string = new Date().toISOString().replace(/[:.]/g, '-');
      options.newFileNames = [`${name}-${stamp}.conf`];
      const view = new picker.DocumentViewPicker(context);
      const uris: string[] = await view.save(options);
      if (uris.length === 0) {
        this.sheet = SHEET_NONE;
        return;
      }
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, parts.join('\n\n'));
      fileIo.closeSync(file);
      Diag.write(`group export ${name}: ${uris[0]} (${list.length} tunnels)`);
      this.onError(`Exported ${list.length} tunnel(s)`);
    } catch (err) {
      const error = err as BusinessError;
      this.onError(`Export failed: ${error.message}`);
    }
    this.sheet = SHEET_NONE;
  }

  /**
   * The reference app sorts by the latency its pings recorded. This build asks
   * the engine to perform a handshake with each endpoint and keeps the RTT.
   */
  private async sortByLatency(): Promise<void> {
    this.sheet = SHEET_NONE;
    // The probe waits on the network; a second tap while it runs would only
    // queue another round of handshakes.
    if (this.probing) {
      return;
    }
    this.probing = true;
    const configs: string[] = [];
    for (let i = 0; i < this.tunnels.length; i++) {
      configs.push(JSON.stringify(JSON.parse(this.tunnels[i].toJson())));
    }
    let rtts: number[] = [];
    try {
      rtts = JSON.parse(await taskpool.execute(probeLatencies, configs) as string) as number[];
    } catch (err) {
      this.probing = false;
      Diag.write(`sort by latency: measurement failed: ${err}`);
      this.onError(`Could not measure latency: ${(err as BusinessError).message}`);
      return;
    }
    let measured: number = 0;
    for (let i = 0; i < rtts.length && i < this.tunnels.length; i++) {
      if (rtts[i] >= 0) {
        SettingsStore.setLatency(this.tunnels[i].id, rtts[i]);
        measured++;
      }
    }
    this.probing = false;
    this.sortMode = 'latency';
    SettingsStore.setSortMode('latency');
    this.epoch++;
    Diag.write(`sort by latency: ${measured} of ${this.tunnels.length} measured`);
    this.onError(measured > 0 ? `Sorted by latency (${measured} measured)` :
      Tr.t('No tunnel answered, the order is unchanged'));
  }

  @Builder
  private header() {
    Row() {
      if (this.selecting) {
        Row() {
          Image($r('app.media.ic_close'))
            .width(24)
            .height(24)
            .fillColor(Palette.ON_SURFACE)
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .margin({ right: 4 })
        .onClick(() => {
          this.endSelection();
        })
        Text(`${this.selected.length} selected`)
          .fontSize(Type.TITLE_LARGE)
          .fontFamily(FONT)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.ON_SURFACE)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Image($r('app.media.ic_more'))
          .width(24)
          .height(24)
          .fillColor(Palette.ON_SURFACE)
          .margin({ left: 12 })
          .onClick(() => {
            this.sheet = SHEET_ACTIONS;
          })
      } else {
        Text(Tr.t('Tunnels'))
          .fontSize(Type.TITLE_LARGE)
          .fontFamily(FONT)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.ON_SURFACE)
          .layoutWeight(1)
        Image($r('app.media.ic_reorder'))
          .width(24)
          .height(24)
          .fillColor(Palette.ON_SURFACE)
          .margin({ right: 20 })
          .onClick(() => {
            this.sheet = SHEET_SORT;
          })
        Image($r('app.media.ic_add'))
          .width(24)
          .height(24)
          .fillColor(Palette.ON_SURFACE)
          .onClick(() => {
            this.onAdd();
          })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: ROW_PAD_H, right: ROW_PAD_H })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private emptyState() {
    Column() {
      Text(Tr.t('Nothing here… yet.'))
        .fontSize(Type.BODY_LARGE)
        .fontFamily(FONT)
        .fontColor(Palette.ON_SURFACE)
        .margin({ bottom: 8 })
      Text(Tr.t('Use the + button to import a tunnel, or view the getting started guide.'))
        .fontSize(Type.BODY_MEDIUM)
        .fontFamily(FONT)
        .fontColor(Palette.MUTED)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: 32, right: 32, top: 96 })
  }

  @Builder
  private actionRow(label: string, icon: Resource, tint: string, action: () => void) {
    Row() {
      Image(icon)
        .width(20)
        .height(20)
        .fillColor(tint)
        .margin({ right: 16 })
      Text(label)
        .fontSize(Type.BODY_LARGE)
        .fontFamily(FONT)
        .fontColor(tint)
        .layoutWeight(1)
    }
    .width('100%')
    .height(52)
    .padding({ left: 24, right: 24 })
    .onClick(() => {
      action();
    })
  }

  @Builder
  private actionsSheet() {
    Column() {
      Row() {
        Text(Tr.t('Actions'))
          .fontSize(Type.TITLE_MEDIUM)
          .fontFamily(FONT)
          .fontColor(Palette.ON_SURFACE)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8, bottom: 8 })

      this.actionRow(Tr.t('Select all'), $r('app.media.ic_check_circle'), Palette.ON_SURFACE, () => {
        const all: string[] = [];
        for (let i = 0; i < this.tunnels.length; i++) {
          all.push(this.tunnels[i].id);
        }
        this.selected = all;
        this.selecting = all.length > 0;
        this.sheet = SHEET_NONE;
      })
      this.actionRow(Tr.t('Move to group'), $r('app.media.ic_folder'), Palette.ON_SURFACE, () => {
        this.sheet = SHEET_GROUPS;
      })
      this.actionRow(Tr.t('Copy config'), $r('app.media.ic_doc'), Palette.ON_SURFACE, () => {
        this.copySelected();
      })
      this.actionRow(Tr.t('Ungroup'), $r('app.media.ic_close'), Palette.ON_SURFACE, () => {
        const list: WgTunnel[] = this.selectedTunnels();
        for (let i = 0; i < list.length; i++) {
          list[i].group = '';
          TunnelStore.save(list[i]);
        }
        this.sheet = SHEET_NONE;
        this.endSelection();
        this.onChanged();
      })
      this.actionRow(Tr.t('Delete'), $r('app.media.ic_delete'), Palette.ALERT, () => {
        this.deleteSelected();
      })
      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
  }

  @Builder
  private groupsSheet() {
    Column() {
      Row() {
        Text(Tr.t('Move to group'))
          .fontSize(Type.TITLE_MEDIUM)
          .fontFamily(FONT)
          .fontColor(Palette.ON_SURFACE)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8, bottom: 8 })

      Row() {
        TextInput({ placeholder: Tr.t('Group name'), text: this.groupDraft })
          .layoutWeight(1)
          .height(44)
          .backgroundColor(Palette.SURFACE)
          .fontColor(Palette.ON_SURFACE)
          .placeholderColor(Palette.MUTED)
          .onChange((value: string) => {
            this.groupDraft = value;
          })
        Button(Tr.t('Create'))
          .height(44)
          .margin({ left: 12 })
          .backgroundColor(Palette.PRIMARY)
          .fontColor(Palette.BACKGROUND)
          .fontSize(Type.LABEL_LARGE)
          .fontFamily(FONT)
          .onClick(() => {
            this.moveSelectedTo(this.groupDraft);
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 12 })

      List() {
        ForEach(this.groups, (name: string) => {
          ListItem() {
            Row() {
              Image($r('app.media.ic_folder'))
                .width(20)
                .height(20)
                .fillColor(Palette.ON_SURFACE)
                .margin({ right: 16 })
              Text(name)
                .fontSize(Type.BODY_LARGE)
                .fontFamily(FONT)
                .fontColor(Palette.ON_SURFACE)
                .layoutWeight(1)
            }
            .width('100%')
            .height(52)
            .padding({ left: 24, right: 24 })
            .onClick(() => {
              this.moveSelectedTo(name);
            })
          }
        }, (name: string) => name)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
  }

  build() {
    Column() {
      this.header();

      if (this.tunnels.length === 0 && this.groups.length === 0) {
        this.emptyState();
        Blank()
      } else {
        List({ space: 5 }) {
          ForEach(this.groups, (name: string) => {
            ListItem() {
              Column() {
                this.groupHeader(name);
                if (!this.isCollapsed(name)) {
                  ForEach(this.inGroup(name), (tunnel: WgTunnel) => {
                    this.tunnelRow(tunnel, true);
                  }, (tunnel: WgTunnel) => tunnel.id + this.epoch.toString())
                }
              }
              .width('100%')
            }
          }, (name: string) => name)

          ForEach(this.ungrouped(), (tunnel: WgTunnel) => {
            ListItem() {
              this.tunnelRow(tunnel, false);
            }
          }, (tunnel: WgTunnel) => tunnel.id + this.epoch.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ bottom: BAR_SPACE })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
    .bindSheet(this.sheet !== SHEET_NONE, this.sheetBody(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      preferType: SheetType.BOTTOM,
      showClose: false,
      onWillDismiss: sheetWillDismiss('tunnels'),
      backgroundColor: Palette.BACKGROUND,
      onDisappear: () => {
        this.sheet = SHEET_NONE;
      }
    })
  }

  @Builder
  private sheetBody() {
    if (this.sheet === SHEET_GROUPS) {
      this.groupsSheet();
    } else if (this.sheet === SHEET_GROUP_ACTIONS) {
      this.groupActionsSheet();
    } else if (this.sheet === SHEET_SORT) {
      this.sortSheet();
    } else {
      this.actionsSheet();
    }
  }
}
