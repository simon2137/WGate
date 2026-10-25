# WGate 上架华为应用市场（AGC）手册

> **最后与代码核对**：2026-10-25。第 3 节那份签名包对应应用代码 `33c29aa`。想知道文档有没有过期，跑这一条就知道——输出为空，说明应用代码从那之后没变过：
>
> ```powershell
> git diff --name-only 33c29aa..HEAD -- entry AppScope
> ```
>
> 有输出就说明包和文档都可能过期了，先重出包、再改本文档，然后提审。

> 目标产物：一个用**发布证书**签名的 `.app` 包，加上 AGC 后台的版本表单。
> 本地已就绪：密钥库、CSR、AGC 签发的 `.cer` 与 `.p7b`，出包脚本跑通，签名包已生成（见第 3 节）。还缺的是资质类材料：APP 备案号、软著。

## 0. 先过三道门槛（这三条决定"能不能上"，不是技术问题）

个人开发者 + 仅中国大陆 + VPN 客户端，是这个组合里最难的一种。三件事按顺序确认：

| # | 门槛 | 现状 | 说明 |
|---|---|---|---|
| 1 | **类目资质** | ❓ 待确认 | AGC 提交版本时会按应用分类列出必须上传的资质。VPN/网络代理在国内属"增值电信业务"，通常要求企业主体的《增值电信业务经营许可证》；个人账号基本拿不到 |
| 2 | **APP 备案**（工信部） | ❌ 没有 | 2023-09 起国内分发的 App 必须有备案号，AGC 表单里有必填栏。个人也能备案，但要走通管局流程，约 20 个工作日 |
| 3 | **软著**（计算机软件著作权） | ❓ 待确认 | 网络工具类经常被要求，正常 30~60 个工作日，可加急 |

**最省时间的核对方式**：AGC 里把应用建起来，进"版本信息 → 提审"，看系统给这个分类弹出的"资质要求"清单——那是唯一权威答案，比任何文档都准。如果清单里出现"增值电信业务经营许可证"，个人主体的国内这条路基本走不通，得转成企业主体，或者只做非大陆分发。

