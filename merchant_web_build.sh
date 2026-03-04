#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================
# 参数检查
# ==============================

if [ $# -ne 1 ]; then
  echo "用法: $0 <branch_name>"
  exit 1
fi

BRANCH="$1"

# ==============================
# 可配置参数
# ==============================

PROJECT_DIR="/home/admin/im/qgim_client_merchants_web"
IMAGE_NAME="merchant_web"
TAG="latest"
SAVE_DIR="/home/admin/package/merchant_web"
KEEP_COUNT=10

# ==============================
# 进入项目目录
# ==============================

echo ">>> 进入项目目录 ${PROJECT_DIR}"
cd "${PROJECT_DIR}"

# ==============================
# 更新代码
# ==============================

echo ">>> 拉取远程代码"
git fetch origin

echo ">>> 切换分支 ${BRANCH}"
git checkout "${BRANCH}"

echo ">>> 拉取最新代码"
git pull origin "${BRANCH}"

# ==============================
# 创建保存目录
# ==============================

mkdir -p "${SAVE_DIR}"

# ==============================
# 构建 Docker 镜像
# ==============================

echo ">>> 构建 Docker 镜像 ${IMAGE_NAME}:${TAG}"
docker build -t ${IMAGE_NAME}:${TAG} .

# ==============================
# 生成时间戳文件名
# ==============================

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TAR_NAME="${IMAGE_NAME}_${TIMESTAMP}.tar.gz"
TAR_PATH="${SAVE_DIR}/${TAR_NAME}"

# ==============================
# 保存并压缩镜像
# ==============================

echo ">>> 保存并压缩镜像到 ${TAR_PATH}"
docker save ${IMAGE_NAME}:${TAG} | gzip > "${TAR_PATH}"

# ==============================
# 清理旧文件
# ==============================

echo ">>> 只保留最近 ${KEEP_COUNT} 个镜像文件"
cd "${SAVE_DIR}"
ls -1t ${IMAGE_NAME}_*.tar.gz 2>/dev/null | tail -n +$((KEEP_COUNT + 1)) | xargs -r rm -f

echo ">>> 构建完成"
ls -lh ${IMAGE_NAME}_*.tar.gz