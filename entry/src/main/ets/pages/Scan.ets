import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { customScan, detectBarcode, scanBarcode, scanCore } from '@kit.ScanKit';
import { WgTunnel, parseWgQuick } from '../model/Tunnel';
import { TunnelStore } from '../service/TunnelStore';
import { Tr } from '../i18n/Tr';

const DOMAIN: number = 0x0002;
const TAG: string = 'Scan';

/**
 * QR import page.
 *
 * The camera is opened and driven by Scan Kit itself: we hand it the surface id
 * of an `XComponent` and it renders the preview there and decodes frames
 * internally, so there is no CameraKit session to manage and no image format to
 * convert. `customScan.init()` must run before `start()`, and `stop()`/`release()`
 * may only be called after a successful `start()` (otherwise error 1000500001).
 */
@Entry
@Component
struct Scan {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;
  @State private cameraReady: boolean = false;
  @State private unavailableReason: string = '';
  @State private flashOn: boolean = false;
  @State private decoding: boolean = false;

  private controller: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private surfaceW: number = 0;
  private surfaceH: number = 0;
  private permissionGranted: boolean = false;
  private starting: boolean = false;
  private running: boolean = false;
  private handling: boolean = false;

  aboutToAppear(): void {
    void this.requestCamera();
  }

  onPageHide(): void {
    void this.stopScanning();
  }

  aboutToDisappear(): void {
    void this.stopScanning();
  }

