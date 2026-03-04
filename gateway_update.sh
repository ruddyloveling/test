#!/usr/bin/env bash
set -Eeuo pipefail

# ========== 可调参数 ==========
BASE_DIR="/home/admin/gateway"
COMPOSE_CMD="${COMPOSE_CMD:-docker-compose}"
COMPOSE_FILE="${COMPOSE_FILE:-${BASE_DIR}/docker-compose.yml}"
NEW_BIN="${NEW_BIN:-${BASE_DIR}/gateway}"
HEALTH_PATH="${HEALTH_PATH:-/v1/health}"
HEALTH_HOST="${HEALTH_HOST:-127.0.0.1}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-60}"
MAX_BACKUP=5
# =================================

cd "$BASE_DIR"

NODES=(
  "gateway1:18081:${BASE_DIR}/gateway1"
  "gateway2:18082:${BASE_DIR}/gateway2"
)

log() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERR ]\033[0m $*" >&2; }

# ===============================
# 二进制级回滚
# ===============================
rollback_bin() {
  log "执行二进制回滚"

  for item in "${NODES[@]}"; do
    IFS=":" read -r svc port dir <<<"$item"
    target="$dir/gateway"
    backup_dir="$dir/backup"

    last_backup=$(ls -1t "$backup_dir" 2>/dev/null | head -n1 || true)

    if [[ -z "${last_backup:-}" ]]; then
      err "$svc 无备份，无法回滚"
      continue
    fi

    cp -f "$backup_dir/$last_backup" "$target"
    ${COMPOSE_CMD} -f "$COMPOSE_FILE" restart "$svc"
    log "已回滚 $svc -> $last_backup"
  done
  exit 0
}

# ===============================
# 包级回滚
# ===============================
pkg_rollback() {
  local pkg="$1"
  local pkg_path="${BASE_DIR}/package_backup/${pkg}"

  if [[ ! -f "$pkg_path" ]]; then
    err "包不存在: $pkg_path"
    exit 1
  fi

  log "回滚到构建包: $pkg"

  # 当前包备份
  mkdir -p "${BASE_DIR}/package_backup"
  current_pkg=$(ls ${BASE_DIR}/gateway_*.tar* 2>/dev/null | head -n1 || true)

  if [[ -n "${current_pkg:-}" ]]; then
    mv "$current_pkg" "${BASE_DIR}/package_backup/"
  fi

  # 移动目标包回来
  mv "$pkg_path" "$BASE_DIR/"

  # 解压
  tar -xf "${BASE_DIR}/${pkg}" -C "$BASE_DIR"

  log "解压完成，开始滚动更新"
  main
  exit 0
}

# ===============================
# 单节点更新
# ===============================
update_one() {
  local service="$1" port="$2" dir="$3"
  local target="$dir/gateway"
  local backup_dir="$dir/backup"
  local url="http://${HEALTH_HOST}:${port}${HEALTH_PATH}"

  log "开始更新 $service"

  mkdir -p "$backup_dir"

  if [[ -f "$target" ]]; then
    cp -f "$target" "$backup_dir/gateway.bak.$(date +%Y%m%d-%H%M%S)"
  fi

  cp -f "$NEW_BIN" "$target"
  chmod +x "$target"

  # 只保留最近5个备份
  ls -1t "$backup_dir" | tail -n +$((MAX_BACKUP+1)) | while read f; do
    rm -f "$backup_dir/$f"
  done

  ${COMPOSE_CMD} -f "$COMPOSE_FILE" restart "$service"

  if ! wait_healthy "$url" "$HEALTH_TIMEOUT"; then
    err "$service 健康检查失败，自动回滚"
    rollback_bin
  fi

  log "✅ $service 更新成功"
}

wait_healthy() {
  local url="$1"
  local timeout="$2"
  start=$(date +%s)

  until curl -fsS "$url" >/dev/null 2>&1; do
    now=$(date +%s)
    if (( now - start >= timeout )); then
      return 1
    fi
    sleep 2
  done
  return 0
}

# ===============================
# 主流程
# ===============================
main() {
  for item in "${NODES[@]}"; do
    IFS=":" read -r svc port dir <<<"$item"
    update_one "$svc" "$port" "$dir"
  done
  log "🎉 全部节点更新完成"
}

# ===============================
# 入口
# ===============================
case "${1:-}" in
  rollback)
    rollback_bin
    ;;
  pkg-rollback)
    shift
    pkg_rollback "$1"
    ;;
  *)
    main
    ;;
esac