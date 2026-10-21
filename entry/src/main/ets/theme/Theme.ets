import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';

/**
 * Colours and type scale taken from the reference app's Compose theme
 * (`ui/theme/Color.kt` and `ui/theme/Type.kt`), so the two builds look like the
 * same product.
 *
 * The palette is no longer a set of frozen constants: the display theme is a
 * real setting now, so every colour is a getter that reads the scheme that was
 * applied last. Components repaint because each one subscribes to the
 * `theme_tick` counter in AppStorage — see `applyScheme`.
 */

export interface ColorScheme {
  background: string;
  surface: string;
  raised: string;
  primary: string;
  onSurface: string;
  muted: string;
  outline: string;
  up: string;
  slow: string;
  alert: string;
}

/** The palette the app shipped with, and the reference's default look. */
const DARK: ColorScheme = {
  background: '#1C1B1F',
  surface: '#21272A',
  raised: '#2E3538',
  primary: '#76BEBD',
  onSurface: '#F2F2F4',
  muted: '#8D9D9F',
  outline: '#5A6468',
  up: '#6DB58B',
  slow: '#D4C483',
  alert: '#CF6679'
};

/** One step darker than dark, for people who find the default too bright. */
const DARKER: ColorScheme = {
  background: '#101013',
  surface: '#14181A',
  raised: '#1E2426',
  primary: '#6FB2B1',
  onSurface: '#E6E6E8',
  muted: '#7F8C8E',
  outline: '#454E51',
  up: '#5FA37C',
  slow: '#BFB074',
  alert: '#C25F71'
};

/** True black, so an OLED panel can switch the pixels off. */
const AMOLED: ColorScheme = {
  background: '#000000',
  surface: '#0A0A0B',
  raised: '#141416',
  primary: '#76BEBD',
  onSurface: '#F2F2F4',
  muted: '#8D9D9F',
  outline: '#3A3F42',
  up: '#6DB58B',
  slow: '#D4C483',
  alert: '#CF6679'
};

/** Light surfaces; the accent is darkened so it stays readable on white. */
const LIGHT: ColorScheme = {
  background: '#F2F3F5',
  surface: '#FFFFFF',
  raised: '#E8EAEF',
  primary: '#2C7876',
  onSurface: '#17191B',
  muted: '#5A6669',
  outline: '#C5CBD1',
  up: '#2F7D57',
  slow: '#7E6F26',
  alert: '#B3261E'
};

let current: ColorScheme = DARK;

/** Maps a stored theme name to the scheme it paints. */
export function schemeFor(mode: string): ColorScheme {
  if (mode === 'light') {
    return LIGHT;
  }
  if (mode === 'darker') {
    return DARKER;
  }
  if (mode === 'amoled') {
    return AMOLED;
  }
  return DARK;
}

/**
 * Paints the app with `mode` and notifies every component: the counter in
 * AppStorage is what each `struct` subscribes to, so a bump repaints the whole
 * tree without remounting it.
 */
export function applyScheme(mode: string): void {
  current = schemeFor(mode);
  const tick: number = AppStorage.get<number>('theme_tick') ?? 0;
  AppStorage.setOrCreate('theme_mode', mode);
  AppStorage.setOrCreate('theme_tick', tick + 1);
}

/**
 * Applies the theme and then rebuilds the page stack from the list screen.
 *
 * Repainting attribute by attribute is not reliable here: ArkUI re-applies the
 * values that hang off a changed state variable, but a `Palette` read inside a
 * modifier whose expression did not change is not re-applied, which left the
 * surfaces of the previous scheme behind. Replacing the stack recreates every
 * node, so each colour is read again from the new scheme.
 */
/**
 * Rebuilds the page stack. ArkUI only re-applies the modifiers whose expression
 * changed, so swapping a palette (or the language catalogue) in place leaves the
 * already built nodes on the old values; replacing the stack recreates every
 * node so each value is read again.
 */
export function reloadUi(): void {
  setTimeout(() => {
    try {
      router.clear();
      router.replaceUrl({ url: 'pages/Home' });
    } catch (e) {
      const message: string = (e as Error).message;
      console.error(`ui: reload failed ${message}`);
    }
  }, 80);
}

export function applySchemeAndReload(mode: string): void {
  applyScheme(mode);
  reloadUi();
}

/** The scheme in force right now (also used by `applyScheme`). */
export function currentScheme(): ColorScheme {
  return current;
}

/** True when the active scheme paints light surfaces (high red nibble). */
export function isLightScheme(): boolean {
  return current.background.charAt(1) === 'F';
}

/**
 * Bright core of the bottom-panel glass highlight. A white light paints nothing
 * on the light palette, so the accent stands in for it there. Shared by the
 * panel's own material and the page's painted highlight so the two always match.
 */
export function glassCore(): string {
  return isLightScheme() ? '#6676BEBD' : '#73FFFFFF';
}

/** The soft spill around the bright core of the glass highlight. */
export function glassHalo(): string {
  return isLightScheme() ? '#2676BEBD' : '#26FFFFFF';
}

/**
 * Resolves the stored name to a name that `schemeFor` can paint.
 *
 * `automatic` follows the device: HarmonyOS reports the system appearance on
 * the ability configuration, so a light device gets the light palette. The
 * `dynamic` entry follows the system accent colour in the reference, which has
 * no API here, so it paints the dark scheme and says so on its row.
 */
export function resolveTheme(mode: string, context: common.UIAbilityContext): string {
  if (mode !== 'automatic') {
    return mode;
  }
  try {
    const colorMode: number | undefined = context.config.colorMode;
    const light: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    return colorMode === light ? 'light' : 'dark';
  } catch (e) {
    return 'dark';
  }
}

export class Palette {
  static get BACKGROUND(): string {
    return current.background;
  }

  static get SURFACE(): string {
    return current.surface;
  }

  static get RAISED(): string {
    return current.raised;
  }

  static get PRIMARY(): string {
    return current.primary;
  }

  static get ON_SURFACE(): string {
    return current.onSurface;
  }

  static get MUTED(): string {
    return current.muted;
  }

  static get OUTLINE(): string {
    return current.outline;
  }

  static get SILVER_TREE(): string {
    return current.up;
  }

  static get STRAW(): string {
    return current.slow;
  }

  static get ALERT(): string {
    return current.alert;
  }
}

/** The reference body/type scale, in fp. */
export class Type {
  static readonly BODY_LARGE: number = 16;
  static readonly BODY_MEDIUM: number = 14;
  static readonly BODY_SMALL: number = 12;
  static readonly LABEL_LARGE: number = 15;
  static readonly LABEL_MEDIUM: number = 12;
  static readonly TITLE_LARGE: number = 22;
  static readonly TITLE_MEDIUM: number = 16;
}

/** Material's 4dp grid, mostly used for the list rows. */
export const GAP: number = 4;
export const ROW_PAD_H: number = 16;
export const ROW_PAD_V: number = 8;
export const ROW_MIN_H: number = 42;
/**
 * Bottom padding under scrolling content. Leaves enough room for the last row
 * to sit fully above the floating capsule (it occupies about 72vp from the
 * bottom: 16vp edge gap + 56vp height, plus the drop shadow), leaving a clear
 * gap below the last row so nothing is covered when scrolled to the end.
 */
export const BAR_SPACE: number = 100;
/** The family registered from `resources/rawfile/inter.ttf`, as the original app. */
export const FONT: string = 'Inter';
