# InstaBox Auto Watchdog (自动监听与复活)

用于自动化监听与保活 InstaBox 机器（Free Tier）的 GitHub Actions 守护工作流。

## 🎯 功能特性
- **防 30 分钟空闲休眠**：每 25 分钟通过公共端口探测一次 Web 服务，重置空闲休眠计时器。
- **8 小时上限自动复活**：当机器因 8 小时强制上限挂起（`state: suspended`）后，自动感知平台冷却期并在冷却结束后调用 `/wake` 接口复活机器。
- **适配私人仓库（Private）额度**：调度间隔设为 25 分钟一次，每月仅消耗约 1,720 分钟，完全在 GitHub 免费提供的 2,000 分钟配额内。

---

## ⚙️ 快速配置

为了保证 API Key 安全，请在 GitHub 仓库中配置 Secret：

1. 打开当前 GitHub 仓库页面；
2. 点击 **Settings** -> **Secrets and variables** -> **Actions**；
3. 点击 **New repository secret**，添加如下密钥：
   - **Name**: `INSTABOX_API_KEY`
   - **Secret**: 你的 InstaBox API 密钥（格式为 `ibk_...`）
4. （可选）如果你更换了机器，可在同页面添加：
   - `INSTABOX_MACHINE_ID`: 机器 ID（默认内置）
   - `INSTABOX_PUBLIC_URL`: 机器公网 URL（默认内置）

---

## 🚀 手动测试

1. 打开仓库的 **Actions** 标签页；
2. 在左侧选择 **InstaBox Auto Watchdog**；
3. 点击右侧 **Run workflow** 下拉框，点击绿色 **Run workflow** 按钮即可立即手动触发一次执行。
