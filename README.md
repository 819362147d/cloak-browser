# CloakBrowser — 检测伪装浏览器（IPA 工程骨架，未编译验证）

一个只有 WKWebView 的极简浏览器，在每个页面脚本运行之前注入 `spoof.js`，
把 ip.cx「Claude 检测」命中的 JS 层信号改成英国画像（用户 2026-11-08 指定 UK 版）。

## 画像
无痕：WebView 用非持久化数据存储（nonPersistent），Cookie / localStorage /
缓存 / 历史只在内存里，App 进程结束即清，本地不落盘。代价：网站登录态
不跨重启保存，每次打开要重新登录。
- 时区 `Europe/London`（含夏令时：冬 GMT 偏移 0 / 夏 BST 偏移 -60，已本地验算）
- 语言 / Intl locale `en-GB`，`navigator.languages = [en-GB, en]`

## 能压掉的（针对截图那 61 分）
| 信号 | 分 | 手段 |
|---|---|---|
| 系统时区 Asia/Shanghai | 24 | 覆写 `Intl.DateTimeFormat.resolvedOptions` + 构造器强制 `timeZone` |
| 浏览器语言 zh-CN | 18 | `navigator.language/languages` getter |
| 已装中文字体 | 12 | 劫持 canvas `measureText`：命中屏蔽名单（PingFang SC/TC/HK、微软雅黑/正黑、思源、MiSans、鸿蒙等）时按通用字体量宽；`document.fonts.check` 对名单字体返回 false |
| Intl 区域 zh-CN | 4 | 同 Intl 覆写 |
| 时区偏移 UTC+8 | 2 | 覆写 `getTimezoneOffset`，按巴黎真实偏移（含夏令时）算 |
| WebRTC 泄露 | 0→0 | 截图里本来就是 0（Safari 不漏），脚本里顺手禁掉 `RTCPeerConnection` 防其他页面 |
| Emoji Apple 风格 | 1 | 压不掉——真美国 iPhone 也是 Apple 风格，这 1 分检测方自己也标注是弱信号 |

真机进度（2026-11-08）：时区 Europe/London +0、语言 en-GB +0、WebRTC +0
已实测通过；字体 v1.0 仍被检出 +12，原因是旧 stripBlocked 把
'72px "PingFang SC"' 拼成了无效的 '72monospace'、canvas 默默忽略赋值。
v1.2 已改为命中屏蔽字体时按同字号通用字体（优先用原串自带的通用回退）
量宽，本地模拟通过，待真机复测。

理论目标：61 → 1（只剩 Emoji）。**以 Codemagic 构建后在真机复测为准，没测之前不算数。**

## 帧率（v1.3）
App 侧能公开申请的都拉满了：Info.plist 加
`CADisableMinimumFrameDurationOnPhone = true`（解除系统对本 App 的
最低帧时长压制），WebView 滚动视图按 min=max=preferred=屏幕上限
（ProMotion 机型 120）申请帧率区间。
边界：网页内容本身的合成帧率由 WebKit 进程和页面代码决定，App 锁不住；
系统级「把整机推向 120」是 GlobalRefresh 那个包的悬浮窗方案的活，
两个包同时开（GR 后台悬浮窗 + 本浏览器前台）效果等价且不用互相移植。

## 界面（v1.1 补上）
顶部地址/搜索两用栏：输完整网址直接打开，输域名自动补 https://，
输关键词走 DuckDuckGo 搜索（改 `ContentView.swift` 里 `makeURL`
的模板可换 Google）。底部工具栏：后退 / 前进 / 刷新（加载中变停止）/
主页（DuckDuckGo）/ 检测页（ip.cx，一键复测）。
v1.0 只有固定打开 ip.cx 一页、没有这些，是已知的偷工，已修。

## 硬边界（做之前必须知道）
1. **只管这个 App 内部的网页。** iOS 沙盒决定了：任何 IPA 都改不了 Safari、
   改不了 Claude App、改不了系统里其他 App 看到的时区/语言。想让 Claude App
   也吃到伪装，非越狱做不到。
2. **字体只能骗过 canvas 量字宽这一路。** 截图里的检测写的就是 canvas 法，
   所以对它有效；但用 DOM 排版量宽（真实文本节点 offsetWidth）的检测骗不过，
   强行劫持排版会把页面搞坏，不做。
3. **`Date.toString()` 里的时区名、JS 函数被改过的痕迹**（toString 不是
   `[native code]`）高级检测能看出来。这个页面的检测不查，但别指望它能骗过
   专门的反指纹系统。
4. **压低这个第三方页面的分数 ≠ Claude 官方风控就低。** Anthropic 服务端还看
   IP/ASN、账号历史、付款、手机号等，JS 信号只是其中一小块。别拿 1 分当免封金牌。
5. ⚠️ 一致性提醒：出口 IP 仍是法国 VPS（194.60.95.38），与英国画像对不上。
   ip.cx 只查中国信号，所以分数照样能压下去；但查 IP 与时区一致性的
   风控会看到「法国 IP + 伦敦时区」。要真一致，得配英国出口节点使用。
   换画像只改 `spoof.js` 顶部 `TZ/LANG/LANGS` 三行。

## 零成本替代（不用装 IPA，全系统生效）
设置 → 通用 → 语言与地区：语言 English (UK)、地区改英国；
设置 → 通用 → 日期与时间：关「自动设置」时区选 London。
效果 61 → 约 13（只剩字体 12 + Emoji 1），且对所有 App 生效，
代价是全手机的语言/时间跟着变。IPA 方案的价值就是不用动系统。

## 构建
同 glod 的路子：本目录推到 GitHub 仓库后用根目录 `codemagic.yaml`
出未签名 IPA，自签安装。本地无 Xcode，**未做编译验证**，
Codemagic 构建日志是第一道验证，构建过了还要真机打开 ip.cx 复测分数。
