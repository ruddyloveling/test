#!/usr/bin/env bash
set -Eeuo pipefail

# ========== 可调参数 ==========
COMPOSE_CMD="${COMPOSE_CMD:-docker-compose}"         # 如果用 docker-compose V1，可改为 "docker-compose"
COMPOSE_FILE="${COMPOSE_FILE:-/home/admin/gateway/docker-compose.yml}"   # 如有多文件，可用: COMPOSE_FILE="docker-compose.yml:docker-compose.prod.yml"
NEW_BIN="${NEW_BIN:-./gateway}"             # 新版本可执行文件路径
HEALTH_PATH="${HEALTH_PATH:-/v1/health}"                # 健康检查 HTTP 路径
HEALTH_HOST="${HEALTH_HOST:-127.0.0.1}"              # 健康检查访问主机
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-60}"               # 单节点健康检查超时时间(秒)
# =================================
cd /home/admin/gateway
# 节点清单：服务名:宿主机端口:挂载目录(放二进制的地方)
NODES=(
  "gateway1:18081:./gateway1"
  "gateway2:18082:./gateway2"
)

# ---- 工具函数 ----
log() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERR ]\033[0m $*" >&2; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || { err "缺少命令: $1"; exit 127; }; }

check_prereq() {
  need_cmd curl
  need_cmd ${COMPOSE_CMD%% *} # docker
  [[ -f "$COMPOSE_FILE" ]] || { err "找不到 compose 文件: $COMPOSE_FILE"; exit 2; }
  [[ -f "$NEW_BIN" ]] || { err "找不到新版本二进制: $NEW_BIN"; exit 2; }
  chmod +x "$NEW_BIN" || true
}

wait_healthy() {
  local url="$1"
  local timeout="$2"
  local start ts
  start=$(date +%s)
  until curl -fsS "$url" >/dev/null 2>&1; do
    ts=$(date +%s)
    if (( ts - start >= timeout )); then
      return 1
    fi
    sleep 2
  done
  return 0
}

update_one() {
  local service="$1" port="$2" dir="$3"
  local target="$dir/gateway"
  local backup_dir="$dir/backup"
  local backup="${target}.bak.$(date +%Y%m%d-%H%M%S)"
  local url="http://${HEALTH_HOST}:${port}${HEALTH_PATH}"

  log "开始更新 ${service} (端口 ${port}, 目录 ${dir})"

  # 确保备份目录存在
  mkdir -p "$backup_dir"

  # 1) 备份旧二进制 & 下发新二进制
  if [[ -f "$target" ]]; then
    cp -f "$target" "$backup_dir/$(basename $backup)"
    log "已备份旧二进制: $backup_dir/$(basename $backup)"
  else
    warn "未发现旧二进制 ${target}，跳过备份"
  fi

  cp -f "$NEW_BIN" "$target"
  chmod +x "$target"

  # 备份清理：只保留最近 10 个
  local files_to_delete
  files_to_delete=$(ls -1t "$backup_dir" | grep "^$(basename $target).bak" | tail -n +11)
  if [[ -n "$files_to_delete" ]]; then
    for f in $files_to_delete; do
      rm -f "$backup_dir/$f"
      log "删除旧备份: $backup_dir/$f"
    done
  fi

  # 2) 重启容器
  ${COMPOSE_CMD} -f "$COMPOSE_FILE" restart "$service"

  # 3) 健康检查
  log "等待 ${service} 健康就绪: $url (超时 ${HEALTH_TIMEOUT}s)"
  if ! wait_healthy "$url" "$HEALTH_TIMEOUT"; then
    err "${service} 健康检查失败，执行回滚"
    # 回滚
    local last_backup
    last_backup=$(ls -1t "$backup_dir" | grep "^$(basename $target).bak" | head -n1)
    if [[ -f "$backup_dir/$last_backup" ]]; then
      cp -f "$backup_dir/$last_backup" "$target"
      ${COMPOSE_CMD} -f "$COMPOSE_FILE" restart "$service"
      if wait_healthy "$url" "$HEALTH_TIMEOUT"; then
        warn "已回滚 ${service} 到旧版本并恢复运行。停止整体更新，请排查问题后重试。"
      else
        err "回滚后 ${service} 仍未就绪，需要人工介入。"
      fi
    else
      err "无备份可回滚，请人工处理 ${service}。"
    fi
    exit 1
  fi

  log "✅ ${service} 更新成功"
}

main() {
  check_prereq
  for item in "${NODES[@]}"; do
    IFS=":" read -r svc port dir <<<"$item"
    update_one "$svc" "$port" "$dir"
  done
  log "🎉 全部节点滚动更新完成"
}

main "$@"