  private async requestCamera(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    TunnelStore.init(context);
    const permissions: Array<Permissions> = ['ohos.permission.CAMERA'];
    try {
      const manager = abilityAccessCtrl.createAtManager();
      const result = await manager.requestPermissionsFromUser(context, permissions);
      const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0;
      hilog.info(DOMAIN, TAG, `camera permission granted=${granted}`);
      if (!granted) {
        this.unavailableReason = Tr.t('Camera permission was denied.');
        return;
      }
      this.permissionGranted = true;
      this.unavailableReason = '';
      this.maybeStart();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `camera permission failed: ${JSON.stringify(e)}`);
      this.unavailableReason = Tr.t('Camera permission could not be requested.');
    }
  }

  private onSurfaceLoad(): void {
    const id: string = this.controller.getXComponentSurfaceId();
    hilog.info(DOMAIN, TAG, `surface=${id}`);
    if (id !== undefined && id.length > 0) {
      this.surfaceId = id;
    }
    this.maybeStart();
  }

  /** Surface, size and permission all have to be ready before the camera starts. */
  private maybeStart(): void {
    if (this.starting || this.running || !this.permissionGranted) {
      return;
    }
    if (this.surfaceId.length === 0 || this.surfaceW <= 0 || this.surfaceH <= 0) {
      return;
    }
    this.starting = true;
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: false
      };
      customScan.init(options);
      const view: customScan.ViewControl = {
        width: this.surfaceW,
        height: this.surfaceH,
        surfaceId: this.surfaceId
      };
      customScan.start(view,
        (error: BusinessError, data: Array<scanBarcode.ScanResult>) => {
          this.onResult(error, data);
        },
        (error: BusinessError, frame: customScan.ScanFrame) => {
          if (error || frame === undefined || this.cameraReady) {
            return;
          }
          hilog.info(DOMAIN, TAG, `preview frame ${frame.width}x${frame.height}`);
          this.cameraReady = true;
          this.unavailableReason = '';
        });
      this.running = true;
      hilog.info(DOMAIN, TAG, `scanning ${this.surfaceW}x${this.surfaceH}`);
      // A device without a usable camera starts the session but never delivers a
      // frame, so the UI has to stop saying "starting" on its own.
      setTimeout(() => {
        if (!this.cameraReady) {
          hilog.warn(DOMAIN, TAG, 'no preview frame after 6s');
          this.unavailableReason =
            Tr.t('This device is not delivering a camera preview. Use Image to decode a screenshot, ') +
              Tr.t('or paste the configuration.');
        }
      }, 6000);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `start failed: ${JSON.stringify(e)}`);
      this.unavailableReason = Tr.t('This device cannot open the camera for scanning.');
    }
    this.starting = false;
  }

  private onResult(error: BusinessError, data: Array<scanBarcode.ScanResult>): void {
    if (error) {
      hilog.warn(DOMAIN, TAG, `scan error: ${error.code} ${error.message}`);
      this.unavailableReason = Tr.t('The scanner stopped unexpectedly.');
      this.cameraReady = false;
      this.running = false;
      return;
    }
    if (data === undefined || data.length === 0) {
      return;
    }
    const text: string = data[0].originalValue;
    if (text === undefined || text.length === 0) {
      return;
    }
    hilog.info(DOMAIN, TAG, `decoded ${text.length} chars`);
    this.apply(text);
  }

  /** Decoded text is always a wg-quick configuration in this client. */
  private apply(text: string): void {
    if (this.handling) {
      return;
    }
    this.handling = true;
    this.decoding = true;
    const parsed: WgTunnel | null = parseWgQuick(text, 'Scanned tunnel');
    if (parsed === null) {
      this.decoding = false;
      this.handling = false;
      this.toast(Tr.t('That code does not contain a WireGuard configuration'));
      void this.resume();
      return;
    }
    const same = TunnelStore.list().find((t: WgTunnel) =>
      t.privateKey === parsed.privateKey && t.endpoint() === parsed.endpoint());
    if (same !== undefined) {
      // Updating an existing tunnel keeps the name the user gave it; the parsed
      // one is only the placeholder every configuration without a name gets.
      parsed.id = same.id;
      parsed.name = same.name;
    }
    TunnelStore.save(parsed);
    hilog.info(DOMAIN, TAG, `saved ${parsed.id} peers=${parsed.peers.length}`);
    void this.stopScanning();
    this.toast(`${Tr.t('Imported')} ${parsed.name}`);
    router.back();
  }

  private async resume(): Promise<void> {
    try {
      customScan.rescan();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'rescan failed');
    }
  }

  private async stopScanning(): Promise<void> {
    if (!this.running) {
      return;
    }
    this.running = false;
    try {
      await customScan.stop();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'stop failed');
    }
    try {
      await customScan.release();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'release failed');
    }
  }

  /**
   * Decode a QR code from an image file.
   *
   * This is the fallback when there is no usable camera (and the way a code
   * shared as a screenshot gets imported): the same decoding engine is used,
   * just fed from a URI instead of the preview stream.
   */
  private async importFromImage(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris = await documentPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.png', '.jpg', '.jpeg', '.webp']
      });
      if (uris.length === 0) {
        return;
      }
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: false
      };
      const results: Array<scanBarcode.ScanResult> =
        await detectBarcode.decode({ uri: uris[0] }, options);
      if (results === undefined || results.length === 0) {
        this.toast(Tr.t('No QR code was found in that image'));
        return;
      }
      const text: string = results[0].originalValue;
      hilog.info(DOMAIN, TAG, `image decode: ${text.length} chars`);
      this.apply(text);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `image decode failed: ${JSON.stringify(e)}`);
      this.toast(Tr.t('That image could not be decoded'));
    }
  }

  private toggleFlash(): void {
    if (!this.running) {
      return;
    }
    try {
      if (this.flashOn) {
        customScan.closeFlashLight();
      } else {
        customScan.openFlashLight();
      }
      this.flashOn = customScan.getFlashLightStatus();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'torch failed');
    }
  }

  private toast(message: string): void {
    try {
      promptAction.showToast({ message: message, duration: 2200 });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'toast failed');
    }
  }

  private goBack(): void {
    void this.stopScanning();
    router.back();
  }

  @Builder
  viewfinder() {
    Stack() {
      // Four corner marks: a full frame would be noise over the preview.
      ForEach([0, 1, 2, 3], (corner: number) => {
        Row()
          .width(34)
          .height(34)
          .borderWidth({ top: corner < 2 ? 3 : 0, bottom: corner >= 2 ? 3 : 0,
            left: corner % 2 === 0 ? 3 : 0, right: corner % 2 === 1 ? 3 : 0 })
          .borderColor('#38E8A0')
          .position({
            x: corner % 2 === 0 ? 0 : 226,
            y: corner < 2 ? 0 : 226
          })
      }, (corner: number) => corner.toString())
    }
    .width(260)
    .height(260)
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')

      XComponent({ id: 'scan-surface', type: XComponentType.SURFACE, controller: this.controller })
        .width('100%')
        .height('100%')
        .onLoad(() => this.onSurfaceLoad())
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.surfaceW = newValue.width as number;
          this.surfaceH = newValue.height as number;
          this.maybeStart();
        })

      if (!this.cameraReady) {
        Column({ space: 12 }) {
          Text(this.unavailableReason.length > 0 ? this.unavailableReason : Tr.t('Starting the camera…'))
            .fontSize(14)
            .fontColor('#8FA3B8')
            .textAlign(TextAlign.Center)
            .width('80%')
          Text(Tr.t('You can still import a tunnel from a file or by pasting its configuration.'))
            .fontSize(12)
            .fontColor('#5A6B7D')
            .textAlign(TextAlign.Center)
            .width('80%')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#0E1621')
      } else {
        Column() {
          Blank()
          this.viewfinder()
          Blank()
          Text(Tr.t('Point the camera at a WireGuard configuration code'))
            .fontSize(13)
            .fontColor('#EAF2FB')
            .padding({ top: 16 })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
      }

      Column() {
        Row() {
          Button(Tr.t('Back'))
            .fontSize(13)
            .fontColor('#EAF2FB')
            .backgroundColor('#16212F')
            .height(36)
            .onClick(() => this.goBack())
          Blank()
          Text(Tr.t('Scan a tunnel'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#EAF2FB')
          Blank()
          Row({ space: 8 }) {
            Button(Tr.t('Image'))
              .fontSize(13)
              .fontColor('#EAF2FB')
              .backgroundColor('#16212F')
              .height(36)
              .onClick(() => this.importFromImage())
            Button(this.flashOn ? Tr.t('Torch on') : Tr.t('Torch'))
              .fontSize(13)
              .fontColor('#EAF2FB')
              .backgroundColor('#16212F')
              .height(36)
              .onClick(() => this.toggleFlash())
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10 })

        if (this.decoding) {
          Row() {
            Text(Tr.t('Reading the code…'))
              .fontSize(13)
              .fontColor('#38E8A0')
          }
          .padding({ top: 8 })
        }
        Blank()
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0E1621')
    .padding({ top: this.safeTop })
  }
}
