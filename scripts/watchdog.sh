#!/bin/bash
# ==============================================================================
# InstaBox Multi-Account & Multi-Machine Watchdog & Auto Wake Script
# 支持多账号 (多 API Key)、多机器自动发现、端口探测与自动复活
# ==============================================================================

set -euo pipefail

RAW_KEYS="${API_KEYS:-${API_KEY:-}}"
TARGET_MACHINES="${TARGET_MACHINES:-${MACHINE_IDS:-}}"
API_BASE="https://api.instabox.sh/v1"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S UTC')] $1"
}

# 密钥脱敏显示（如 ibk_tjyy...2e2q）
mask_key() {
    local k="$1"
    local len=${#k}
    if [ "$len" -gt 12 ]; then
        echo "${k:0:8}...${k: -4}"
    else
        echo "***"
    fi
}

if [ -z "$RAW_KEYS" ]; then
    log "❌ 错误: 未设置 API_KEY 或 API_KEYS 环境变量！"
    log "请在 GitHub 仓库中配置 Secret: INSTABOX_API_KEY 或 INSTABOX_API_KEYS"
    log "（支持一行一个 Key，或用逗号隔开）"
    exit 1
fi

# 解析所有 Key（支持换行、逗号分隔，自动过滤注释与空行）
mapfile -t KEYS_LIST < <(echo "$RAW_KEYS" | tr ',' '\n' | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^#' | grep -v '^$')

TOTAL_KEYS=${#KEYS_LIST[@]}
if [ "$TOTAL_KEYS" -eq 0 ]; then
    log "❌ 错误: 解析到的有效 API Key 数量为 0！"
    exit 1
fi

log "=========================================================="
log "🔍 启动 InstaBox 多账号与多机器监控 (共检测到 ${TOTAL_KEYS} 个 API Key)"
log "=========================================================="

KEY_INDEX=0
GLOBAL_TOTAL_MACHINES=0
GLOBAL_RUNNING=0
GLOBAL_WAKED=0

NOW_EPOCH=$(date +%s)

for KEY in "${KEYS_LIST[@]}"; do
    KEY_INDEX=$((KEY_INDEX + 1))
    MASKED_KEY=$(mask_key "$KEY")

    # 1. 查询当前 Key 对应的账号信息
    ME_RESP=$(curl -s -m 10 -X GET "${API_BASE}/me" -H "Authorization: Bearer ${KEY}" || true)
    ACCOUNT_NAME=$(echo "$ME_RESP" | jq -r '.email // .login // "未知账号"' 2>/dev/null || echo "未知账号")

    log "----------------------------------------------------------"
    log "🔑 [账号 ${KEY_INDEX}/${TOTAL_KEYS}] 用户: ${ACCOUNT_NAME} (Key: ${MASKED_KEY})"
    log "----------------------------------------------------------"

    # 2. 查询该账号下的全部机器
    MACHINES_RESP=$(curl -s -m 15 -X GET "${API_BASE}/machines" -H "Authorization: Bearer ${KEY}" || true)

    if [ -z "$MACHINES_RESP" ]; then
        log "   ❌ 错误: 请求 InstaBox API 失败，网络超时或无响应"
        continue
    fi

    ERR_CODE=$(echo "$MACHINES_RESP" | jq -r '.error.code // empty' 2>/dev/null || true)
    if [ -n "$ERR_CODE" ]; then
        ERR_MSG=$(echo "$MACHINES_RESP" | jq -r '.error.message // empty' 2>/dev/null || true)
        log "   ❌ API 报错: [${ERR_CODE}] ${ERR_MSG}"
        continue
    fi

    TOTAL_MACHINES=$(echo "$MACHINES_RESP" | jq -r '.machines | length' 2>/dev/null || echo 0)
    log "   ℹ️ 该账号下共找到 ${TOTAL_MACHINES} 台机器"

    if [ "$TOTAL_MACHINES" -eq 0 ]; then
        continue
    fi

    GLOBAL_TOTAL_MACHINES=$((GLOBAL_TOTAL_MACHINES + TOTAL_MACHINES))

    # 3. 遍历并检测当前账号的每一台机器
    echo "$MACHINES_RESP" | jq -c '.machines[]' | while read -r machine_json; do
        M_ID=$(echo "$machine_json" | jq -r '.id')
        M_NAME=$(echo "$machine_json" | jq -r '.name // "unnamed"')
        STATE=$(echo "$machine_json" | jq -r '.state // "unknown"')
        COOLDOWN=$(echo "$machine_json" | jq -r '.cooldownUntil // empty')
        RUN_STARTED=$(echo "$machine_json" | jq -r '.runStartedAt // empty')

        # 白名单过滤（如果配置了 TARGET_MACHINES）
        if [ -n "$TARGET_MACHINES" ]; then
            MATCHED=false
            IFS=',' read -ra ADDR <<< "$TARGET_MACHINES"
            for target in "${ADDR[@]}"; do
                target_clean=$(echo "$target" | xargs)
                if [ "$target_clean" = "$M_ID" ] || [ "$target_clean" = "$M_NAME" ]; then
                    MATCHED=true
                    break
                fi
            done
            if [ "$MATCHED" = false ]; then
                log "   ⏭️ 跳过未在白名单中的机器: [${M_NAME}] (${M_ID})"
                continue
            fi
        fi

        log "   🖥️ 机器: [${M_NAME}] (ID: ${M_ID}) | 状态: ${STATE}"

        case "$STATE" in
            "running")
                GLOBAL_RUNNING=$((GLOBAL_RUNNING + 1))
                if [ -n "$RUN_STARTED" ] && [ "$RUN_STARTED" != "null" ]; then
                    START_EPOCH=$(date -d "$RUN_STARTED" +%s 2>/dev/null || echo 0)
                    if [ "$START_EPOCH" -gt 0 ]; then
                        EXPIRE_EPOCH=$((START_EPOCH + 480 * 60))
                        REMAIN_MIN=$(((EXPIRE_EPOCH - NOW_EPOCH) / 60))
                        log "      ✅ 运行健康 | 距 8 小时上限还剩约 ${REMAIN_MIN} 分钟"
                    fi
                else
                    log "      ✅ 运行健康"
                fi

                # 获取公开端口并探测（超时放宽至 10 秒，并支持自动跟随 301/302 重定向）
                PORTS_RESP=$(curl -s -m 10 -X GET "${API_BASE}/machines/${M_ID}/ports" -H "Authorization: Bearer ${KEY}" || true)
                PUBLIC_URLS=$(echo "$PORTS_RESP" | jq -r '.ports[]? | select(.access == "public") | .url' 2>/dev/null || true)

                if [ -n "$PUBLIC_URLS" ]; then
                    while read -r url; do
                        if [ -n "$url" ]; then
                            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 -L "$url" || true)
                            log "      🌐 探测公网服务 [${url}]: HTTP ${HTTP_CODE}"
                        fi
                    done <<< "$PUBLIC_URLS"
                else
                    log "      🔄 无公网端口，调用 wake 接口刷新活跃度..."
                    curl -s -m 15 -X POST "${API_BASE}/machines/${M_ID}/wake" -H "Authorization: Bearer ${KEY}" >/dev/null 2>&1 || true
                fi
                ;;

            "suspended")
                # 检查冷却期
                NEED_WAIT=false
                WAIT_SEC=0
                if [ -n "$COOLDOWN" ] && [ "$COOLDOWN" != "null" ]; then
                    CD_EPOCH=$(date -d "$COOLDOWN" +%s 2>/dev/null || echo 0)
                    if [ "$NOW_EPOCH" -lt "$CD_EPOCH" ]; then
                        NEED_WAIT=true
                        WAIT_SEC=$((CD_EPOCH - NOW_EPOCH))
                    fi
                fi

                if [ "$NEED_WAIT" = true ]; then
                    if [ "$WAIT_SEC" -le 300 ]; then
                        log "      ⏳ 处于平台冷却保护中，等待 ${WAIT_SEC} 秒后自动唤醒..."
                        sleep "$WAIT_SEC"
                    else
                        log "      ⏳ 处于平台冷却保护中，还剩 ${WAIT_SEC} 秒，将在下个周期唤醒"
                        continue
                    fi
                fi

                log "      🚀 发起 wake 请求复活机器..."
                WAKE_RESP=$(curl -s -m 30 -X POST "${API_BASE}/machines/${M_ID}/wake" -H "Authorization: Bearer ${KEY}" || true)
                WAKE_STATE=$(echo "$WAKE_RESP" | jq -r '.state // empty' 2>/dev/null || true)

                if [ "$WAKE_STATE" = "running" ] || [ "$WAKE_STATE" = "resuming" ]; then
                    log "      🎉 唤醒成功！当前状态已更新为: ${WAKE_STATE}"
                    GLOBAL_WAKED=$((GLOBAL_WAKED + 1))
                else
                    log "      ❌ 唤醒响应异常: $WAKE_RESP"
                fi
                ;;

            "resuming"|"starting")
                log "      🔄 机器处于启动/恢复过渡中"
                ;;

            *)
                log "      ℹ️ 机器状态: ${STATE}"
                ;;
        esac
    done
done

log "=========================================================="
log "🏁 扫描汇总：共处理 ${TOTAL_KEYS} 个账号，累计扫描 ${GLOBAL_TOTAL_MACHINES} 台机器"
log "=========================================================="
