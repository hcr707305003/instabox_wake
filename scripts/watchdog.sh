#!/bin/bash
# ==============================================================================
# InstaBox Watchdog & Auto Wake Script
# ==============================================================================

set -euo pipefail

MACHINE_ID="${MACHINE_ID:-m_agqx76qe5b2o4aqknmyqzefj7i}"
API_KEY="${API_KEY:-}"
PUBLIC_URL="${PUBLIC_URL:-https://6185-agqx76qe5b2o4aqknmyqzefj7i.instabox.tech}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S UTC')] $1"
}

if [ -z "$API_KEY" ]; then
    log "❌ 错误: 未设置 API_KEY 环境变量！"
    log "请在 GitHub 仓库中配置 Secret: INSTABOX_API_KEY"
    log "路径: Settings -> Secrets and variables -> Actions -> New repository secret"
    exit 1
fi

log "=== 开始检测 InstaBox 机器状态 [ID: ${MACHINE_ID}] ==="

API_URL="https://api.instabox.sh/v1/machines/${MACHINE_ID}"
RESP=$(curl -s -m 15 -X GET "$API_URL" -H "Authorization: Bearer ${API_KEY}" || true)

if [ -z "$RESP" ]; then
    log "❌ 错误: 请求 InstaBox API 失败，网络超时或无响应"
    exit 1
fi

# 检查是否有 API 报错
ERR_CODE=$(echo "$RESP" | jq -r '.error.code // empty' 2>/dev/null || true)
if [ -n "$ERR_CODE" ]; then
    ERR_MSG=$(echo "$RESP" | jq -r '.error.message // empty' 2>/dev/null || true)
    log "❌ API 错误: [${ERR_CODE}] ${ERR_MSG}"
    exit 1
fi

STATE=$(echo "$RESP" | jq -r '.state // empty' 2>/dev/null || true)
COOLDOWN=$(echo "$RESP" | jq -r '.cooldownUntil // empty' 2>/dev/null || true)
RUN_STARTED=$(echo "$RESP" | jq -r '.runStartedAt // empty' 2>/dev/null || true)

log "当前机器状态: ${STATE}"

NOW_EPOCH=$(date +%s)

case "$STATE" in
    "running")
        if [ -n "$RUN_STARTED" ] && [ "$RUN_STARTED" != "null" ]; then
            START_EPOCH=$(date -d "$RUN_STARTED" +%s 2>/dev/null || echo 0)
            if [ "$START_EPOCH" -gt 0 ]; then
                EXPIRE_EPOCH=$((START_EPOCH + 480 * 60))
                REMAIN_MIN=$(((EXPIRE_EPOCH - NOW_EPOCH) / 60))
                log "✅ 机器正在健康运行 | 距 8 小时上限强制暂停还剩约 ${REMAIN_MIN} 分钟"
            fi
        else
            log "✅ 机器正在健康运行"
        fi

        if [ -n "$PUBLIC_URL" ]; then
            log "正在请求公网服务以刷新 30 分钟空闲活跃度: ${PUBLIC_URL}"
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "$PUBLIC_URL" || true)
            log "公网服务探测响应状态码: ${HTTP_CODE}"
        fi
        ;;

    "suspended")
        log "⚠️ 机器已被挂起 (suspended)"

        if [ -n "$COOLDOWN" ] && [ "$COOLDOWN" != "null" ]; then
            CD_EPOCH=$(date -d "$COOLDOWN" +%s 2>/dev/null || echo 0)
            if [ "$NOW_EPOCH" -lt "$CD_EPOCH" ]; then
                WAIT_SEC=$((CD_EPOCH - NOW_EPOCH))
                log "⏳ 处于平台冷却期，还需等待 ${WAIT_SEC} 秒..."
                if [ "$WAIT_SEC" -le 300 ]; then
                    log "等待 ${WAIT_SEC} 秒后直接执行唤醒..."
                    sleep "$WAIT_SEC"
                else
                    log "冷却时间较长，跳过本次执行，将在下一次定时触发时唤醒。"
                    exit 0
                fi
            fi
        fi

        log "🚀 发送 wake 唤醒请求..."
        WAKE_RESP=$(curl -s -m 30 -X POST "${API_URL}/wake" -H "Authorization: Bearer ${API_KEY}")
        WAKE_STATE=$(echo "$WAKE_RESP" | jq -r '.state // empty' 2>/dev/null || true)
        log "唤醒请求响应状态: ${WAKE_STATE:-未知 (详情见响应: $WAKE_RESP)}"
        ;;

    "resuming"|"starting")
        log "🔄 机器正处于恢复/启动中 (${STATE})..."
        ;;

    *)
        log "ℹ️ 机器状态: ${STATE}"
        ;;
esac

log "=== 检测完成 ==="
