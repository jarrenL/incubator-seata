#!/bin/bash
# ============================================================
# Seata Server 一键启动脚本
# 用于自包含部署包 seata-package/
# ============================================================
# 包结构:
#   seata-package/
#   ├── bin/start.sh          ← 此脚本
#   ├── conf/application-gaussdb.yml
#   └── lib/*.jar
#
# 用法:
#   # 集中式（默认）
#   ./bin/start.sh
#
#   # 分布式
#   MODE=distributed ./bin/start.sh
#
#   # 或者先 source env.sh
#   source /path/to/env.sh centralized
#   ./bin/start.sh
#
# 环境变量（优先级从高到低）:
#   1. 命令行 export 或 env.sh 设置的
#   2. 脚本内置默认值（指向集中式云 GaussDB）
# ============================================================

set -e

# ─── 定位包根目录 ───
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CONF_DIR="$PKG_DIR/conf"
LIB_DIR="$PKG_DIR/lib"

# ─── 如果 env.sh 设置了 MODE，按模式选默认值 ───
MODE="${MODE:-centralized}"

# ─── GaussDB 连接默认值（被同名环境变量覆盖） ───
#     集中式默认值
if [ "$MODE" = "distributed" ]; then
    : ${GAUSSDB_HOST:="60.204.173.73"}
    : ${GAUSSDB_PORT:="8000"}
    : ${GAUSSDB_USER:="root"}
    : ${GAUSSDB_PASSWORD:="Gauss_234net,"}
    echo "[start] 模式: 分布式 GaussDB"
else
    : ${GAUSSDB_HOST:="1.92.120.69"}
    : ${GAUSSDB_PORT:="8000"}
    : ${GAUSSDB_USER:="root"}
    : ${GAUSSDB_PASSWORD:="GaussDB123"}
    echo "[start] 模式: 集中式 GaussDB"
fi

: ${SEATA_SERVER_PORT:="8091"}

# ─── 构建 Seata store DB URL ───
SEATA_STORE_DB_URL="${SEATA_STORE_DB_URL:-jdbc:gaussdb://${GAUSSDB_HOST}:${GAUSSDB_PORT}/postgres?currentSchema=public}"

echo "[start] GaussDB 地址: ${GAUSSDB_HOST}:${GAUSSDB_PORT}"
echo "[start] Seata Server 端口: ${SEATA_SERVER_PORT}"

# ─── 检查必要文件 ───
if [ ! -d "$LIB_DIR" ]; then
    echo "[ERROR] lib/ 目录不存在: $LIB_DIR"
    echo "        请确保解压了完整的 seata-package/"
    exit 1
fi

JAR_COUNT=$(ls "$LIB_DIR"/*.jar 2>/dev/null | wc -l | tr -d ' ')
if [ "$JAR_COUNT" -lt 10 ]; then
    echo "[ERROR] lib/ 目录下 jar 不足（找到 $JAR_COUNT 个）"
    exit 1
fi

# ─── JVM 参数 ───
JAVA_OPTS="${JAVA_OPTS:--Xmx2g -Xms512m}"

# ─── 启动 ───
echo "[start] 正在启动 Seata Server..."
echo "[start] JAVA_HOME=${JAVA_HOME:-$(/usr/libexec/java_home 2>/dev/null || echo '系统默认')}"

exec java $JAVA_OPTS \
    -Dspring.profiles.active=gaussdb \
    -Dserver.port="${SEATA_SERVER_PORT}" \
    -Dseata.store.db.url="${SEATA_STORE_DB_URL}" \
    -Dseata.store.db.user="${GAUSSDB_USER}" \
    -Dseata.store.db.password="${GAUSSDB_PASSWORD}" \
    -cp "${CONF_DIR}:${LIB_DIR}/*" \
    org.apache.seata.server.ServerApplication
