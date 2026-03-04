#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# 基础配置
# =========================
GO_BIN="/usr/local/go/bin/go"
PROJECT_DIR="/home/admin/im/qgim_server_gateway"
OUTPUT_DIR="/home/admin/package/gateway"
KEEP_COUNT=10   # 保留最近多少个包

# =========================
# 参数检查
# =========================
if [ $# -lt 1 ]; then
  echo "用法: $0 <branch>"
  exit 1
fi

BRANCH="$1"

echo "======================================"
echo "开始构建 gateway"
echo "分支: ${BRANCH}"
echo "时间: $(date)"
echo "======================================"

# =========================
# 检查 Go
# =========================
if [ ! -x "$GO_BIN" ]; then
  echo "错误: 未找到 Go 可执行文件: $GO_BIN"
  exit 1
fi

"$GO_BIN" version

# =========================
# 进入项目目录
# =========================
cd "$PROJECT_DIR"
echo "当前目录: $(pwd)"

# =========================
# 更新代码
# =========================
echo "===== 更新代码 ====="
git fetch origin
git checkout "$BRANCH"
git pull origin "$BRANCH"

# =========================
# 构建
# =========================
echo "===== 开始编译 ====="

export CGO_ENABLED=0
export GOOS=linux
export GOARCH=amd64

"$GO_BIN" mod tidy
"$GO_BIN" build -o gateway

echo "===== 编译完成 ====="

# =========================
# 生成文件名
# =========================
NOW_TIME=$(date +"%Y%m%d%H%M%S")
RAND_NUM=$RANDOM
FILE_NAME="gateway_${NOW_TIME}_${RAND_NUM}.tar.gz"

mkdir -p "$OUTPUT_DIR"

# =========================
# 打包
# =========================
echo "===== 开始打包 ====="
tar -czf "${OUTPUT_DIR}/${FILE_NAME}" gateway
echo "===== 打包完成 ====="
echo "输出文件: ${OUTPUT_DIR}/${FILE_NAME}"

# =========================
# 自动清理旧包（保留最新 N 个）
# =========================
echo "===== 开始清理旧包（保留最近 ${KEEP_COUNT} 个） ====="

cd "$OUTPUT_DIR"

# 列出按时间倒序排列的包
PACKAGE_LIST=$(ls -1t gateway_*.tar.gz 2>/dev/null || true)

TOTAL_COUNT=$(echo "$PACKAGE_LIST" | wc -l)

if [ "$TOTAL_COUNT" -gt "$KEEP_COUNT" ]; then
    REMOVE_LIST=$(echo "$PACKAGE_LIST" | tail -n +$((KEEP_COUNT+1)))

    echo "将删除以下旧包："
    echo "$REMOVE_LIST"

    echo "$REMOVE_LIST" | xargs -r rm -f

    echo "旧包清理完成"
else
    echo "当前包数量 ${TOTAL_COUNT} <= ${KEEP_COUNT}，无需清理"
fi

echo "===== 打包完成 ====="
echo "输出文件: ${OUTPUT_DIR}/${FILE_NAME}"

# 给 AWX 用的变量输出
echo "BUILD_PACKAGE=${FILE_NAME}"

echo "======================================"
echo "构建结束"
echo "======================================"