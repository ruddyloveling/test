#!/usr/bin/env bash
set -Eeuo pipefail

if [ $# -ne 1 ]; then
  echo "用法: $0 <branch>"
  exit 1
fi

BRANCH="$1"

PROJECT_DIR="/home/admin/im/qgim_client_pc_web"
IMAGE_NAME="merchant_client_web"
TAG="latest"
SAVE_DIR="/home/admin/package/merchant_client_web"
KEEP_COUNT=10

echo ">>> 进入项目目录"
cd "${PROJECT_DIR}"

echo ">>> 更新代码"
git fetch origin
git checkout "${BRANCH}"
git pull origin "${BRANCH}"

echo ">>> 构建镜像 ${IMAGE_NAME}:${TAG}"
docker build -t ${IMAGE_NAME}:${TAG} .

mkdir -p "${SAVE_DIR}"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TAR_NAME="merchant_client_web_${TIMESTAMP}.tar"
TAR_GZ_NAME="${TAR_NAME}.gz"
TAR_PATH="${SAVE_DIR}/${TAR_NAME}"

echo ">>> 保存镜像"
docker save -o "${TAR_PATH}" ${IMAGE_NAME}:${TAG}

echo ">>> 压缩镜像"
gzip "${TAR_PATH}"

echo ">>> 清理旧包"
cd "${SAVE_DIR}"
ls -1t merchant_client_web_*.tar.gz 2>/dev/null | tail -n +$((KEEP_COUNT + 1)) | xargs -r rm -f

echo ">>> 构建完成"

# ⭐⭐⭐ 关键输出（AWX解析用）
echo "BUILD_PACKAGE=${TAR_GZ_NAME}"