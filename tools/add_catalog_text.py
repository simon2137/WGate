"""Add rows the reference app has no translation for.

`tools/add_catalog_row.py` copies a translation out of the reference's
`values-*/strings.xml`. Some strings in this build were written here — the theme
picker's one-line descriptions, for instance — so there is nothing to copy: the
wording itself is authored, and the translation has to be authored with it.

    python tools/add_catalog_text.py

The table below is that authored wording. Rows are keyed by the English text,
exactly like the imported ones, and the insert is idempotent: a key already
present in a locale is left alone, so re-running after editing one translation
only adds the rows that are missing.

Keep the English column byte-identical to the `Tr.t(...)` call site, otherwise
the lookup misses and the interface silently stays English.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / 'entry' / 'src' / 'main' / 'ets' / 'i18n' / 'Catalog.ets'

SEP_ROW = '\u0001'
SEP_COL = '\u0002'

# english key -> {locale: translation}
AUTHORED: dict[str, dict[str, str]] = {
    # Support tab, the email row on a device with no mail client: the address is
    # copied instead, and the toast has to say which of the two rows it came from.
    'The address is on the clipboard': {
        'zh_CN': '邮箱地址已复制',
        'zh_TW': '電子郵件地址已複製',
    },
    # Singular of the reference's `seconds` (秒). The reference only carries the
    # plural, so a bare `Second` would print "1 seconds" in English. The key is
    # the whole label rather than the word: `Second` is a prefix of `Seconds`,
    # and `check_catalog_rows.py` rejects a key that another key starts with.
    '1 second': {
        'zh_CN': '1 秒',
        'zh_TW': '1 秒',
    },
    # Display theme page (`pages/Display.ets`). The reference's strings.xml has
    # no description strings for these rows — it renders titles only — so these
    # lines are ours.
    'The default palette': {
        'zh_CN': '默认调色板',
        'zh_TW': '預設調色盤',
    },
    'Light surfaces on a white background': {
        'zh_CN': '白色背景上的浅色外观',
        'zh_TW': '白色背景上的淺色外觀',
    },
    'Follow the system appearance': {
        'zh_CN': '跟随系统外观',
        'zh_TW': '跟隨系統外觀',
    },
    'Follow the system accent colour': {
        'zh_CN': '跟随系统强调色',
        'zh_TW': '跟隨系統強調色',
    },
    'Dim the surfaces a step further': {
        'zh_CN': '在深色基础上再压暗一档',
        'zh_TW': '在深色基礎上再壓暗一階',
    },
    'True black, for OLED panels': {
        'zh_CN': '纯黑，适合 OLED 屏幕',
        'zh_TW': '純黑，適合 OLED 螢幕',
    },
    # The tunnel-state labels `service/EngineStatus.ets` reports. The reference
    # carries `tunnel_state_connected`/`_disconnected` but not these two states,
    # so their wording is ours.
    'Connecting…': {
        'zh_CN': '正在连接…',
        'zh_TW': '正在連線…',
    },
    'Failed': {
        'zh_CN': '连接失败',
        'zh_TW': '連線失敗',
    },
    # Title of the configuration screen while the engine is live. The reference
    # only has "View live tunnel", which is the row that opens it.
    'Live tunnel': {
        'zh_CN': '实时隧道',
        'zh_TW': '即時隧道',
    },
    # The footnote under the theme list. Its first half comes from the reference
    # (`…picked. Automatic `), which ends mid-sentence, so the rest is here.
    'follows the device appearance; Dynamic has no accent API on HarmonyOS, so it paints the dark '
    'palette that the reference sits on.': {
        'zh_CN': '跟随设备外观；Dynamic 在鸿蒙上没有强调色 API，因此沿用参考实现所用的深色调色板。',
        'zh_TW': '跟隨裝置外觀；Dynamic 在鴻蒙上沒有強調色 API，因此沿用參考實作所用的深色調色盤。',
    },
    # The recovery delay row (`pages/TunnelRecovery.ets`). The reference worded
    # this row "Handshake failure threshold before recovery triggers", which
    # reads as a count of failed handshakes; that is not what this build does.
    # `service/TunnelGuard.ets` waits that many seconds of silence and then asks
    # the system for the extension again, so the wording says seconds.
    'How long the tunnel has to stay silent, in seconds, before it is started again': {
        'zh_CN': '隧道静默多少秒之后重新拉起',
        'zh_TW': '隧道靜默多少秒之後重新拉起',
    },
    # Sentences the reference splits across two resources at an English comma.
    # Translating only the first half leaves the second one in English on screen
    # ("…保持保护 switches and NAT issues"), so the tail is a key of its own. The
    # seamless-recovery one is not split at all — Chinese word order puts the NAT
    # clause before the verb, so the whole sentence is translated as one row.
    'Keeps protection while recovering from DDNS changes, network switches and NAT issues': {
        'zh_CN': '在 DDNS 变更、网络切换和 NAT 问题等恢复期间保持保护',
        'zh_TW': '在 DDNS 變更、網路切換和 NAT 問題等恢復期間保持保護',
    },
    'open-source WireGuard client, but this is only possible with your support.': {
        'zh_CN': '开源 WireGuard 客户端，但这只有靠你的支持才能做到。',
        'zh_TW': '開源 WireGuard 用戶端，但這只有靠你的支持才能做到。',
    },
    'The code holds the whole configuration, keys included, so only scan it with a peer you trust.': {
        'zh_CN': '这段代码包含完整配置（含密钥），请只与信任的对端互相扫描。',
        'zh_TW': '這段代碼包含完整設定（含金鑰），請只與信任的對端互相掃描。',
    },
    # The ongoing notification (service/TunnelNotice.ets). Its text is composed
    # here rather than in the reference app, which words the shade differently.
    # `Reconnecting…` is a state of its own so the recovery switch has something
    # to show; the bearer names are the words the origin line uses.
    'Reconnecting…': {
        'zh_CN': '正在重新连接…',
        'zh_TW': '正在重新連線…',
    },
    'Cellular': {
        'zh_CN': '移动数据',
        'zh_TW': '行動數據',
    },
    # `Ethernet` alone cannot be a key: the reference already has
    # `Tunnel on Ethernet`, and a key that appears inside another row would make
    # the lookup ambiguous (tools/check_catalog_rows.py rejects exactly that), so
    # the wired bearer is named in full.
    'Wired Ethernet': {
        'zh_CN': '有线以太网',
        'zh_TW': '有線乙太網路',
    },
    # The reference offers a "failure tint", but the platform cannot tint a
    # notification (`notificationRequest.color` is documented as "Not supported
    # currently"), so the row is named after what the app actually does: a mark.
    'Failure mark': {
        'zh_CN': '失败标记',
        'zh_TW': '失敗標記',
    },
    'Mark the notification while the tunnel is down': {
        'zh_CN': '隧道断开时在通知上加标记',
        'zh_TW': '隧道斷開時在通知上加標記',
    },
    # The origin line of the notification reuses the list's template, which the
    # reference only translated for some locales.
    'via %1$s': {
        'zh_CN': '经 %1$s',
        'zh_TW': '經 %1$s',
    },
    # The desktop tray (service/PcTray.ets) was written with Chinese literals,
    # which stayed Chinese on an English device; the menu and the hover text are
    # catalogued like everything else.
    'Connect tunnel': {
        'zh_CN': '连接隧道',
        'zh_TW': '連線隧道',
    },
    'Disconnect tunnel': {
        'zh_CN': '断开隧道',
        'zh_TW': '中斷連線隧道',
    },
    'Open main interface': {
        'zh_CN': '打开主界面',
        'zh_TW': '開啟主介面',
    },
    # The engine calls a session younger than REJECT_AFTER "up" even with the
    # radio off; the published state says `offline` instead, and the shade needs
    # a word for it ("No network" already exists in the reference catalogue).
    'Waiting for the network': {
        'zh_CN': '等待网络',
        'zh_TW': '等待網路',
    },
    # Second line of the shade while a tunnel that already worked comes back.
    'down for %1$s': {
        'zh_CN': '已断开 %1$s',
        'zh_TW': '已斷開 %1$s',
    },
    # The log page: one flat trace, exported to a file and cleared in place.
    'What the app and the VPN extension recorded': {
        'zh_CN': '应用和 VPN 扩展记录的内容',
        'zh_TW': '應用和 VPN 擴充功能記錄的內容',
    },
    'Nothing has been recorded yet': {
        'zh_CN': '还没有任何记录',
        'zh_TW': '還沒有任何記錄',
    },
    'Send this file when a tunnel misbehaves': {
        'zh_CN': '隧道出问题时可以把这个文件发出去',
        'zh_TW': '隧道出問題時可以把這個檔案傳出去',
    },
    'Saved the log to %1$s': {
        'zh_CN': '日志已保存到 %1$s',
        'zh_TW': '日誌已儲存到 %1$s',
    },
    'Could not export the log: %1$s': {
        'zh_CN': '无法导出日志：%1$s',
        'zh_TW': '無法匯出日誌：%1$s',
    },
    'Log cleared': {
        'zh_CN': '日志已清空',
        'zh_TW': '日誌已清空',
    },
    'Exported %1$s tunnel(s)': {'zh_CN': '已导出 %1$s 个隧道', 'zh_TW': '已匯出 %1$s 個隧道'},
    'Restored %1$s tunnel(s) from the file': {'zh_CN': '已恢复 %1$s 个隧道', 'zh_TW': '已還原 %1$s 個隧道'},
    'Restored %1$s tunnel(s), skipped %2$s': {'zh_CN': '已恢复 %1$s 个隧道，跳过 %2$s 个', 'zh_TW': '已還原 %1$s 個隧道，跳過 %2$s 個'},
    'Export failed: %1$s': {'zh_CN': '导出失败：%1$s', 'zh_TW': '匯出失敗：%1$s'},
    'Restore failed: %1$s': {'zh_CN': '恢复失败：%1$s', 'zh_TW': '還原失敗：%1$s'},
    'Restore failed: no tunnels in this file': {'zh_CN': '恢复失败：这个文件里没有隧道', 'zh_TW': '還原失敗：這個檔案裡沒有隧道'},
    'Restore failed: unrecognised file': {'zh_CN': '恢复失败：无法识别的文件', 'zh_TW': '還原失敗：無法辨識的檔案'},
    'Restore failed: the file has no usable [Interface] and [Peer]': {'zh_CN': '恢复失败：文件里没有可用的 [Interface] 和 [Peer]', 'zh_TW': '還原失敗：檔案裡沒有可用的 [Interface] 和 [Peer]'},
    'Restored tunnel': {'zh_CN': '恢复的隧道', 'zh_TW': '還原的隧道'},
    # The support tab now carries only what belongs to this app: the licence
    # page and the privacy policy (both pages in the app, no external links),
    # and the version. See view/SupportView.ets and pages/Privacy.ets.
    'Open source': {
        'zh_CN': '开源',
        'zh_TW': '開源',
    },
    'GPL-3.0, the components in this build, and where the source is': {
        'zh_CN': 'GPL-3.0、本次构建包含的组件，以及源码在哪里',
        'zh_TW': 'GPL-3.0、本次建置包含的元件，以及原始碼在哪裡',
    },
    # "Privacy" alone cannot be a key: it is inside the existing row "Privacy
    # policy", and check_catalog_rows.py rejects a key that another English row
    # contains. The section header says what the section is about instead.
    'Your data': {
        'zh_CN': '您的数据',
        'zh_TW': '您的資料',
    },
    'What stays on this device, and what never leaves it': {
        'zh_CN': '哪些内容留在本机，哪些永远不会离开',
        'zh_TW': '哪些內容留在本機，哪些永遠不會離開',
    },
    # The privacy policy is a page in the app rather than a link, so its
    # sentences have to live here. Each paragraph is a statement about what the
    # build actually does -- keep them in step with the code that does it.
    'No accounts, no telemetry, no analytics. This app runs no server of its own and does not upload your configuration anywhere.': {
        'zh_CN': '没有账号，没有遥测，没有统计。本应用不运营自己的服务器，也不会把您的配置上传到任何地方。',
        'zh_TW': '沒有帳號，沒有遙測，沒有統計。本應用程式不營運自己的伺服器，也不會把您的設定上傳到任何地方。',
    },
    'Tunnel configurations, private keys included, are stored in the app\u2019s private preferences on this device. They leave it only when you export a backup or show a QR code, and both of those are things you start.': {
        'zh_CN': '隧道配置（含私钥）保存在本机的应用私有存储中。只有当您主动导出备份或展示二维码时，它们才会离开这台设备。',
        'zh_TW': '通道設定（含私鑰）儲存在本機的應用程式私有儲存空間中。只有當您主動匯出備份或顯示 QR code 時，它們才會離開這台裝置。',
    },
    'The startup trace under Local logging stays in the app\u2019s private files. It records state changes and errors, not packet contents, and you can clear it or export it at any time.': {
        'zh_CN': '“本地日志监控器”里的启动记录只保存在应用私有文件中。它记录状态变化和错误，不记录数据包内容，您可以随时清空或导出。',
        'zh_TW': '「本機日誌監控器」中的啟動記錄只儲存在應用程式私有檔案中。它記錄狀態變化和錯誤，不記錄封包內容，您可以隨時清除或匯出。',
    },
    'The permissions are the ones the app is named for: INTERNET and the VPN extension for tunnel traffic, GET_NETWORK_INFO and GET_WIFI_INFO to tell Wi-Fi from mobile data, CAMERA only while you scan a configuration. Nothing else is requested.': {
        'zh_CN': '申请的权限只有应用本身需要的那几项：INTERNET 和 VPN 扩展用于隧道流量，GET_NETWORK_INFO 和 GET_WIFI_INFO 用于区分 Wi-Fi 与移动数据，CAMERA 只在进行扫码时使用。没有其它权限。',
        'zh_TW': '申請的權限只有應用程式本身需要的那幾項：INTERNET 和 VPN 擴充功能用於通道流量，GET_NETWORK_INFO 和 GET_WIFI_INFO 用於區分 Wi-Fi 與行動數據，CAMERA 只會在掃描設定時使用。沒有其它權限。',
    },
    'No advertising SDK, crash reporter or tracker is linked into this build. The only traffic the app generates is the tunnel itself.': {
        'zh_CN': '本次构建没有链接任何广告 SDK、崩溃上报或追踪组件。应用产生的唯一流量就是隧道本身。',
        'zh_TW': '本次建置沒有連結任何廣告 SDK、當機回報或追蹤元件。應用程式產生的唯一流量就是通道本身。',
    },
    'Uninstalling the app removes the stored tunnels, the settings and the trace with it. There is no copy anywhere else.': {
        'zh_CN': '卸载应用会一并删除已保存的隧道、设置和日志，其它地方不会留有副本。',
        'zh_TW': '解除安裝應用程式會一併刪除已儲存的通道、設定和日誌，其它地方不會留有副本。',
    },
    'Last updated: October 2026': {
        'zh_CN': '最后更新：2026 年 10 月',
        'zh_TW': '最後更新：2026 年 10 月',
    },
    # The paragraph above the licence table: the port has to be stated in prose,
    # which is what GPL-3.0 5(a) (prominent notice that the work was modified)
    # and the MIT notice both ask for.
    'WGate is a port of WG Tunnel, the Android app by Zane Schepke: its interface, its wording and its interaction flows come from there, while the tunnel core was written for HarmonyOS. The upstream project is released under the MIT license, so its copyright line and permission text travel with every copy of this app and are printed in full at the end of this page. WGate itself is a separate work, licensed under GPL-3.0.': {
        'zh_CN': 'WGate 是 WG Tunnel（Zane Schepke 的 Android 应用）的移植：界面、文案和交互流程来自该项目，隧道内核则为 HarmonyOS 重新编写。上游项目以 MIT 许可发布，因此其版权声明与许可文本随本应用的每一份副本一起分发，并在本页末尾完整印出。WGate 本身是独立作品，以 GPL-3.0 授权。',
        'zh_TW': 'WGate 是 WG Tunnel（Zane Schepke 的 Android 應用）的移植：介面、文案和互動流程來自該專案，隧道核心則為 HarmonyOS 重新撰寫。上游專案以 MIT 授權發布，因此其版權聲明與授權文本隨本應用的每一份副本一起分發，並在本頁末尾完整印出。WGate 本身是獨立作品，以 GPL-3.0 授權。',
    },
    # The licence page splits into this app, the MIT project it descends from
    # and the components that ship inside the package.
    'This application': {
        'zh_CN': '本应用',
        'zh_TW': '本應用',
    },
    'Upstream project': {
        'zh_CN': '上游项目',
        'zh_TW': '上游專案',
    },
    'Third-party components': {
        'zh_CN': '第三方组件',
        'zh_TW': '第三方元件',
    },
    'WG Tunnel (the Android app this port started from)': {
        'zh_CN': 'WG Tunnel（本移植所基于的 Android 应用）',
        'zh_TW': 'WG Tunnel（本移植所依據的 Android 應用）',
    },
    'WGate ports its interface, its wording and its flows from this project': {
        'zh_CN': 'WGate 的界面、文案和交互流程移植自该项目',
        'zh_TW': 'WGate 的介面、文案和互動流程移植自該專案',
    },
    'Zig (the C compiler used for the native core at build time)': {
        'zh_CN': 'Zig（构建时编译原生内核的 C 编译器）',
        'zh_TW': 'Zig（建置時編譯原生核心的 C 編譯器）',
    },
    'Huawei SDK licence': {
        'zh_CN': '华为 SDK 许可',
        'zh_TW': '華為 SDK 授權',
    },
    'MIT license of the upstream project': {
        'zh_CN': '上游项目的 MIT 许可',
        'zh_TW': '上游專案的 MIT 授權',
    },
    # The licence page states where the corresponding source is, because
    # GPL-3.0 requires it to be obtainable from whoever has the binary.
    'GPL-3.0 requires the corresponding source of this exact build to be available to anyone who has the binary. It is published with every release in the project repository, together with the revision and the build recipe used for this package. If you received the app without it, write to the address under the version row and it will be sent.': {
        'zh_CN': 'GPL-3.0 要求：任何拿到本程序的人都能获得与本次构建对应的完整源码。源码随每个版本发布在项目仓库中，并附上用于构建此安装包的版本号与构建方式。如果拿到应用时没有同时获得源码，可按下方的联系方式索取，我们会寄送。',
        'zh_TW': 'GPL-3.0 要求：任何拿到本程式的人都能取得與本次建置對應的完整原始碼。原始碼隨每個版本發佈在專案倉庫中，並附上用於建置此安裝包的版本號與建置方式。如果拿到應用程式時沒有同時取得原始碼，可按下方的聯絡方式索取，我們會寄送。',
    },
    # The Support tab (`view/SupportView.ets`). The licence list and the privacy
    # policy are the two pages of legal text this build ships, so they share one
    # section; no reference group label names that pair (its `Resources` group
    # also holds the website and the donation page, which this build keeps out
    # of the tab).
    'Legal information': {
        'zh_CN': '法律信息',
        'zh_TW': '法律資訊',
    },
    # The contact section links the source of this build. The reference only
    # words a link to its issue tracker ("Open an issue"), which is the wrong
    # page to send a reader of the repository to.
    # Add-tunnel sheet (`Home.ets`) and the file/zip importer. The reference has
    # the row titles; everything the importer says back to the user is ours.
    # The two Imported* keys must not share a prefix: `check_catalog_rows.py`
    # rejects a key that another key starts with.
    '.conf, .wg, or a zip of them': {
        'zh_CN': '.conf、.wg，或它们的 zip 压缩包',
        'zh_TW': '.conf、.wg，或它們的 zip 壓縮檔',
    },
    'Imported %1$s': {
        'zh_CN': '已导入 %1$s',
        'zh_TW': '已匯入 %1$s',
    },
    'Imported tunnels: %1$s': {
        'zh_CN': '已导入 %1$s 条隧道',
        'zh_TW': '已匯入 %1$s 條隧道',
    },
    'Imported configuration': {
        'zh_CN': '导入的配置',
        'zh_TW': '匯入的設定',
    },
    'That file is not a WireGuard configuration': {
        'zh_CN': '这个文件不是 WireGuard 配置',
        'zh_TW': '這個檔案不是 WireGuard 設定',
    },
    'That zip holds no configuration': {
        'zh_CN': '这个压缩包里没有配置文件',
        'zh_TW': '這個壓縮檔裡沒有設定檔',
    },
    'Could not read that file': {
        'zh_CN': '读不了这个文件',
        'zh_TW': '讀不到這個檔案',
    },
    'The clipboard is empty': {
        'zh_CN': '剪贴板是空的',
        'zh_TW': '剪貼簿是空的',
    },
    'The clipboard holds no WireGuard configuration': {
        'zh_CN': '剪贴板里没有 WireGuard 配置',
        'zh_TW': '剪貼簿裡沒有 WireGuard 設定',
    },
    # Configuration editor (`ConfigEdit.ets`). The reference has labels for most
    # of these; the ones it phrases differently, or has no string for at all,
    # are authored here. `new_tunnel` is the create-mode title, matching the
    # reference opening the same screen with a null configuration.
    'Preshared key': {
        'zh_CN': '预共享密钥',
        'zh_TW': '預先共用金鑰',
    },
    'Show Amnezia options': {
        'zh_CN': '显示 Amnezia 参数',
        'zh_TW': '顯示 Amnezia 參數',
    },
    'Hide Amnezia options': {
        'zh_CN': '隐藏 Amnezia 参数',
        'zh_TW': '隱藏 Amnezia 參數',
    },
    'Rotate': {
        'zh_CN': '重新生成',
        'zh_TW': '重新產生',
    },
    'base64 key': {
        'zh_CN': 'base64 密钥',
        'zh_TW': 'base64 金鑰',
    },
    'optional': {
        'zh_CN': '可选',
        'zh_TW': '選填',
    },
    'separate values with commas': {
        'zh_CN': '多个值以逗号分隔',
        'zh_TW': '多個值以逗號分隔',
    },
    'server:port': {
        'zh_CN': '服务器:端口',
        'zh_TW': '伺服器:埠',
    },
    'tunnel name': {
        'zh_CN': '隧道名称',
        'zh_TW': '隧道名稱',
    },
    'random': {
        'zh_CN': '随机',
        'zh_TW': '隨機',
    },
    'The engine brings one interface up at a time; the hooks are written to the configuration text and are not executed by this build.': {
        'zh_CN': '引擎一次只启用一个接口；钩子会写入配置文本，但本版本不执行它们。',
        'zh_TW': '引擎一次只啟用一個介面；鉎子會寫入設定文字，但本版本不會執行它們。',
    },
    'Peer %1$s': {
        'zh_CN': '对端 %1$s',
        'zh_TW': '節點 %1$s',
    },
    'picked automatically': {
        'zh_CN': '自动选择',
        'zh_TW': '自動選擇',
    },
    '25 or 22-30, seconds': {
        'zh_CN': '25，或 22-30，单位秒',
        'zh_TW': '25，或 22-30，單位秒',
    },
    'New tunnel': {
        'zh_CN': '新建隧道',
        'zh_TW': '新增隧道',
    },
    'Interface and one peer': {
        'zh_CN': '填写接口和一个对端',
        'zh_TW': '填寫介面與一個對端',
    },
    'A private key is required': {
        'zh_CN': '必须填写私钥',
        'zh_TW': '必須填寫私鑰',
    },
    'Add at least one peer': {
        'zh_CN': '至少要添加一个对端',
        'zh_TW': '至少要新增一個對端',
    },
    'New key pair generated': {
        'zh_CN': '已生成新的密钥对',
        'zh_TW': '已產生新的金鑰對',
    },
    'Key generation is not available on this device': {
        'zh_CN': '这台设备无法生成密钥',
        'zh_TW': '這台裝置無法產生金鑰',
    },
    'Public key copied': {
        'zh_CN': '公钥已复制',
        'zh_TW': '公開金鑰已複製',
    },
    'Could not copy the public key': {
        'zh_CN': '复制公钥失败',
        'zh_TW': '複製公開金鑰失敗',
    },
    'Configuration saved': {
        'zh_CN': '配置已保存',
        'zh_TW': '設定已儲存',
    },
    'Project on GitHub': {
        'zh_CN': '开源项目',
        'zh_TW': '開源專案',
    },
}


def escape(value: str) -> str:
    return value.replace('\\', '\\\\').replace("'", "\\'")


def payload_bounds(text: str, locale: str) -> tuple[int, int] | None:
    marker = f"\n    ['{locale}', '"
    at = text.find(marker)
    if at < 0:
        return None
    end = text.find("'],", at)
    if end < 0:
        return None
    return at, end


def main() -> int:
    text = CATALOG.read_text(encoding='utf-8')
    added = 0
    for english, translations in AUTHORED.items():
        for locale, value in translations.items():
            bounds = payload_bounds(text, locale)
            if bounds is None:
                print(f'{locale}: not in the catalogue, skipped "{english}"')
                continue
            at, end = bounds
            if (english + SEP_COL) in text[at:end]:
                continue
            # Same trap the importer hit: an unterminated last row would swallow
            # the new one, so the separator is only added when it is missing.
            prefix = '' if text[at:end].endswith(SEP_ROW) else SEP_ROW
            row = f'{prefix}{english}{SEP_COL}{escape(value)}{SEP_ROW}'
            text = text[:end] + row + text[end:]
            added += 1

    if added:
        CATALOG.write_text(text, encoding='utf-8')
    print(f'{added} row(s) added across {len(AUTHORED)} key(s)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
