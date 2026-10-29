# InstaBox Multi-Machine Auto Watchdog (多机器自动监听与复活)

用于自动化监听与保活 InstaBox 机器（Free Tier）的 GitHub Actions 守护工作流。已原生升级为**多机器架构**。

---

## 🚀 核心特性

1. **自动发现全量机器（零配置）**：
   - 默认无需手动指定机器 ID！脚本通过 InstaBox 平台 API 自动拉取当前账号下的**所有机器**。
   - 以后在 InstaBox 创建新机器后，无需修改任何代码或配置，定时任务会自动扫描并纳管新机器。
2. **多机器独立状态感知与复活**：
   - 逐台检测每台机器的运行状态（`running` / `suspended` 等）。
   - 若某台机器因 8 小时强制上限挂起，自动感知其专属的平台冷却期（`cooldownUntil`），冷却结束后自动执行 `/wake` 唤醒。某台机器冷却中不会阻塞其他机器的处理。
3. **智能公网端口探测（防 30 分钟空闲休眠）**：
   - 自动获取每台机器已开放的所有公网 Web 端口并自动发起探测；若机器未暴露公开端口，则自动调用平台活跃度借口保持在线。
4. **支持白名单模式（可选过滤）**：
   - 如果账号下某些机器不想保活，可在 GitHub Actions 触发时或通过环境变量指定只保活特定机器。
5. **适配私人仓库（Private）免费额度**：
   - 调度周期设为 25 分钟一次，每月仅消耗约 1,720 分钟，完全在 GitHub 免费提供的 2,000 分钟配额内。

---

## ⚙️ 快速配置

### 1. 配置 API 密钥（必需）
1. 打开当前 GitHub 仓库页面；
2. 点击 **Settings** -> **Secrets and variables** -> **Actions**；
3. 点击 **New repository secret**，添加如下密钥：
   - **Name**: `INSTABOX_API_KEY`
   - **Secret**: 你的 InstaBox API 密钥（格式为 `ibk_...`）

### 2. （可选）指定只保活部分机器
如果不希望全部机器都自动保活，可以在 **Settings** -> **Secrets and variables** -> **Actions** -> **Variables** 标签下添加：
- **Name**: `TARGET_MACHINES`
- **Value**: 机器 ID 或机器名称（多个以逗号隔开，例如 `shiroi, m_xxx2`）

*若不配置此项，默认自动保活账号下的全部机器。*

---

## 🧪 手动测试

1. 打开仓库的 [Actions 页面](https://github.com/hcr707305003/instabox_wake/actions)；
2. 在左侧选择 **InstaBox Auto Watchdog**；
3. 点击右侧 **Run workflow** 下拉框：
   - 你可以直接点击绿色按钮测试**扫描全量机器**；
   - 也可以在输入框输入特定的机器名/ID 进行定向测试。
