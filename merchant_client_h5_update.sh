#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/home/admin/merchant_client_web"
IMAGE_NAME="merchant_client_web"
BACKUP_DIR="${APP_DIR}/backup"
KEEP=5

cd "$APP_DIR"
mkdir -p "$BACKUP_DIR"

log() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERR ]\033[0m $*" >&2; }

# ==============================
# 回滚到最近一个备份
# ==============================
rollback_latest() {
    log "开始回滚到最近备份"

    LAST_BACKUP=$(ls -1t ${BACKUP_DIR}/${IMAGE_NAME}_*.tar.gz 2>/dev/null | head -n1 || true)

    if [[ -z "${LAST_BACKUP}" ]]; then
        err "备份数量不足，无法回滚"
        exit 1
    fi

    log "使用备份文件: ${LAST_BACKUP}"

    gunzip -c "${LAST_BACKUP}" | docker load

    docker compose down
    docker compose up -d

    log "✅ 回滚完成"
    exit 0
}

# ==============================
# 回滚到指定备份
# ==============================
rollback_to() {
    FILE="$1"

    if [[ ! -f "${BACKUP_DIR}/${FILE}" ]]; then
        err "指定备份不存在: ${FILE}"
        exit 1
    fi

    log "回滚到指定备份: ${FILE}"

    gunzip -c "${BACKUP_DIR}/${FILE}" | docker load

    docker compose down
    docker compose up -d

    log "✅ 指定版本回滚完成"
    exit 0
}

# ==============================
# 参数判断
# ==============================
case "${1:-}" in
    rollback)
        rollback_latest
        ;;
    rollback-to)
        shift
        rollback_to "$1"
        ;;
esac

echo "========== 开始更新 ${IMAGE_NAME} =========="

# ------------------------------
# 1️⃣ 备份当前镜像（压缩）
# ------------------------------
if docker image inspect ${IMAGE_NAME}:latest >/dev/null 2>&1; then
    TS=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="${BACKUP_DIR}/${IMAGE_NAME}_${TS}.tar.gz"

    log "备份当前镜像 -> ${BACKUP_FILE}"
    docker save ${IMAGE_NAME}:latest | gzip > "$BACKUP_FILE"
else
    warn "未找到旧镜像，跳过备份"
fi

# ------------------------------
# 2️⃣ 清理旧备份（最多保留5个）
# ------------------------------
log "清理旧备份..."
ls -1t ${BACKUP_DIR}/${IMAGE_NAME}_*.tar.gz 2>/dev/null | tail -n +$((KEEP+1)) | xargs -r rm -f

# ------------------------------
# 3️⃣ 查找最新镜像包
# ------------------------------
PKG=$(ls -t ${APP_DIR}/${IMAGE_NAME}_*.tar ${APP_DIR}/${IMAGE_NAME}_*.tar.gz 2>/dev/null | head -n 1 || true)

if [[ -z "${PKG}" ]]; then
    err "未找到镜像包"
    exit 1
fi

log "发现镜像包: ${PKG}"

# ------------------------------
# 4️⃣ 加载镜像
# ------------------------------
if [[ "${PKG}" == *.tar.gz ]]; then
    log "解压并加载镜像..."
    gunzip -c "${PKG}" | docker load
else
    log "加载镜像..."
    docker load -i "${PKG}"
fi

# ------------------------------
# 5️⃣ 重启服务
# ------------------------------
log "重启服务..."
if ! docker compose down || ! docker compose up -d; then
    err "启动失败，自动回滚"
    rollback_latest
fi

log "✅ 更新完成"