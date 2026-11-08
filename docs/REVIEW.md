# WGate（维门）· 上架审核说明

给应用市场审核用的说明：这个应用是什么、申请了什么、后台在做什么。所有条目都能在仓库里找到对应代码，路径写在每节末尾。

| 项 | 值 |
| --- | --- |
| 应用名 | WGate（中文名「维门」，仅用于展出与备案，包内名称仍是 WGate） |
| 包名 | `com.wgate.app` |
| 版本 | 1.0.0（versionCode 1000000，首个提审版本） |
| 类型 | 工具 · 网络连接（VPN 客户端） |
| 服务器 | **本应用不运营任何服务器**，不提供节点、订阅或账号 |

## 一、应用做什么

用户自己搭建一台 WireGuard 服务端（家用 NAS、公司内网、云主机都行），把配置导入 WGate，就能在手机、平板、电脑上连回自己的网络。应用只做一件事：把你设备上的流量按配置加密，送到你填的那台服务器。

应用里没有账号体系，没有服务器列表，没有内置节点，也没有任何「购买/开通」入口。

## 二、申请的权限（全部 normal 级）

| 权限 | 用途 | 触发时机 |
| --- | --- | --- |
| `ohos.permission.INTERNET` | 建立加密隧道，与你配置的服务器通信 | 隧道连接期间 |
| `ohos.permission.GET_NETWORK_INFO` | 识别当前网络类型（Wi-Fi / 移动数据 / 以太网），用于自动隧道与断线重连 | 网络变化时 |
| `ohos.permission.GET_WIFI_INFO` | 读取当前 Wi-Fi 名称，用于「连上某个 Wi-Fi 就启动某条隧道」的规则 | 网络切换时 |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | 申请后台执行，保持隧道与通知同步 | 退到后台时 |
| `ohos.permission.CAMERA` | 扫描 WireGuard 配置二维码 | 仅在用户点「扫描二维码」时 |
| `ohos.permission.PRIVACY_WINDOW` | 显示私钥或二维码时阻止截屏与录屏 | 该页面显示期间 |

见 `entry/src/main/module.json5` 的 `requestPermissions`。

通知不是 manifest 权限，而是系统在运行时单独询问：连接隧道时应用会请求通知授权（`requestEnableNotification`），因为通知栏里那条状态通知是隧道在后台唯一的可见入口（隧道本身由 VPN 扩展进程持有，不受应用进程挂起影响）。用户拒绝时隧道照常工作，只是通知栏里不出现状态通知；用户随时可以在「设置 → 外观 → 通知」页最上面的「设置」行打开系统开关，打开后通知会在下一次刷新时自动出现，不需要重连。

见 `entry/src/main/ets/service/Notifier.ets` 的 `requestIfOff`，调用点是 `entry/src/main/ets/pages/Index.ets` 与 `entry/src/main/ets/view/TunnelsView.ets` 的连接入口。

## 三、后台能力声明（`backgroundModes`）

`module.json5` 里 `EntryAbility` 声明了一项后台模式：

```json5
"backgroundModes": ["taskKeeping"]
```

需要说明四点：

1. **只在 PC / 2in1 上使用。** 代码按 `deviceInfo.deviceType === '2in1'` 判断，手机上不会申请这一类长时任务。
2. **只在有实际网络业务时持有。** 触发条件是「隧道已连接」或「自动隧道已开启」；回到前台或隧道结束立即 `stopBackgroundRunning` 释放。
3. **为什么必须是长时任务。** 桌面端关闭窗口后应用驻留系统托盘，用户从托盘随时查看/切换隧道；若进程被冻结，托盘就失效了。平台提供的长时任务类型里，与「应用需要持续运行」对应的只有 `taskKeeping`。
4. **手机上为什么不申请。** 平台的 `BackgroundMode` 没有 VPN/网络类型；手机端改用短时任务（每次 3 分钟、有每日配额），配额用尽时应用会记录一行日志并接受系统挂起，不伪装常驻。隧道本身由 VPN 扩展进程持有，不受应用进程挂起影响。

见 `entry/src/main/ets/service/KeepAlive.ets`（`holdContinuous` / `arm`）与 `entry/src/main/ets/entryability/EntryAbility.ets`（`onBackground` / `onForeground`）。

## 四、VPN 能力

- 扩展：`WgVpnExtAbility`，`"type": "vpn"`，由系统在独立进程启动；tun 设备由系统下发，应用不申请任何其他网络特权。
- 隧道内核为自写实现（WireGuard 协议），无外部服务端、无中转节点；流量只发往用户配置里填的那台服务器。
- 断开即释放 tun；应用退出后不会保留连接。

见 `entry/src/main/ets/vpnext/WgVpnExtAbility.ets`。

## 五、数据与隐私

- 没有账号，没有遥测，没有崩溃上报，没有广告 SDK，也没有任何第三方 SDK。
- 隧道配置（含私钥）、应用设置、启动日志只存在本机的应用私有目录；只有用户主动导出备份或显示二维码时才离开设备。
- 隐私政策由应用市场的协议服务生成并托管，**每个语言一份、编号各不相同**：
  - 简体中文 `agreementId=2069872513088805568`
    <https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2069872513088805568>
  - 繁體中文 `agreementId=2069887177466076864`
    <https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh-Hant-TW&agreementId=2069887177466076864>
  - English `agreementId=2069895149739073216`
    <https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=en&agreementId=2069895149739073216>
  应用内「设置 → 支持 → 隐私政策」按界面语言选对应编号，用页内 Web 组件直接显示协议全文；
  AGC 表单里的隐私政策 URL 填 <https://simon2137.github.io/WGate/privacy.html>
  （按浏览器语言跳到对应语言的协议页）。

## 六、审核复现步骤

1. 安装并打开应用，首屏是隧道列表（空列表时有引导文案）。
2. 点右上角 `+`，选「手动创建」或「从文件或 zip」，填入/导入一份 WireGuard 配置（`[Interface]` + `[Peer]`）。
3. 返回列表点那条隧道，连接（首次连接会弹出系统的通知授权询问，用于在通知栏显示隧道状态）；允许后通知栏出现当前隧道的状态通知，桌面端在系统托盘出现图标。
4. 断开、切换网络、退到后台再回来，均可复现自动重连与状态同步。
5. 设置 → 本地日志监控器可以导出启动记录，用于核对上述行为。

## 七、许可与归属

WGate 以 GPL-3.0 发布。界面与交互流程移植自开源项目 WG Tunnel（MIT），隧道内核为独立实现。与 WireGuard 官方、与 WG Tunnel 均无隶属或背书关系。「WireGuard」是 Jason A. Donenfeld 的注册商标，本项目仅在描述协议兼容性时使用。
