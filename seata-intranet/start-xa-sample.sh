#!/bin/bash
# ============================================================
# XA 模式样本应用 - 一键启动（4个服务: account/storage/order/business）
# ============================================================
# 前置条件:
#   1. Seata Server 已启动 (:8091)
#   2. GaussDB 已初始化（seata_account/order/storage 库）
#   3. GaussDB max_prepared_transactions > 0  ⚠️ 必须！
#   4. xa-sample/springboot-feign-seata-xa 已编译: mvn clean package -DskipTests
#
# 用法:
#   source /path/to/env.sh [centralized|distributed]
#   ./start-xa-sample.sh
#
# 注意: XA 模式不自动触发 rollback（business 模块无 auto-trigger）。
#       本脚本仅启动服务，需手动调用 API 触发事务测试。
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── 检查环境变量 ───
if [ -z "$GAUSSDB_JDBC_BASE" ]; then
    echo "[ERROR] 请先 source env.sh [centralized|distributed]"
    exit 1
fi

# ─── 示例 jar 路径 ───
SAMPLE_DIR="${SAMPLE_DIR:-$HOME/IdeaProjects/incubator-seata-samples/xa-sample/springboot-feign-seata-xa}"
ACCOUNT_JAR="$SAMPLE_DIR/springboot-feign-seata-account/target/springboot-feign-seata-account-2.5.0-gaussdb.jar"
STORAGE_JAR="$SAMPLE_DIR/springboot-feign-seata-storage/target/springboot-feign-seata-storage-2.5.0-gaussdb.jar"
ORDER_JAR="$SAMPLE_DIR/springboot-feign-seata-order/target/springboot-feign-seata-order-2.5.0-gaussdb.jar"
BUSINESS_JAR="$SAMPLE_DIR/springboot-feign-seata-business/target/springboot-feign-seata-business-2.5.0-gaussdb.jar"

for jar in "$ACCOUNT_JAR" "$STORAGE_JAR" "$ORDER_JAR" "$BUSINESS_JAR"; do
    if [ ! -f "$jar" ]; then
        echo "[ERROR] 找不到 $jar"
        echo "        请先编译: cd $SAMPLE_DIR && mvn clean package -DskipTests"
        exit 1
    fi
done

# ─── 端口定义 ───
ACCOUNT_PORT=7083
ORDER_PORT=7082
STORAGE_PORT=7081
BUSINESS_PORT=7084

# ─── 清理旧进程 ───
echo "[XA] 清理旧进程..."
for port in $ACCOUNT_PORT $ORDER_PORT $STORAGE_PORT $BUSINESS_PORT; do
    lsof -ti :$port 2>/dev/null | xargs kill -9 2>/dev/null || true
done
sleep 2

# ─── 数据库连接 ───
ACCOUNT_URL="${GAUSSDB_JDBC_BASE}/seata_account?currentSchema=public"
ORDER_URL="${GAUSSDB_JDBC_BASE}/seata_order?currentSchema=public"
STORAGE_URL="${GAUSSDB_JDBC_BASE}/seata_storage?currentSchema=public"
BUSINESS_URL="${GAUSSDB_JDBC_BASE}/seata_account?currentSchema=public"

# ─── 启动 4 个服务 ───
echo "[XA] 启动服务..."

java -jar "$ACCOUNT_JAR" \
    --server.port="$ACCOUNT_PORT" \
    --spring.datasource.url="$ACCOUNT_URL" \
    --spring.datasource.username="$GAUSSDB_USER" \
    --spring.datasource.password="$GAUSSDB_PASSWORD" \
    --seata.registry.type=file \
    --seata.config.type=file \
    --spring.datasource.hikari.auto-commit=true \
    > /tmp/seata-xa-account.log 2>&1 &
echo "  account :${ACCOUNT_PORT} (pid $!)"

java -jar "$STORAGE_JAR" \
    --server.port="$STORAGE_PORT" \
    --spring.datasource.url="$STORAGE_URL" \
    --spring.datasource.username="$GAUSSDB_USER" \
    --spring.datasource.password="$GAUSSDB_PASSWORD" \
    --seata.registry.type=file \
    --seata.config.type=file \
    --spring.datasource.hikari.auto-commit=true \
    > /tmp/seata-xa-storage.log 2>&1 &
echo "  storage :${STORAGE_PORT} (pid $!)"

java -jar "$ORDER_JAR" \
    --server.port="$ORDER_PORT" \
    --spring.datasource.url="$ORDER_URL" \
    --spring.datasource.username="$GAUSSDB_USER" \
    --spring.datasource.password="$GAUSSDB_PASSWORD" \
    --seata.registry.type=file \
    --seata.config.type=file \
    --spring.datasource.hikari.auto-commit=true \
    > /tmp/seata-xa-order.log 2>&1 &
echo "  order   :${ORDER_PORT} (pid $!)"

java -jar "$BUSINESS_JAR" \
    --server.port="$BUSINESS_PORT" \
    --spring.datasource.url="$BUSINESS_URL" \
    --spring.datasource.username="$GAUSSDB_USER" \
    --spring.datasource.password="$GAUSSDB_PASSWORD" \
    --seata.registry.type=file \
    --seata.config.type=file \
    --spring.datasource.hikari.auto-commit=true \
    > /tmp/seata-xa-business.log 2>&1 &
echo "  business :${BUSINESS_PORT} (pid $!)"

# ─── 等待就绪 ───
echo "[XA] 等待服务就绪..."
READY=0
for i in $(seq 1 20); do
    A=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 1 http://127.0.0.1:${ACCOUNT_PORT}/ 2>/dev/null || echo "000")
    S=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 1 http://127.0.0.1:${STORAGE_PORT}/ 2>/dev/null || echo "000")
    O=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 1 http://127.0.0.1:${ORDER_PORT}/ 2>/dev/null || echo "000")
    B=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 1 http://127.0.0.1:${BUSINESS_PORT}/ 2>/dev/null || echo "000")
    if [ "$A" != "000" ] && [ "$S" != "000" ] && [ "$O" != "000" ] && [ "$B" != "000" ]; then
        READY=1
        echo "[XA] 全部服务就绪 (${i}s)"
        break
    fi
    sleep 2
done

if [ "$READY" = "0" ]; then
    echo "[XA] WARNING: 部分服务未就绪"
fi

echo ""
echo "[XA] 服务已启动，手动触发 XA 事务："
echo "  curl http://127.0.0.1:${BUSINESS_PORT}/purchase/commit"
echo "  curl http://127.0.0.1:${BUSINESS_PORT}/purchase/rollback"
echo ""
echo "  日志: tail -f /tmp/seata-xa-{account,storage,order,business}.log"
