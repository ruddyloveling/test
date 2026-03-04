#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================
# 可调参数
# ==============================
COMPOSE_CMD="${COMPOSE_CMD:-docker-compose}"
COMPOSE_FILE="${COMPOSE_FILE:-/home/admin/merchant_run/docker-compose.yml}"
HEALTH_PATH="${HEALTH_PATH:-/v1/health}"
HEALTH_HOST="${HEALTH_HOST:-127.0.0.1}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-60}"
BASE_DIR="/home/admin/merchant"
BACKUP_DIR="${BASE_DIR}/backup"
KEEP=5

cd "$BASE_DIR"

# 节点配置：服务名:端口:二进制目录
NODES=(
  "merchant1:18080:./merchant1"
  "merchant2:18081:./merchant2"
)

# ==============================
# 工具函数
# ==============================
log() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERR ]\033[0m $*" >&2; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || { err "缺少命令: $1"; exit 127; }; }

check_prereq() {
    need_cmd curl
    need_cmd ${COMPOSE_CMD%% *}
    [[ -f "$COMPOSE_FILE" ]] || { err "找不到 compose 文件: $COMPOSE_FILE"; exit 2; }
    mkdir -p "$BACKUP_DIR"
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

# ==============================
# 确定更新包
# ==============================
determine_pkg() {
    local pkg_arg="$1"
    if [[ -n "$pkg_arg" ]]; then
        [[ -f "$pkg_arg" ]] || { err "指定更新包不存在: $pkg_arg"; exit 1; }
        PKG="$pkg_arg"
    else
        if [[ -f ./merchant ]]; then
            PKG="./merchant"
            log "未指定包，使用当前目录下的二进制: $PKG"
        else
            PKG=$(ls -t ./merchant*.tar ./merchant*.tar.gz 2>/dev/null | head -n1 || true)
            if [[ -n "$PKG" ]]; then
                log "未指定包，使用当前目录下最新镜像包: $PKG"
            else
                err "未找到可用的更新包，请指定 --pkg 或确保当前目录有 merchant/merchant.tar.gz"
                exit 1
            fi
        fi
    fi
}

# ==============================
# 更新单节点
# ==============================
update_one() {
    local service="$1" port="$2" dir="$3"
    local target="$dir/merchant"
    local timestamp backup url

    timestamp=$(date +%Y%m%d-%H%M%S)
    backup="${BACKUP_DIR}/merchant.bak.${timestamp}"
    url="http://${HEALTH_HOST}:${port}${HEALTH_PATH}"

    log "开始更新 ${service}"

    if [[ -f "$target" ]]; then
        cp -f "$target" "$backup"
        log "已备份旧版本 -> $backup"
        ls -1t ${BACKUP_DIR}/merchant.bak.* 2>/dev/null | tail -n +$((KEEP+1)) | xargs -r rm -f
    fi

    # 更新逻辑
    apply_pkg "$PKG" "$dir"

    # 重启 & 健康检查
    ${COMPOSE_CMD} -f "$COMPOSE_FILE" restart "$service"
    log "等待健康检查: $url"
    if ! wait_healthy "$url" "$HEALTH_TIMEOUT"; then
        err "$service 健康检查失败，自动回滚"
        rollback_single "$service" "$dir" "$url" "$backup"
    fi
    log "✅ $service 更新成功"
}

# ==============================
# 应用包函数
# ==============================
apply_pkg() {
    local pkg="$1" dir="$2"
    local target="$dir/merchant"

    if [[ "$pkg" == *.tar.gz ]]; then
        mkdir -p "$dir/tmp_update"
        tar -xzf "$pkg" -C "$dir/tmp_update"
        cp -f "$dir/tmp_update/merchant" "$target"
        rm -rf "$dir/tmp_update"
    elif [[ "$pkg" == *.tar ]]; then
        mkdir -p "$dir/tmp_update"
        tar -xf "$pkg" -C "$dir/tmp_update"
        cp -f "$dir/tmp_update/merchant" "$target"
        rm -rf "$dir/tmp_update"
    else
        cp -f "$pkg" "$target"
    fi
    chmod +x "$target"
}

# ==============================
# 单节点回滚
# ==============================
rollback_single() {
    local service="$1" dir="$2" url="$3" backup_file="$4"

    log "开始回滚 $service -> $backup_file"
    apply_pkg "$backup_file" "$dir"

    ${COMPOSE_CMD} -f "$COMPOSE_FILE" restart "$service"

    if wait_healthy "$url" "$HEALTH_TIMEOUT"; then
        warn "已回滚 $service"
        return 0
    else
        warn "$service 回滚失败，尝试更早版本"
        local backups=($(ls -1t ${BACKUP_DIR}/merchant.bak.* 2>/dev/null))
        for bf in "${backups[@]}"; do
            [[ "$bf" == "$backup_file" ]] && continue
            log "尝试回滚到 $bf"
            apply_pkg "$bf" "$dir"
            ${COMPOSE_CMD} -f "$COMPOSE_FILE" restart "$service"
            if wait_healthy "$url" "$HEALTH_TIMEOUT"; then
                warn "已成功回滚 $service 到 $bf"
                return 0
            fi
        done
        err "所有备份都回滚失败，请人工介入 $service"
        exit 1
    fi
}

# ==============================
# 回滚逻辑（全量）
# ==============================
rollback_all() {
    local target_file
    if [[ $# -eq 0 ]]; then
        log "回滚到上一个版本"
        FILES=($(ls -1t ${BACKUP_DIR}/merchant.bak.* 2>/dev/null))
        if [[ ${#FILES[@]} -eq 0 ]]; then
            err "没有备份可回滚"
            exit 1
        elif [[ ${#FILES[@]} -eq 1 ]]; then
            warn "只有一个备份，回滚该版本"
            target_file="${FILES[0]}"
        else
            target_file="${FILES[1]}"
        fi
    else
        target_file="${BACKUP_DIR}/$1"
        [[ -f "$target_file" ]] || { err "指定备份不存在"; exit 1; }
    fi

    log "回滚版本: $target_file"

    for item in "${NODES[@]}"; do
        IFS=":" read -r svc port dir <<<"$item"
        rollback_single "$svc" "$dir" "http://${HEALTH_HOST}:${port}${HEALTH_PATH}" "$target_file"
    done
    log "🎉 全部节点回滚完成"
}

# ==============================
# 主入口
# ==============================
main() {
    check_prereq "${1:-}"

    case "${1:-}" in
        rollback)
            shift
            rollback_all "$@"
            ;;
        *)
            if [[ "${1:-}" == "--pkg" ]]; then
                shift
                determine_pkg "$1"
            else
                determine_pkg ""
            fi

            for item in "${NODES[@]}"; do
                IFS=":" read -r svc port dir <<<"$item"
                update_one "$svc" "$port" "$dir"
            done
            log "🎉 全部节点滚动更新完成"
            ;;
    esac
}

main "$@"