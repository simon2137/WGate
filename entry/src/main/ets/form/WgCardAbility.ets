/**
 * The desktop card's provider.
 *
 * The launcher owns the card's lifetime and asks this extension to build the
 * contents; the app may also push new contents through `formProvider` (see
 * `CardRefresh`), which is why the build itself lives in `CardData` and this
 * class only handles the form lifecycle.
 *
 * A card is not a window: nothing here starts, stops or reads the tunnel engine
 * directly. The VPN extension publishes a snapshot every two seconds and this
 * process renders whatever is in it, so a card that cannot see the extension
 * says "disconnected" instead of inventing a state.
 *
 * The size is the other thing that has to be right rather than guessed: it picks
 * one of three layouts, and the square one puts the switch in the bottom-right
 * corner. `onAddForm` is handed it, `onUpdateForm` is not — a launcher only sends
 * the id — so the launcher is asked for the dimension instead of assuming one.
 */
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CardData } from './CardData';
import { CardRegistry } from './CardRegistry';
import { CardRefresh } from './CardRefresh';
import { Diag } from '../util/Diag';
import { withTimeout } from '../util/Async';

const DOMAIN: number = 0x0001;
const TAG: string = 'WgCard';
/**
 * The launcher answers a size question in milliseconds. A card that never gets
 * an answer is worse than one that keeps its last drawing, so the question is
 * bounded and the registry answers when the launcher does not.
 */
const SIZE_LOOKUP_MS: number = 1500;

export default class WgCardAbility extends FormExtensionAbility {
  /** Called by the launcher when a card is placed on the desktop. */
  onAddForm(want: Want): formBindingData.FormBindingData {
    // The shared state has to be ready before anything is recorded. `CardRegistry`
    // writes through `Diag.directory()`, which is '' until this runs, so recording
    // the size first quietly did nothing: a card added by a fresh process never
    // made it into the file, the next update filled the gap with the default, and
    // a 2x4 card was then painted with the 2x2 layout.
    CardData.init(this.context);
    const formId: string = WgCardAbility.value(want, formInfo.FormParam.IDENTITY_KEY);
    const dimension: number = Number.parseInt(
      WgCardAbility.value(want, formInfo.FormParam.DIMENSION_KEY), 10);
    const size: string = CardData.sizeOf(Number.isNaN(dimension) ? 2 : dimension);
    CardRegistry.put(formId, size);
    hilog.info(DOMAIN, TAG, `add form ${formId} as ${size}`);
    const data: Record<string, Object> =
      CardData.build(this.context, size, this.context.config.colorMode, CardRegistry.tunnelOf(formId));
    CardRefresh.nextTick(formId, data);
    return formBindingData.createFormBindingData(data);
  }

  /**
   * The periodic refresh the form config asks for (every 30 minutes), and the
   * moment a changed layout is noticed: a card dragged from 2x2 to 2x4 asks for
   * an update rather than a new form. The dimension itself only exists in the
   * launcher, so it is asked for; the registry is the fallback for a launcher that
   * refuses, and a card whose size cannot be established is left as it is drawn
   * rather than repainted with a guess.
   */
  onUpdateForm(formId: string): void {
    CardData.init(this.context);
    try {
      withTimeout(formProvider.getPublishedRunningFormInfoById(formId), SIZE_LOOKUP_MS, 'card size')
        .then((info: formInfo.RunningFormInfo) => {
          const size: string = CardData.sizeOf(info.dimension);
          CardRegistry.put(formId, size);
          this.render(formId, size);
        })
        .catch((err: Error) => {
          this.renderKnown(formId, `the launcher did not report the size (${err.message})`);
        });
    } catch (err) {
      this.renderKnown(formId, `the launcher cannot be asked for the size (${(err as Error).message})`);
    }
  }

  /** Renders with the size the registry knows, or skips the update. */
  private renderKnown(formId: string, reason: string): void {
    const size: string = CardRegistry.sizeOf(formId);
    if (CardRegistry.knownSize(size)) {
      this.render(formId, size);
      return;
    }
    hilog.warn(DOMAIN, TAG, `update form ${formId}: ${reason}`);
    Diag.write(`card: update of ${formId} skipped, ${reason}`);
  }

  /**
   * The card was dragged to another grid size.
   *
   * This is the one callback that carries the new dimension, so the layout follows
   * the grid at once instead of on the next timed update: a 2x4 card that kept the
   * square page is a 2x4 card whose switch sits in the bottom-right corner.
   */
  onSizeChanged(formId: string, newDimension: formInfo.FormDimension, newRect: formInfo.Rect): void {
    CardData.init(this.context);
    const size: string = CardData.sizeOf(newDimension);
    CardRegistry.put(formId, size);
    hilog.info(DOMAIN, TAG,
      `form ${formId} resized to ${size} (${newRect.width}x${newRect.height}vp)`);
    Diag.write(`card: ${formId} resized to ${size}`);
    this.render(formId, size);
  }

  private render(formId: string, size: string): void {
    const data: Record<string, Object> = CardData.build(this.context, size,
      this.context.config.colorMode, CardRegistry.tunnelOf(formId));
    formProvider.updateForm(formId, formBindingData.createFormBindingData(data))
      .catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, `update form ${formId} failed: ${err.code}`);
      });
    CardRefresh.nextTick(formId, data);
  }

  /** The card is gone; its id must not outlive it. */
  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, `remove form ${formId}`);
    CardRegistry.remove(formId);
  }

  /** Reads a want parameter as a string, '' when it is missing. */
  private static value(want: Want, key: string): string {
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined) {
      return '';
    }
    const value: Object | undefined = params[key];
    if (value === undefined || value === null) {
      return '';
    }
    return value.toString();
  }
}
