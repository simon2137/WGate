// Generated from the language list; keep the order used by the picker.
const LABELS: string[] = [
  'en:English',
  'zh_CN:中文（简体）',
  'zh_TW:中文（繁體）',
  'cs_CZ:Čeština',
  'de_DE:Deutsch',
  'es_ES:Español',
  'et_EE:Eesti',
  'eu_ES:Euskara',
  'fa_IR:فارسی',
  'fi_FI:Suomi',
  'fr_FR:Français',
  'hu_HU:Magyar',
  'id_ID:Bahasa Indonesia',
  'it_IT:Italiano',
  'ja_JP:日本語',
  'ka_GE:ქართული',
  'ko_KR:한국어',
  'nl_NL:Nederlands',
  'pl_PL:Polski',
  'pt_BR:Português (Brasil)',
  'pt_PT:Português (Portugal)',
  'ru_RU:Русский',
  'sk_SK:Slovenčina',
  'ta_IN:தமிழ்',
  'tr_TR:Türkçe',
  'uk_UA:Українська',
  'ur_PK:اردو',
  'vi_VN:Tiếng Việt',
];

/**
 * The three interfaces this build offers, in the order the picker lists them.
 *
 * The catalogue keeps every locale the reference ships a translation for, but
 * only these are reachable from the UI; `offeredLocale` folds anything else
 * onto one of them so the picker and the painted interface never disagree.
 */
export const OFFERED: string[] = ['en', 'zh_CN', 'zh_TW'];

/**
 * Folds a stored qualifier onto one of `OFFERED`.
 *
 * Earlier builds listed the whole reference catalogue and stored whatever was
 * picked, so `de_DE`, the old `system` sentinel and the region tags a device
 * reports all have to land somewhere. English is what those values rendered as
 * anyway, so that is where they go.
 */
export function offeredLocale(stored: string): string {
  if (stored === 'zh_CN' || stored === 'zh' || stored === 'zh-CN' || stored === 'zh-Hans') {
    return 'zh_CN';
  }
  if (stored === 'zh_TW' || stored === 'zh-HK' || stored === 'zh-Hant' || stored === 'zh-TW') {
    return 'zh_TW';
  }
  return 'en';
}

/**
 * Display name for a stored qualifier.
 *
 * Folds first, so a locale an earlier build allowed (but this one no longer
 * offers) is labelled with the interface it actually renders as.
 */
export function localeLabel(qualifier: string): string {
  const folded: string = offeredLocale(qualifier);
  for (let i = 0; i < LABELS.length; i++) {
    const entry: string = LABELS[i];
    const cut: number = entry.indexOf(':');
    if (entry.substring(0, cut) === folded) {
      return entry.substring(cut + 1);
    }
  }
  return folded;
}
