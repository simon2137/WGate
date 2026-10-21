import { Diag } from '../util/Diag';

/**
 * Shape of the action ArkUI hands to `onWillDismiss` for a sheet.
 *
 * The declaration lives in `common.d.ts` as `DismissSheetAction`; it is
 * restated here only so the helper can name the parameter without importing
 * the whole component typings.
 */
interface SheetDismissAction {
  dismiss: () => void;
  reason: DismissReason;
}

/** A reason, in words, for the diagnostic log. */
function reasonName(reason: DismissReason): string {
  if (reason === DismissReason.TOUCH_OUTSIDE) {
    return 'outside tap';
  }
  if (reason === DismissReason.PRESS_BACK) {
    return 'back';
  }
  if (reason === DismissReason.CLOSE_BUTTON) {
    return 'close button';
  }
  return `reason ${reason}`;
}

/**
 * Let every interactive dismissal through, and leave a trace.
 *
 * Registering `onWillDismiss` is what turns the default dismissal off, so the
 * callback has to close the sheet itself: a tap on the mask, a drag down and
 * Back all arrive here as different `DismissReason`s. Without the callback a
 * mask tap was the one gesture that did nothing, which is the complaint this
 * answers - every panel of the app now leaves on a tap outside it, and the log
 * says which gesture did it when a panel behaves unexpectedly.
 */
export function sheetWillDismiss(name: string): (action: SheetDismissAction) => void {
  return (action: SheetDismissAction) => {
    Diag.write(`sheet: ${name} dismissed by ${reasonName(action.reason)}`);
    action.dismiss();
  };
}
