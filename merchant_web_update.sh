#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="/home/admin/merchant_web"
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"
SERVICE_NAME="web"

cd "${PROJECT_DIR}"

# ⭐ 同时支持 tar 和 tar.gz
LATEST_PACKAGE=$(ls -1t merchant_web_*.tar merchant_web_*.tar.gz 2>/dev/null | head -n 1 || true)

if [ -z "${LATEST_PACKAGE}" ]; then
  echo "❌ 未找到镜像包"
  exit 1
fi

echo ">>> 使用包 ${LATEST_PACKAGE}"

echo ">>> 导入镜像"

if [[ "${LATEST_PACKAGE}" == *.tar.gz ]]; then
  gunzip -c "${LATEST_PACKAGE}" | docker load
else
  docker load -i "${LATEST_PACKAGE}"
fi

echo ">>> 重启服务"
docker compose -f ${COMPOSE_FILE} down
docker compose -f ${COMPOSE_FILE} up -d

sleep 5

CONTAINER_ID=$(docker compose -f ${COMPOSE_FILE} ps -q ${SERVICE_NAME})
RUNNING=$(docker inspect -f '{{.State.Running}}' ${CONTAINER_ID})

if [ "${RUNNING}" != "true" ]; then
  echo "❌ 容器启动失败"
  exit 1
fi

echo "✅ 发布成功"
