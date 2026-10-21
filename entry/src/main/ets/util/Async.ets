/**
 * A promise with a deadline.
 *
 * The VPN framework only settles `startVpnExtensionAbility` once the system
 * has asked the user (first connection) and the extension is running.  If the
 * authorisation surface is missing or never answers, the caller would wait
 * forever with every control disabled, so each call is bounded.
 */
export function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  return new Promise<T>((resolve: (value: T) => void, reject: (err: Error) => void) => {
    let settled: boolean = false;
    const timer: number = setTimeout(() => {
      if (!settled) {
        settled = true;
        reject(new Error(`timeout:${label}`));
      }
    }, ms);
    promise.then((value: T) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        resolve(value);
      }
    }).catch((err: Error) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        reject(err);
      }
    });
  });
}

export function isTimeout(err: Error): boolean {
  return err.message.startsWith('timeout:');
}
