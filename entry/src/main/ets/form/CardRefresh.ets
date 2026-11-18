/**
 * Pushes fresh contents into the cards that are on the desktop.
 *
 * A card is redrawn when the launcher asks for it (every 30 minutes, see
 * resources/base/profile/wg_card.json) or when the app pushes something. That is
 * not fast enough for the one thing the card is for — flipping the switch and
 * seeing the result — so the app pushes right after a toggle: once quickly (the
 * switch paints as pressed, the state line changes) and once more when the
 * extension has had time to publish its first snapshot.
 *
 * The ids come from CardRegistry, a file both processes can read; this class
 * runs in the app process, where `formProvider.updateForm` is available.
 *
 * The registry also carries each card's layout, and a layout that is wrong is
 * visible: the 2x2 page puts the switch in the bottom-right corner while the 2x4
 * one puts it on the left. So before the first push of a process the sizes are
 * reconciled with the launcher's own report, and a card whose size is still
 * unknown is skipped instead of being repainted from a guess.
 */
import { common } from '@kit.AbilityKit';
import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardData } from './CardData';
import { CardEntry, CardRegistry } from './CardRegistry';
import { withTimeout } from '../util/Async';

const DOMAIN: number = 0x0001;
const TAG: string = 'CardRefresh';
/** The snapshot a start request produces lands in about a second. */
const EARLY_MS: number = 700;
const LATE_MS: number = 3000;
/**
 * A push is what keeps a card truthful, so the size check in front of it is not
 * allowed to hold the push for long: the launcher answers in milliseconds and a
 * push that never happens is worse than one made from the registry as it is.
 */
const RECONCILE_MS: number = 1500;

export class CardRefresh {
  /** Whether this process has already taken the launcher's report of the sizes. */
  private static sizesFresh: boolean = false;

  /** Every placed card gets the current state. Never throws. */
  static async all(context: common.UIAbilityContext): Promise<void> {
    await CardRefresh.push(context, context.config.colorMode);
  }

  /**
   * The same push from the VPN extension.
   *
   * That process is the one that sees a tunnel actually come up, and it outlives
   * the app in the background: pushing from here is what stops the card from
   * sitting on "connecting" until the user opens the app. It is not a UIAbility,
   * so the colour mode is handed in instead of read off the context.
   */
  static async fromService(context: common.Context, colorMode: number | undefined): Promise<void> {
    await CardRefresh.push(context, colorMode);
  }

  private static async push(context: common.Context, colorMode: number | undefined): Promise<void> {
    if (!CardRefresh.sizesFresh) {
      await CardRefresh.reconcile();
    }
    const forms: Record<string, CardEntry> = CardRegistry.list();
    const ids: string[] = Object.keys(forms);
    if (ids.length === 0) {
      return;
    }
    for (let i = 0; i < ids.length; i++) {
      const formId: string = ids[i];
      const size: string = forms[formId].size;
      if (!CardRegistry.knownSize(size)) {
        // The layout decides where the switch sits, so a card whose size nobody
        // has reported keeps the drawing it has rather than being repainted with
        // a default that may be the wrong one. The launcher's next update fills
        // the size in (see WgCardAbility.onUpdateForm).
        hilog.warn(DOMAIN, TAG, `update ${formId} skipped, its size is unknown`);
        continue;
      }
      try {
        const data: Record<string, Object> = CardData.build(context, size,
          colorMode, forms[formId].tunnel);
        await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
        CardRefresh.nextTick(formId, data);
      } catch (err) {
        // A card the launcher has already dropped answers with an error; that is
        // not worth breaking the refresh of the other cards over.
        hilog.warn(DOMAIN, TAG, `update ${formId} failed: ${(err as BusinessError).code}`);
      }
    }
  }

  /**
   * Takes the launcher's report of which cards are placed and how big they are.
   *
   * This is the one authority on the grid, so it repairs a registry entry an
   * older build guessed (a 2x4 card recorded as 2x2, which paints the square
   * layout) and adds a card the file never saw. It runs at most once per process,
   * before the first push; a launcher that refuses leaves the registry as it is,
   * and the push above skips whatever that leaves unknown.
   */
  private static async reconcile(): Promise<void> {
    try {
      const placed: formInfo.RunningFormInfo[] = await withTimeout(
        formProvider.getPublishedRunningFormInfos(), RECONCILE_MS, 'card sizes');
      const sizes: Record<string, string> = {};
      for (let i = 0; i < placed.length; i++) {
        sizes[placed[i].formId] = CardData.sizeOf(placed[i].dimension);
      }
      CardRegistry.reconcile(sizes);
      CardRefresh.sizesFresh = true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `card sizes not reconciled: ${(err as Error).message}`);
    }
  }

  /** The pair of pushes a toggle needs: the reaction, then the truth. */
  static soon(context: common.UIAbilityContext): void {
    CardRefresh.after(context, EARLY_MS);
    CardRefresh.after(context, LATE_MS);
  }

  /**
   * A couple of late pushes after a start request.
   *
   * The extension is supposed to announce a tunnel that comes up (see
   * WgVpnExtAbility.pushCards); this is the belt to that braces, for the case
   * where the app is still scheduled and the announcement is lost.
   */
  static settle(context: common.UIAbilityContext): void {
    CardRefresh.after(context, 2000);
    CardRefresh.after(context, 5000);
  }

  static after(context: common.UIAbilityContext, delayMs: number): void {
    setTimeout(() => {
      CardRefresh.all(context).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, `refresh failed: ${err.message}`);
      });
    }, delayMs);
  }

  /**
   * Asks for another update while a tunnel is up.
   *
   * The form config's own interval is 30 minutes, which is fine for a card that
   * says "disconnected" but not for one counting the minutes a tunnel has been
   * running: half an hour later it would still claim the tunnel is five seconds
   * old. Five minutes is the smallest interval the platform accepts.
   */
  static nextTick(formId: string, data: Record<string, Object>): void {
    if (data['state'] !== 'up') {
      return;
    }
    formProvider.setFormNextRefreshTime(formId, 5).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, `next refresh for ${formId} failed: ${err.code}`);
    });
  }
}
