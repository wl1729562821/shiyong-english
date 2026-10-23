# 实用英语 iOS 版：编译和安装

iOS 版和 Android / Windows 版是同一套代码（Flutter），编译出来是原生 iPhone App：
代码编译成 ARM 机器码，朗读用 iPhone 自带的语音引擎（AVSpeechSynthesizer，不用联网），
图标、名字（实用英语）都已经配好。

**限制：苹果只允许在 Mac 上编译、签名 iOS App，Windows 电脑做不了这一步。**
所以要么借用“云端 Mac”编译（方案 A），要么用一台真的 Mac（方案 B）。
无论哪种，装到 iPhone 上都要用 Apple ID 签名：

| 签名用的账号 | 费用 | App 有效期 |
|---|---|---|
| 普通 Apple ID（免费） | 0 | 7 天，到期重新装一次，学习记录不丢 |
| Apple 开发者账号 | 99 美元 / 年 | 1 年；还能用 TestFlight 安装 |

---

## 方案 A：没有 Mac —— GitHub 云端编译 + Windows 上安装（推荐）

### 1. 把项目放到 GitHub

项目已经是 git 仓库（`main` 分支），代码都已提交；`.gitignore` 排除了 `build/`、`release/`，
不会把几十 MB 的安装包传上去。这台电脑上的仓库还设置了“连 GitHub 不走 7890 代理”。

1. （只做一次）删掉 git 全局配置里失效的 GitHub 镜像改写，否则推送会被转到已经关闭的 hub.fastgit.org：

   ```bash
   git config --global --unset url.https://hub.fastgit.org/.insteadof
   ```

2. 登录 https://github.com → 右上角 **+** → **New repository**：名字填 `shiyong-english`，
   选 **Private**，**不要**勾选 README / .gitignore / license，点 Create
3. 在项目目录（`E:\androidFluttetProject\travel_english`）打开终端，把下面的“你的用户名”换成 GitHub 用户名：

   ```bash
   git remote add origin https://github.com/你的用户名/shiyong-english.git
   ```

   ```bash
   git push -u origin main
   ```

   第一次推送会弹出浏览器让你登录 GitHub 并授权，登录完推送就会继续
4. 推送成功后会自动开始编译（推送到 main 分支就触发）

如果直连 GitHub 很慢或连不上：打开 Clash（7890 端口），再让这个仓库走代理：

```bash
git config --local --unset http.https://github.com/.proxy
```

### 2. 在云端 Mac 上编译

1. 打开仓库网页 → **Actions** → 左边选 **iOS build**，能看到正在运行的那一次（也可以点 **Run workflow** 手动再跑一次）
   （以后每次推送到 main 分支也会自动编译）
2. 等 15–20 分钟。会先跑一遍 44 个自动测试，再编译 iOS 版
3. 完成后打开这次运行的页面，最下面 **Artifacts** 里下载 `ShiYongYingYu-ios-unsigned`，
   解压得到 `ShiYongYingYu-unsigned.ipa`

私有仓库每月有免费的 Actions 时间，Mac 机器按 10 倍扣，大约够编译 10 次；
公开仓库不限。具体额度以 GitHub 当前规则为准。

### 3. 用 Sideloadly 装到 iPhone（在 Windows 上操作）

1. 安装苹果官网下载版的 **iTunes** 和 **iCloud**（不要用微软商店版），用来识别 iPhone
2. 安装 **Sideloadly**：https://sideloadly.io
3. iPhone 用数据线连电脑，手机上点“信任此电脑”
4. 把 `.ipa` 拖进 Sideloadly，填你的 Apple ID，点 **Start**，按提示输入密码
   （建议用一个专门的 Apple ID；密码只在 Sideloadly 里输入）
5. iPhone 上：
   - **设置 → 通用 → VPN 与设备管理** → 点你的 Apple ID → 信任
   - iOS 16 及以上：**设置 → 隐私与安全性 → 开发者模式** 打开，按提示重启
6. 桌面上出现「实用英语」，打开就能用

**7 天到期后**：App 打不开时，用 Sideloadly 把同一个 `.ipa` 再装一次即可，学习进度和标注都在。
Sideloadly 也可以开启自动续签（电脑和手机在同一个 Wi-Fi 下）。

---

## 方案 B：有 Mac

1. Mac 上安装 Xcode（App Store）和 Flutter 3.27：https://docs.flutter.dev/get-started/install/macos
2. 把项目拷到 Mac，在项目目录运行：

   ```bash
   flutter pub get
   ```

   ```bash
   open ios/Runner.xcworkspace
   ```

3. Xcode 里选 **Runner → Signing & Capabilities → Team**，登录并选你的 Apple ID
   （如果提示 Bundle Identifier 被占用，把 `com.travel.travelEnglish` 改成别的，比如加上你的名字）
4. iPhone 连到 Mac，Xcode 顶部选你的 iPhone，点 ▶ 运行；或者在终端：

   ```bash
   flutter run --release
   ```

5. 手机上同样要“信任开发者”和打开“开发者模式”（见方案 A 第 5 步）

---

## 装好以后

- **声音更自然**：iPhone 自带的英文声音是压缩版，比较生硬。打开
  **设置 → 辅助功能 → 朗读内容 → 声音 → 英语**，下载带「增强」或「高级」的声音（比如 Samantha、Daniel），
  回到 App 的「设置 → 发音人」就能选
- **静音开关不影响朗读**：App 把声音当作“播放媒体”，侧面静音键打开时也能听到
- 学习记录、生词本、标注都存在这台 iPhone 上，和 Windows / Android 版不互通

## 尚未在真机上验证的地方

iOS 的原生朗读代码（`ios/Runner/AppDelegate.swift`）是在 Windows 上写的，
还没在 Mac 上编译、也没在 iPhone 上跑过。第一次云端编译如果失败，把 Actions 页面里
报错的那一步的日志发给我；装上后如果朗读有问题（没声音、读一半停、连续播放卡住），也告诉我。
