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
 */
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CardData } from './CardData';
import { CardRegistry } from './CardRegistry';
import { CardRefresh } from './CardRefresh';

const DOMAIN: number = 0x0001;
const TAG: string = 'WgCard';

export default class WgCardAbility extends FormExtensionAbility {
  /** Called by the launcher when a card is placed on the desktop. */
  onAddForm(want: Want): formBindingData.FormBindingData {
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
   * an update rather than a new form.
   */
  onUpdateForm(formId: string): void {
    let size: string = CardRegistry.sizeOf(formId);
    if (size.length === 0) {
      size = '2x2';
      CardRegistry.put(formId, size);
    }
    const data: Record<string, Object> = CardData.build(this.context, size, this.context.config.colorMode, CardRegistry.tunnelOf(formId));
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
