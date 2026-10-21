import { router } from '@kit.ArkUI';
import { Palette, Type, ROW_PAD_H, BAR_SPACE, FONT } from '../theme/Theme';
import { SectionHeader } from '../components/SurfaceRow';
import { Tr } from '../i18n/Tr';

/**
 * The licence page. The reference shows an aboutlibraries list of the Android
 * dependency tree; this build links no Gradle dependencies at all, so the list
 * is what the package actually carries: the app itself, the C core compiled into
 * `libwgcore.so`, the typeface, the icon set and the platform SDK — plus the
 * Android project this port descends from, which is MIT and therefore has to
 * travel with every copy. GPL-3.0 wants the corresponding source to be
 * obtainable from anyone who has the binary, so that is stated here too instead
 * of being implied.
 */
interface Licence {
  name: string;
  version: string;
  licence: string;
  note?: string;
}

const APP_LICENCES: Licence[] = [
  { name: 'WGate', version: '1.0.0', licence: 'GPL-3.0' }
];

const UPSTREAM: Licence[] = [
  {
    name: Tr.t('WG Tunnel (the Android app this port started from)'),
    version: '2023-2025',
    licence: 'MIT',
    note: Tr.t('WGate ports its interface, its wording and its flows from this project')
  }
];

const COMPONENTS: Licence[] = [
  {
    name: 'Monocypher (X25519, ChaCha20-Poly1305)',
    version: '\u2014',
    licence: 'BSD-2-Clause / CC0-1.0',
    note: 'Copyright 2017-2020 Loup Vaillant'
  },
  { name: 'Inter typeface', version: '4.0', licence: 'SIL Open Font License 1.1' },
  { name: 'Material Symbols (icons)', version: '\u2014', licence: 'Apache-2.0' },
  {
    name: Tr.t('Zig (the C compiler used for the native core at build time)'),
    version: '\u2014',
    licence: 'MIT'
  },
  { name: 'HarmonyOS SDK and ArkUI', version: 'API 26', licence: Tr.t('Huawei SDK licence') }
];

const GPL_NOTE: string = Tr.t('WGate is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.\n\nWGate is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.\n\nThe full text of the GPL-3.0 is in the LICENSE file at the root of the repository this build was produced from, and at gnu.org/licenses/gpl-3.0.txt.');

const SOURCE_NOTE: string = Tr.t('GPL-3.0 requires the corresponding source of this exact build to be available to anyone who has the binary. It is published with every release in the project repository, together with the revision and the build recipe used for this package. If you received the app without it, write to the address under the version row and it will be sent.');

/** The upstream notice verbatim: MIT asks for the copyright line and this text. */
const MIT_NOTE: string = 'MIT License\n\nCopyright \u00a9 2023-2025 Zane Schepke\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.';

/**
 * What this page is about: the app is a port, and saying so in the prose — not
 * only in a table row — is what GPL-3.0 §5(a) and the MIT notice both ask for.
 */
const PORT_NOTE: string = Tr.t('WGate is a port of WG Tunnel, the Android app by Zane Schepke: its interface, its wording and its interaction flows come from there, while the tunnel core was written for HarmonyOS. The upstream project is released under the MIT license, so its copyright line and permission text travel with every copy of this app and are printed in full at the end of this page. WGate itself is a separate work, licensed under GPL-3.0.');

@Entry
@Component
struct License {
  @StorageProp('theme_tick') themeTick: number = 0;
  @StorageProp('safe_top') safeTop: number = 40;

  @Builder
  entries(list: Licence[]) {
    ForEach(list, (item: Licence) => {
      Column() {
        Row() {
          Text(item.name)
            .fontSize(Type.BODY_MEDIUM)
            .fontFamily(FONT)
            .fontColor(Palette.ON_SURFACE)
            .layoutWeight(1)
          Text(item.version)
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Text(item.licence)
          .fontSize(Type.BODY_SMALL)
          .fontFamily(FONT)
          .fontColor(Palette.PRIMARY)
          .width('100%')
          .margin({ top: 2 })

        if (item.note !== undefined) {
          Text(item.note)
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
            .width('100%')
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 10, bottom: 10 })
      .backgroundColor(Palette.SURFACE)
    }, (item: Licence) => item.name)
  }

  build() {
    Column() {
      Row() {
        Row() {
          Image($r('app.media.ic_back'))
            .width(24)
            .height(24)
            .fillColor(Palette.ON_SURFACE)
        }
        .width(48)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          router.back();
        })

        Column() {
          Text(Tr.t('Licences'))
            .fontSize(Type.TITLE_LARGE)
            .fontFamily(FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.ON_SURFACE)
          Text(Tr.t('What this build contains and under which terms'))
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .height(64)
      .padding({ left: ROW_PAD_H, right: ROW_PAD_H })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          Text(PORT_NOTE)
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
            .width('100%')
            .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 10, bottom: 4 })

          SectionHeader({ label: Tr.t('This application') })
          this.entries(APP_LICENCES)

          SectionHeader({ label: Tr.t('Upstream project') })
          this.entries(UPSTREAM)

          SectionHeader({ label: Tr.t('Third-party components') })
          this.entries(COMPONENTS)

          SectionHeader({ label: Tr.t('Source code') })

          Text(SOURCE_NOTE)
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
            .width('100%')
            .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 8, bottom: 8 })

          SectionHeader({ label: Tr.t('GNU General Public License v3.0') })

          Text(GPL_NOTE)
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
            .width('100%')
            .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 8, bottom: 8 })

          SectionHeader({ label: Tr.t('MIT license of the upstream project') })

          Text(MIT_NOTE)
            .fontSize(Type.BODY_SMALL)
            .fontFamily(FONT)
            .fontColor(Palette.MUTED)
            .width('100%')
            .padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: 8, bottom: 8 })

          Column().height(BAR_SPACE)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Palette.BACKGROUND)
    .padding({ top: this.safeTop })
  }
}
