import { Catalog } from './Catalog';

/**
 * Runtime lookups for the interface strings.
 *
 * The translations come from the reference app (`values-*` folders). The key is
 * the English text itself, which keeps this side honest: a literal that the
 * reference words differently simply stays English instead of showing a wrong
 * translation. `Catalog` carries one payload per locale, encoded as
 * `english<col>translation` rows joined with <row>.
 */
let parsed: boolean = false;
const table: Map<string, string> = new Map<string, string>();
let current: string = 'en';

function load(): void {
  if (parsed) {
    return;
  }
  parsed = true;
  Catalog.DATA.forEach((payload: string, qualifier: string) => {
    const rows: string[] = payload.split(Catalog.SEP_ROW);
    for (let i = 0; i < rows.length; i++) {
      const row: string = rows[i];
      const cut: number = row.indexOf(Catalog.SEP_COL);
      if (cut <= 0) {
        continue;
      }
      const key: string = qualifier + Catalog.SEP_COL + row.substring(0, cut);
      table.set(key, row.substring(cut + 1));
    }
  });
}

export class Tr {
  /** Sets the language used by `t`. `en` means "the literal as written". */
  static setLocale(qualifier: string): void {
    current = qualifier;
    load();
  }

  static locale(): string {
    return current;
  }

  /** True when the catalogue carries this locale at all. */
  static supported(qualifier: string): boolean {
    return qualifier === 'en' || Catalog.DATA.has(qualifier);
  }

  /** All locales the reference ships translations for, plus English. */
  static locales(): string[] {
    const out: string[] = ['en'];
    for (let i = 0; i < Catalog.LOCALES.length; i++) {
      out.push(Catalog.LOCALES[i]);
    }
    return out;
  }

  /**
   * Translates an English literal. Falls back to the literal itself, which is
   * what happens for the strings this build words differently from the
   * reference — better English than a wrong translation.
   */
  static t(text: string): string {
    if (current === 'en') {
      return text;
    }
    load();
    const hit: string | undefined = table.get(current + Catalog.SEP_COL + text);
    return hit === undefined ? text : hit;
  }

  /**
   * Fills a translated template. The reference writes labels that carry their
   * own punctuation as `%1$s` templates (`peer: %1$s`, `handshake: %1$s`), so
   * the colon and its spacing come from the translation instead of being glued
   * on here.
   */
  static tf(text: string, ...values: string[]): string {
    let out: string = Tr.t(text);
    for (let i = 0; i < values.length; i++) {
      out = out.replace(`%${i + 1}$s`, values[i]);
    }
    return out;
  }
}
