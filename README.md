# InstaBox Multi-Account & Multi-Machine Auto Watchdog (多账号与多机器保活)

用于自动化监听与保活 InstaBox 机器（Free Tier）的 GitHub Actions 守护工作流。现已全面支持**多账号（多 API Key）**与**多机器**混合调度。

---

## 🚀 核心特性

1. **多账号支持（多 API Key）**：
   - 支持同时管理多个 InstaBox 账号（或多个 Org）；
   - 在 GitHub Secret 中填入多个 Key（换行或逗号分隔），脚本会自动轮询每个账号，自动识别账号归属人，并分别保活名下的所有机器。
2. **多机器全自动发现（零配置）**：
   - 每个账号下的所有机器均自动通过 API 发现，无需手动配置机器 ID。
   - 以后在任意账号下新建机器，定时任务自动纳管，零运维。
3. **单次运行极度省额度（完美适配私人仓库）**：
   - 无论你有几个账号、几台机器，脚本均在**同一个 GitHub Actions 任务中顺序执行**，全过程仅需 5~10 秒；
   - 避免了 Matrix 并发产生的额外额度消耗，每月消耗固定约为 1,720 分钟，**彻底保障私人仓库在 2,000 分钟免费额度内**。
4. **多机器独立状态感知与复活**：
   - 逐台检测状态，若遇到 8 小时上限挂起，自动感知各自的平台冷却期（`cooldownUntil`）并在到期后精准唤醒；某台机器冷却中不会阻断其他账号与机器的检测。
5. **智能公网端口探测（防 30 分钟空闲休眠）**：
   - 自动扫描并探测机器已开放的所有公网 Web 端口；未暴露端口的机器则自动调用平台接口记录活跃度。
6. **密钥安全脱敏输出**：
   - 日志中所有 API Key 均已做脱敏处理（如 `ibk_tjyy...2e2q`），安全无忧。

---

## ⚙️ 快速配置

### 如何配置多个 API Key？
打开你的 GitHub 仓库：[Settings -> Secrets and variables -> Actions](https://github.com/hcr707305003/instabox_wake/settings/secrets/actions)

编辑现有的 `INSTABOX_API_KEY`（或新建 `INSTABOX_API_KEYS`），把多个 Key 粘贴进去即可：

#### 格式 1：一行一个 Key（推荐）
```text
ibk_第一个账号的Key...
ibk_第二个账号的Key...
ibk_第三个账号的Key...
```

#### 格式 2：逗号分隔
```text
ibk_第一个账号的Key..., ibk_第二个账号的Key...
```

*如果你目前只有 1 个 Key，保持原样即可，完全兼容！*

---

## 🧪 手动测试

1. 打开仓库的 [Actions 页面](https://github.com/hcr707305003/instabox_wake/actions)；
2. 左侧点击 **InstaBox Auto Watchdog**；
3. 点击右侧 **Run workflow** 下拉框中的绿色按钮，即可查看多账号扫描输出。
