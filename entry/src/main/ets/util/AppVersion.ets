import { bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'AppVersion';

/** What the About rows read when the package cannot answer. */
const UNKNOWN: string = '\u2014';

/** Set once the package has answered; a failed lookup is not remembered, so it can be retried. */
let resolved: string = '';

/**
 * The version this package was built with, asked of the bundle the system
 * installed rather than written down next to the screen that shows it.
 *
 * The About row and the licence list each carried a `1.0.0` literal, and both
 * still said so after `AppScope/app.json5` moved to 1.0.1 — a number a person
 * has to remember to edit is a number that will be wrong. `getBundleInfoForSelfSync`
 * needs no context and no permission for the calling app's own record: the first
 * call costs one synchronous lookup, every later one is a variable read.
 */
export function appVersion(): string {
  if (resolved.length > 0) {
    return resolved;
  }
  try {
    const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    if (info.versionName.length > 0) {
      resolved = info.versionName;
    }
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'the package did not report a version: %{public}s',
      String((error as BusinessError).code));
  }
  return resolved.length > 0 ? resolved : UNKNOWN;
}