官方依据（点开自查）：
- [应用资质审核要求](https://developer.huawei.com/consumer/cn/doc/doccenter-submission/80301?docScope=all)
- [不收录类型](https://developer.huawei.com/consumer/cn/doc/doccenter-submission/50117)
- [应用审核政策](https://developer.huawei.com/consumer/cn/doc/doccenter-submission/50104)

关于 VPN 类，华为开发者问答里官方回复的原话是：

> 应用不得含未经批准自行建立或租用专线（含虚拟专用网络 VPN）等其他信道开展跨境经营活动的内容。

换句话说：**用于访问自有内网（家里/公司）的客户端**和**用于跨境访问的工具**在审核眼里是两回事，前者有讨论空间，后者直接不收录。WGate 的定位要按前者写（不内置服务器、不提供订阅、只连用户自己的 WireGuard 服务端），但最终仍以审核意见为准。

---

## 1. 材料清单

| 材料 | 状态 | 位置 |
|---|---|---|
| 发布密钥库 `.p12` | ✅ 已生成 | `signing/wgate-release.p12` |
| 证书请求文件 `.csr` | ✅ 已生成 | `signing/wgate-release.csr` |
| 密钥库口令 / 别名 | ✅ 已记录 | `signing/keystore-password.txt`（已在 .gitignore 里） |
| 发布证书 `.cer` | ✅ 已申请 | `signing/wgate-release.cer`（AGC 签发，链到 Huawei CBG Root CA G2） |
| 发布 Profile `.p7b` | ✅ 已申请 | `signing/wgate-release.p7b`（type release，bundle-name com.wgate.app） |
| 签名好的 `.app` | ✅ 已出 | `dist/WGate-1.0.0-signed.app`（提审用这份）｜ 源头 `build/outputs/default/wg-default-signed.app` ｜ 重签：`signing/sign-package.ps1` |
| 应用图标 216×216 | ✅ 已导出 | `signing/agc-assets/icon-216.png` |
| 截图：手机 / 平板 / 电脑 各 5 张 | ✅ 已备 | `signing/agc-assets/screenshots/{phone,tablet,pc}/01–05.png` |
| 中英文案（见第 4 节） | ✅ 已写好 | 本文档第 4.2 / 4.3 节，可直接复制 |
| 隐私政策正文 | ✅ 已上线 | https://simon2137.github.io/WGate/privacy.html（含"与 WireGuard 官方、与上游 WG Tunnel 均无隶属关系"声明） |
| APP 备案号 | ⛔ 待办 | 工信部备案系统 |
| 软著证书 | ⛔ 待确认 | 视类目要求 |

密钥参数（后面 AGC 和 DevEco 都要填）：

```
密钥库文件 : wgate-release.p12
别名 alias : wgate-release
算法       : ECC 384 位 (secp384r1) / SHA384withECDSA
口令       : 见 signing/keystore-password.txt
```

> 口令丢了就找不回，同一个包名以后升级也只能用这把密钥。请存进密码管理器。

---

## 2. AGC 侧四步 ✅ 已完成（留作复查：换机器、换证书、换包名时要重走）

控制台：<https://developer.huawei.com/consumer/cn/service/josp/agc/index.html>
先确认右上角是**已实名认证的个人账号**，然后从左下角"账号中心"把**开发者名称**设好（它会显示在应用详情页）。

### 2.1 创建项目与应用

1. 「我的项目」→ 新建项目 → 名称随意（`WGate`）。
2. 项目里「添加应用」→ 平台选 **HarmonyOS**，填：

   | 字段 | 填什么 |
   |---|---|
   | 应用名称 | `WGate` |
   | 应用包名 | `com.wgate.app` ← 必须和 `AppScope/app.json5` 完全一致，建完不能改 |
   | 默认语言 | 简体中文 |
   | 应用分类 | 工具 → 网络工具（没有就选最接近的"实用工具"） |

3. 建完回到「我的应用」，能看到 WGate 就对了。
   本账号实测结果：APP ID `6917619670586179463`，软件包类型 APP，支持设备 手机/平板/PC-2in1（与 `module.json5` 的 `deviceTypes` 一致，不要改）。

> 应用图标要传 `signing/agc-assets/icon-1024-fullbleed.png`。包里那张 `app_icon.png` 自带圆角、四角透明（alpha=0），AGC 会再套一层系统 mask，两套圆角叠加会出现毛边；fullbleed 版本用底板色 `#21272A` 把四角填平，套完 mask 正好是系统圆角。手机 / 平板 / PC-2in1 三个页签用同一张。

> 包名被占用会直接报错。若报"包名已存在"，说明这个包名在别的账号下注册过，得换包名（换包名要改 `AppScope/app.json5` 并重新出包）。

### 2.2 申请发布证书

「证书、APP ID和Profile」→ **证书** → 新增证书：

| 字段 | 填什么 |
|---|---|
| 证书名称 | `wgate-release` |
| 证书类型 | **发布证书** |
| 证书请求文件 | 上传 `signing/wgate-release.csr` |

下载得到的 `.cer` 存成 `D:\dsh\wg\signing\wgate-release.cer`。

> 常见错误：`CSR 格式不正确` → 多半是把 `.p12` 传上去了，要传 `.csr`。
> 一个账号最多 1 张发布证书 + 1 张调试证书。以前项目留下的证书可以在「证书」页删掉腾位置。

### 2.3 确认 APP ID

「证书、APP ID和Profile」→ **APP ID** → 检查是否已有 `com.wgate.app` 的 HarmonyOS 应用记录；没有就新增，应用类型选 **HarmonyOS 应用**，包名填 `com.wgate.app`。写错任何一个字符，后面 Profile 都会签不上。

### 2.4 申请发布 Profile

「证书、APP ID和Profile」→ **Profile** → 新增 Profile：

| 字段 | 填什么 |
|---|---|
| 名称 | `wgate-release` |
| 类型 | **发布** |
| 选择 APP ID | `com.wgate.app` |
| 选择证书 | 2.2 里那张 `wgate-release` |

下载 `.p7b` 存成 `D:\dsh\wg\signing\wgate-release.p7b`。

> 发布 Profile 与调试 Profile 用途不同：调试 Profile 绑设备 UDID，只能装到登记过的设备上；上架的包必须用发布 Profile。

这四步都已经走完，`signing/` 里的 `.cer` 和 `.p7b` 就是从这儿下来的。签名与出包见第 3 节；证书有效期到 2029-10-21，到期前重走一遍即可（换证书意味着换签名，同一个包名的升级链不能断，务必保管好 `wgate-release.p12`）。

---

## 3. 本地签名与出包 ✅ 已完成

**产物**：`dist/WGate-1.0.0-signed.app`（1,847,688 B，SHA-256 `f516bc38…`），从 `build/outputs/default/wg-default-signed.app` 复制而来。

| 校验项 | 结果 |
|---|---|
| 外层 App Pack 验签 | ✅ Verify success（证书链 → Huawei CBG Root CA G2，EC 384） |
| 内层 `entry-default.hap` 验签 | ✅ Verify success，`profile type is: release` |
| 包内 profile | ✅ `bundle-name: com.wgate.app` / `type: release` / `app-distribution-type: app_gallery` |
| 签名档有效期 | 2026-10-21 → 2029-10-21 |
| 开发者 ID（profile 里的 `developer-id`） | `200086000020059589` |

> 这一份是 2026-10-25 20:23 重打的，和提交 `33c29aa`（通知不再每次更新都响/震）同一份代码。**签名包会过期**——代码一变就得按 3.2 重新走一遍，别拿上一次的 `.app` 去提审。

### 3.1 为什么没走 hvigor 的 signingConfigs

DevEco Studio 26（hvigor 26）改了规矩：`build-profile.json5` 里 `storePassword` / `keyPassword` 必须是**加密后的密文**，解密用的材料放在 `storeFile` 同级的 `material/` 目录，而这个目录只有 IDE 的 Project Structure → Signing Configs 才会生成。手写明文口令有两条死路，都实测过：

- 口令 < 32 字符 → `00303116 Configuration Error: The length of the storePassword or keyPassword field in the signature configuration is less than 32`
- 口令 ≥ 32 字符 → 被当成密文去解密 → `ENOENT: no such file or directory, stat 'D:\dsh\wg\signing\material'`

所以改成直接调 SDK 自带的 `hap-sign-tool.jar`，用明文口令，先签 hap、再签 App Pack，两层各验一次。

### 3.2 两条命令出包

```powershell
# 1) 编出未签名的 App Pack（无 signingConfigs 时 hvigor 只打包、不签名）
$env:DEVECO_SDK_HOME = "C:\Program Files\Huawei\DevEco Studio\sdk"
& "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" assembleApp -p product=default -p buildMode=release --no-daemon

# 2) 签 hap → 重组 App Pack → 签 App Pack → 两层验签
powershell -ExecutionPolicy Bypass -File signing\sign-package.ps1
```

`signing/sign-package.ps1` 从 `signing/keystore-password.txt` 读口令，密钥和口令都不进版本管理。

```powershell
# 3) 拷一份带版本号名字的到 dist，并记下指纹（提审时对得上）
Copy-Item build\outputs\default\wg-default-signed.app dist\WGate-1.0.0-signed.app -Force
(Get-FileHash dist\WGate-1.0.0-signed.app -Algorithm SHA256).Hash
```

> 想用回 IDE 那套也行：Project Structure → Signing Configs 选同一份 p12 / cer / p7b，IDE 会把密文和 `material/` 目录写好，之后 hvigor 就能直接出签名包。

### 3.2.1 怎么确认包里是新代码

签名只负责"来源可信"，不负责"内容是最新的"。提审前对着这两个点核一次：

```powershell
# 解出内层 hap
$tmp = "$env:TEMP\wgapp"; Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path build\outputs\default\wg-default-signed.app), $tmp)

# 验签 + 看 profile 类型
& "C:\Program Files\Huawei\DevEco Studio\jbr\bin\java.exe" -jar `
  "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar" `
  verify-app -inFile "$tmp\entry-default.hap" -outProfile "$tmp\p.p7b"

# 包里有没有这次改动的痕迹（举例：通知修复引入的 isAlertOnce 应为 1）
python -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); b=b''.join(z.read(n) for n in z.namelist() if n.endswith('modules.abc')); print('isAlertOnce', b.count(b'isAlertOnce'))" "$tmp\entry-default.hap"
```

`verify:` 那一行是 `Verify success`、`profile type is: release` 就对了。再确认源码侧干净：

```powershell
git status --short      # 应为空
git log --oneline -1    # 记下这个提交号，和提审的包对上
```

### 3.3 能不能装到设备上验证

不能，也不用试：发布证书签出来的包 `app-distribution-type` 是 `app_gallery`，只允许 AGC 分发，`hdc install` 会报签名错误。本地能做的校验就是上面那两条 `verify-app`，过了就说明包是完整有效的。

---

## 4. 上架表单：逐项怎么填

「我的应用 → WGate → 版本信息 → 新建版本」。上传 `.app` 后，AGC 会自动读出包名/版本号/权限，剩下的手填：

### 4.1 基础信息

| 字段 | 内容 |
|---|---|
| 应用名称 | `WGate` |
| 一句话简介（≤80 字） | `鸿蒙上的 WireGuard 客户端：连上你自己的服务器，公共 Wi-Fi 上也能安全上网。` |
| 应用分类 | 工具 → 网络工具 |
| 年龄分级 | 按问卷如实选，工具类一般为 3+ |
| 应用图标 | `signing/agc-assets/icon-216.png`（216×216 PNG） |
| 截图 | 三个终端各 5 张，全部上传：`signing/agc-assets/screenshots/phone/`（1280×2832）、`tablet/`（2880×1920）、`pc/`（2062×1385，已裁到应用窗口）。顺序：`01` 添加隧道 · `02` 自动隧道 · `03` 设置/外观 · `04` 外观/主题 · `05` 主题/通知。手机与平板是整屏，电脑是按窗口裁好的一张应用窗口图 |

> 截图原始尺寸 1280×2832（≈1:2.21）。若 AGC 提示比例超限，改用"深色/浅色"两张和一个设置页即可凑够 3 张；实在不行我按 9:16 重新排版。

### 4.2 应用介绍（直接复制）

```
WGate 是鸿蒙上的 WireGuard 客户端，用来从任何地方连回自己的家庭网络或自己的服务器。

出门在外，手机接的是酒店、咖啡馆或公司的网络，可你要用的东西在家里：路由器后面的 NAS、打印机、摄像头、内网管理面板。把家里那台服务端配好，连上 WGate 之后，这些设备就像还在同一个局域网里一样能打开。

它不提供任何服务器、节点或订阅，也不内置第三方服务地址——你只连接自己搭建的那一台。

主要功能
· 一键连接 / 断开，多个隧道随意新建、改名、删除
· 一个隧道最多 8 个对端（peer），按 AllowedIPs 自动分流
· 粘贴配置、选 .conf 文件、扫自己服务端生成的二维码、从其他应用分享进来，四种方式都能导入
· 自动隧道：Wi-Fi、移动数据、以太网分别指定连上哪个网络自动拉起哪条隧道
· 实时显示收发流量、握手时间、在线对端，以及内核事件日志
· 通知栏显示当前隧道和流量；鸿蒙 PC / 二合一设备上有托盘图标
· 深色 / 更深 / AMOLED / 浅色 / 跟随系统五档主题，中英文界面
· 支持 AmneziaWG 混淆参数（H1–H4、Jc、S1/S2、S3）

隐私
配置文件（含私钥）只存在这台设备上，应用不收集任何个人信息，没有账号，没有统计上报，没有广告 SDK。卸载即删除全部数据。

说明
WGate 是独立客户端，与 WireGuard 官方无隶属关系。"WireGuard" 是 Jason A. Donenfeld 的注册商标，本项目只在描述协议兼容性时使用。
```

### 4.3 关键词

```
WireGuard, VPN, 隧道, 加密, 网络工具, AmneziaWG, 内网, 隐私
```

### 4.4 隐私政策 URL ✅ 已上线

**发布地址**：<https://simon2137.github.io/WGate/privacy.html>（AGC 表单"隐私政策 URL"填这个）

抓取复核：HTTP 200；正文含"与上游开源项目 **WG Tunnel**（作者 Zane Schepke）同样没有任何隶属、赞助或背书关系"；全文不再出现"分应用代理"。审核员点开看到的就是这两句。

- GitHub Pages 配置为 `main` 分支 `/docs` 目录（`docs/.nojekyll` 关闭 Jekyll 处理，保证 HTML 原样输出）；推送后约 1 分钟生效，`gh api repos/simon2137/WGate/pages/builds/latest` 可看构建状态；
- 同一份政策存在两处：`docs/PRIVACY.md`（仓库）与 `docs/privacy.html`（上架用），手写两份、必须同步。`check_keepalive.py` 第 19 节盯着这两份：都不许出现"分应用"，都必须含"WG Tunnel"免责声明；
- 如果哪天仓库改名/转移，这个 URL 会失效——AGC 审核前务必在浏览器里打开确认 200。

### 4.5 权限使用说明

AGC 会列出包内申请的权限，逐个填用途（必须中文）：

| 权限 | 填写内容 |
|---|---|
| `ohos.permission.INTERNET` | 建立加密隧道、与用户自己配置的服务器通信 |
| `ohos.permission.GET_NETWORK_INFO` | 识别当前网络类型（Wi-Fi/移动数据/以太网），用于自动隧道与重连 |
| `ohos.permission.GET_WIFI_INFO` | 读取当前 Wi-Fi 名称，用于匹配用户设置的 Wi-Fi 规则 |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | 应用切到后台时保持隧道连接与通知栏流量显示 |
| `ohos.permission.CAMERA` | 仅在用户选择"扫描二维码"导入配置时使用，用于识别 WireGuard 配置二维码 |
| `ohos.permission.PRIVACY_WINDOW` | 在展示配置二维码/私钥时阻止系统截屏，防止私钥被截走 |

> `PRIVACY_WINDOW` 在 SDK 里是 `normal` 级系统授权权限，不需要额外申请，但 AGC 会要求解释用途——上面那条就是。

### 4.6 其他

- **备案号**：填工信部下发的 App 备案号（此项国内分发必填）。个人主体也能备案，流程见下。
- **软著**：按类目要求上传；没有就先不传，看审核是否退回。
- **版权信息**：GPL-3.0，源码地址填项目仓库。

### 4.7 APP 备案怎么走（个人主体，以华为云为例）

当前状态：**没有备案号**，这是国内上架唯一的硬阻塞。要点是先有"接入服务商"，才能提交 APP 备案：

1. 华为云完成个人实名认证（身份证）；
2. 买一台**包年包月**的轻量应用服务器或 ECS，剩余有效期需 ≥3 个月（备案硬性要求，约 ¥100/年档即可），备案期间不能退订；
3. 进入华为云「备案」控制台 → 新增备案 → 选 **APP 备案**（不是网站备案）；
4. 按向导填：主体信息（姓名/身份证/手机/邮箱）、APP 信息（名称 WGate、包名 `com.wgate.app`、图标、功能描述、隐私政策 URL）、接入信息（选刚买的那台服务器）；
5. 华为云初审（1–2 个工作日）→ 工信部短信核验（要当场点确认）→ 管局审核（通常 5–20 个工作日）；
6. 通过后拿到形如「XICP备XXXXXXXX号-2A」的备案号，填回 AGC 的备案信息栏。国内规范还要求 **APP 内展示备案号**，上架前在"设置 → 关于"里加一行。

> 备案是必要条件，不是充分条件：VPN 类目本身的资质审核是另一道门（见第 0 节）。

**备案要填的 APP 特征信息（本项目的值，直接用）**

| 字段 | 值 |
|---|---|
| APP 名称 | WGate |
| 包名 | `com.wgate.app` |
| 公钥（Base64，SPKI） | `BFonZBpw0jsN/xxNsthh5fn6VgSGuUviJZza7BlL8AtSNkFr7agh1psBZRSvecyl4jPLPcld1VV4e4rzfGSTt0guTdUwq7wdpaRzAcHM+AwNJIBwjJv8A3nOpDh8dcbwkQ==` |
| 证书 MD5 | `7d0c4b46b7c1c0d23c6e4316e5c996a3` |
| 证书 SHA256 | `C7:25:8D:B8:6B:72:2D:6F:DC:F0:08:93:EA:78:2A:15:32:DA:2B:16:5D:62:FA:37:C9:E3:1B:82:0A:83:89:43` |
| 隐私政策 | <https://simon2137.github.io/WGate/privacy.html> |
| 图标 | `signing/agc-assets/icon-216-fullbleed.png` |
| 服务内容（如实、中性） | 网络连接工具：连接用户自行配置的私有网络服务器 |

> 备案期间**冻结**包名、应用名称、签名证书：任何一项变了，备案信息与安装包对不上会被驳回重来。

- **发布地区**：先只勾中国大陆（如果要加海外，海外不需要备案，但需要另填各国的合规信息）。

---

## 5. 提交审核

1. 版本信息页 → 上传 `.app` → 填完 4.1~4.6 → 提交审核。
2. 审核时长：首次一般 1–3 个工作日，资质类问题会更久。
3. 审核状态在「我的应用 → 状态」看；被拒会给出具体条款编号，照着改就行。

### 最常被拒的 6 个原因（都已经提前处理）

| 拒审点 | 处理 |
|---|---|
| 应用内含"翻墙/代理"表述 | 介绍里只写"访问自有内网"，删掉任何"科学上网/解锁"字样 |
| 权限用途说明缺失或与功能不符 | 见 4.5，六个权限都有对应功能 |
| 隐私政策打不开 / 内容与申请权限不一致 | 见 4.4：地址已上线、权限清单与实际一致 |
| 使用他人商标（WireGuard） | 描述里加了注册商标归属声明，图标/应用名不使用 WireGuard 标识 |
| **与上游应用的关系说不清**（移植类应用常见追问："你是 WG Tunnel 作者吗？"） | 隐私政策页脚写明：与 WG Tunnel 及其作者无隶属、赞助、背书关系，只在其 MIT 许可下复用界面与交互设计，并保留原始版权声明；许可证页也印了上游版权与 GPL/MIT 全文 |
| 截图与真实界面不符 | 15 张都是当前版本在模拟器上的真实截图（手机 Mate 90 Pro / 平板 MatePad Pro 13 / 电脑 MateBook Pro 窗口） |

---

## 6. 后续版本

1. `AppScope/app.json5` 里 `versionCode` +1、`versionName` 改成新版本号（两者都要改，versionCode 必须递增）。
2. 重新出包，**两条都要跑**：`assembleApp` 只会产出未签名的 App Pack，签名是 `signing\sign-package.ps1` 干的活（见 3.2）。只跑第一条传上去会被 AGC 拒。
3. 按 3.2.1 核一次内容，再上传新的 `.app`。
4. 证书和 Profile 不用换（除非证书过期或包名变更）。

> AGC 不接受同一个 `versionCode` 传两次。当前包是 `versionCode 1000000` / `versionName 1.0.0`——如果 1.0.0 已经提审过，改版本号再重打，否则上传时会直接报版本重复。

---

## 附：命令速查

```powershell
# 出包（两步都要）
$env:DEVECO_SDK_HOME = "C:\Program Files\Huawei\DevEco Studio\sdk"
& "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" assembleApp -p product=default -p buildMode=release --no-daemon
powershell -ExecutionPolicy Bypass -File signing\sign-package.ps1

# 工程自检（138 项）
python tools\check_keepalive.py

# 验证签名是否生效（在工程侧，不用设备）
$tmp = "$env:TEMP\wgapp"; Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path dist\WGate-1.0.0-signed.app), $tmp)
& "C:\Program Files\Huawei\DevEco Studio\jbr\bin\java.exe" -jar "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar" `
  verify-app -inFile "$tmp\entry-default.hap" -outProfile "$tmp\p.p7b"

# 装到设备上的包是另一份（debug 签名，用 hdc install），别拿去提审
hdc install -r entry\build\default\outputs\default\entry-default-unsigned.hap
```
