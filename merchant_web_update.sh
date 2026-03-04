#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================
# 配置
# ==============================

PROJECT_DIR="/home/admin/merchant_web"
PACKAGE_DIR="/home/admin/merchant_web"
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"
SERVICE_NAME="web"   # docker compose 里的服务名
KEEP_IMAGE_COUNT=3   # 保留最近3个镜像

# ==============================
# 获取当前运行镜像（用于回滚）
# ==============================

echo ">>> 获取当前运行镜像"

OLD_IMAGE=$(docker compose -f ${COMPOSE_FILE} ps -q ${SERVICE_NAME} \
  | xargs -r docker inspect --format='{{.Config.Image}}' 2>/dev/null || true)

echo ">>> 当前运行镜像: ${OLD_IMAGE:-无}"

# ==============================
# 查找最新镜像包
# ==============================

LATEST_PACKAGE=$(ls -1t ${PACKAGE_DIR}/merchant_web_*.tar \
                         ${PACKAGE_DIR}/merchant_web_*.tar.gz \
                         2>/dev/null | head -n 1 || true)

if [ -z "${LATEST_PACKAGE}" ]; then
  echo "❌ 未找到镜像包"
  exit 1
fi

echo ">>> 使用镜像包: ${LATEST_PACKAGE}"

# ==============================
# 导入镜像
# ==============================

echo ">>> 导入镜像"

if [[ "${LATEST_PACKAGE}" == *.tar.gz ]]; then
  gunzip -c "${LATEST_PACKAGE}" | docker load
else
  docker load -i "${LATEST_PACKAGE}"
fi

# 获取新镜像名
NEW_IMAGE=$(docker load -i "${LATEST_PACKAGE}" 2>/dev/null | grep "Loaded image" | awk '{print $3}' || true)

# 如果上面没抓到（tar.gz 情况）
if [ -z "${NEW_IMAGE}" ]; then
  NEW_IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | head -n 1)
fi

echo ">>> 新镜像: ${NEW_IMAGE}"

# ==============================
# 重启服务
# ==============================

echo ">>> 停止旧服务"
docker compose -f ${COMPOSE_FILE} down

echo ">>> 启动新服务"
docker compose -f ${COMPOSE_FILE} up -d

sleep 5

# ==============================
# 健康检查
# ==============================

echo ">>> 检查容器状态"

CONTAINER_ID=$(docker compose -f ${COMPOSE_FILE} ps -q ${SERVICE_NAME})
RUNNING_STATE=$(docker inspect -f '{{.State.Running}}' ${CONTAINER_ID})

if [ "${RUNNING_STATE}" != "true" ]; then
  echo "❌ 新版本启动失败，开始回滚"

  if [ -n "${OLD_IMAGE}" ]; then
    docker compose -f ${COMPOSE_FILE} down
    docker tag ${OLD_IMAGE} ${SERVICE_NAME}:rollback
    docker compose -f ${COMPOSE_FILE} up -d
    echo "✅ 已回滚到旧版本"
  else
    echo "⚠ 无旧版本可回滚"
  fi

  exit 1
fi

echo "✅ 发布成功"

# ==============================
# 清理旧镜像
# ==============================

echo ">>> 清理旧镜像"

docker images qgim-client-merchants-web --format "{{.ID}}" \
| tail -n +$((KEEP_IMAGE_COUNT + 1)) \
| xargs -r docker rmi || true

echo ">>> 当前运行容器"
docker ps