#!/bin/bash
# ==============================================================================
# InstaBox Multi-Machine Watchdog & Auto Wake Script
# 支持多机器自动发现、独立监听、冷却感知与自动复活
# ==============================================================================

set -euo pipefail

API_KEY="${API_KEY:-}"
# 可选：指定要监听的机器 ID 或名称列表（逗号或空格分隔）。留空则自动监听账号下的全部机器
TARGET_MACHINES="${TARGET_MACHINES:-${MACHINE_IDS:-}}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S UTC')] $1"
}

if [ -z "$API_KEY" ]; then
    log "❌ 错误: 未设置 API_KEY 环境变量！"
    log "请在 GitHub 仓库中配置 Secret: INSTABOX_API_KEY"
    exit 1
fi

log "=========================================================="
log "🔍 开始 InstaBox 多机器状态检测与保活任务"
log "=========================================================="

API_BASE="https://api.instabox.sh/v1"

# 1. 获取账号下全部机器
MACHINES_RESP=$(curl -s -m 15 -X GET "${API_BASE}/machines" -H "Authorization: Bearer ${API_KEY}" || true)

if [ -z "$MACHINES_RESP" ]; then
    log "❌ 错误: 请求 InstaBox API 失败，网络超时或无响应"
    exit 1
fi

ERR_CODE=$(echo "$MACHINES_RESP" | jq -r '.error.code // empty' 2>/dev/null || true)
if [ -n "$ERR_CODE" ]; then
    ERR_MSG=$(echo "$MACHINES_RESP" | jq -r '.error.message // empty' 2>/dev/null || true)
    log "❌ API 错误: [${ERR_CODE}] ${ERR_MSG}"
    exit 1
fi

TOTAL_FOUND=$(echo "$MACHINES_RESP" | jq -r '.machines | length' 2>/dev/null || echo 0)
if [ "$TOTAL_FOUND" -eq 0 ]; then
    log "⚠️ 未查询到任何机器。"
    exit 0
fi

log "ℹ️ 账号下共发现 ${TOTAL_FOUND} 台机器"

# 统计计数
COUNT_RUNNING=0
COUNT_WAKED=0
COUNT_COOLDOWN=0
COUNT_OTHER=0

NOW_EPOCH=$(date +%s)

# 2. 遍历并检测每一台机器
echo "$MACHINES_RESP" | jq -c '.machines[]' | while read -r machine_json; do
    M_ID=$(echo "$machine_json" | jq -r '.id')
    M_NAME=$(echo "$machine_json" | jq -r '.name // "unnamed"')
    STATE=$(echo "$machine_json" | jq -r '.state // "unknown"')
    COOLDOWN=$(echo "$machine_json" | jq -r '.cooldownUntil // empty')
    RUN_STARTED=$(echo "$machine_json" | jq -r '.runStartedAt // empty')

    # 如果用户指定了白名单过滤
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
            log "⏭️ 跳过未在白名单中的机器: [${M_NAME}] (${M_ID})"
            continue
        fi
    fi

    log "----------------------------------------------------------"
    log "🖥️ 机器: [${M_NAME}] (ID: ${M_ID}) | 当前状态: ${STATE}"

    case "$STATE" in
        "running")
            COUNT_RUNNING=$((COUNT_RUNNING + 1))
            if [ -n "$RUN_STARTED" ] && [ "$RUN_STARTED" != "null" ]; then
                START_EPOCH=$(date -d "$RUN_STARTED" +%s 2>/dev/null || echo 0)
                if [ "$START_EPOCH" -gt 0 ]; then
                    EXPIRE_EPOCH=$((START_EPOCH + 480 * 60))
                    REMAIN_MIN=$(((EXPIRE_EPOCH - NOW_EPOCH) / 60))
                    log "   ✅ 运行健康 | 距 8 小时上限还剩约 ${REMAIN_MIN} 分钟"
                fi
            else
                log "   ✅ 运行健康"
            fi

            # 获取机器开放的公开端口并进行探测保活
            PORTS_RESP=$(curl -s -m 10 -X GET "${API_BASE}/machines/${M_ID}/ports" -H "Authorization: Bearer ${API_KEY}" || true)
            PUBLIC_URLS=$(echo "$PORTS_RESP" | jq -r '.ports[]? | select(.access == "public") | .url' 2>/dev/null || true)

            if [ -n "$PUBLIC_URLS" ]; then
                while read -r url; do
                    if [ -n "$url" ]; then
                        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "$url" || true)
                        log "   🌐 探测公网服务 [${url}]: HTTP ${HTTP_CODE}"
                    fi
                done <<< "$PUBLIC_URLS"
            else
                # 若未配置公开端口，直接向机器发送一次轻量 wake 请求记录活跃度
                log "   🔄 无公网端口，调用 wake 接口刷新平台活跃度..."
                curl -s -m 15 -X POST "${API_BASE}/machines/${M_ID}/wake" -H "Authorization: Bearer ${API_KEY}" >/dev/null 2>&1 || true
            fi
            ;;

        "suspended")
            # 判断是否在冷却期
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
                    log "   ⏳ 处于平台冷却保护中，等待 ${WAIT_SEC} 秒后自动唤醒..."
                    sleep "$WAIT_SEC"
                else
                    log "   ⏳ 处于平台冷却保护中，距离冷却结束还剩 ${WAIT_SEC} 秒，将在下个周期唤醒"
                    COUNT_COOLDOWN=$((COUNT_COOLDOWN + 1))
                    continue
                fi
            fi

            log "   🚀 发起 wake 请求复活机器..."
            WAKE_RESP=$(curl -s -m 30 -X POST "${API_BASE}/machines/${M_ID}/wake" -H "Authorization: Bearer ${API_KEY}" || true)
            WAKE_STATE=$(echo "$WAKE_RESP" | jq -r '.state // empty' 2>/dev/null || true)

            if [ "$WAKE_STATE" = "running" ] || [ "$WAKE_STATE" = "resuming" ]; then
                log "   🎉 唤醒成功！当前状态已更新为: ${WAKE_STATE}"
                COUNT_WAKED=$((COUNT_WAKED + 1))
            else
                log "   ❌ 唤醒响应异常: $WAKE_RESP"
                COUNT_OTHER=$((COUNT_OTHER + 1))
            fi
            ;;

        "resuming"|"starting")
            log "   🔄 机器处于启动/恢复过渡状态"
            COUNT_OTHER=$((COUNT_OTHER + 1))
            ;;

        *)
            log "   ℹ️ 机器处于状态: ${STATE}"
            COUNT_OTHER=$((COUNT_OTHER + 1))
            ;;
    esac
done

log "=========================================================="
log "🏁 本次多机器检测与保活全部完成！"
log "=========================================================="
