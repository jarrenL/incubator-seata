#!/bin/bash
# ============================================================
# AT 模式样本应用 - 一键启动（4个服务: account/storage/order/business）
# ============================================================
# 前置条件:
#   1. Seata Server 已启动 (:8091)
#   2. GaussDB 已初始化（seata_account/order/storage 库，表+种子数据）
#   3. at-sample/springboot-seata 已编译: mvn package -DskipTests
#   4. 分布式 GaussDB 需先修复 undo_log 序列（见 init-db.sh）
#
# 用法:
#   source /path/to/env.sh [centralized|distributed]
#   ./start-at-sample.sh [commit|rollback]
#
# commit  → force-rollback=false（正常提交，验证数据一致性）
# rollback → force-rollback=true（触发回滚，验证数据不变）
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── 检查环境变量 ───
if [ -z "$GAUSSDB_JDBC_BASE" ]; then
    echo "[ERROR] 请先 source env.sh [centralized|distributed]"
    exit 1
fi

TEST_TYPE="${1:-commit}"

# ─── 示例 jar 路径 ───
SAMPLE_DIR="${SAMPLE_DIR:-$HOME/IdeaProjects/incubator-seata-samples/at-sample/springboot-seata}"
JAR_FILE="$SAMPLE_DIR/target/springboot-seata-2.5.0-gaussdb.jar"

if [ ! -f "$JAR_FILE" ]; then
    echo "[ERROR] 找不到 $JAR_FILE"
    echo "        请先编译: cd $SAMPLE_DIR && mvn package -DskipTests"
    exit 1
fi

# ─── 端口定义 ───
ACCOUNT_PORT=9081
STORAGE_PORT=9082
ORDER_PORT=9083
BUSINESS_PORT=9084

# ─── 清理旧进程 ───
echo "[AT] 清理旧进程..."
for port in $ACCOUNT_PORT $STORAGE_PORT $ORDER_PORT $BUSINESS_PORT; do
    lsof -ti :$port 2>/dev/null | xargs kill -9 2>/dev/null || true
done
sleep 2

# ─── 数据库连接（每个服务连不同库） ───
ACCOUNT_URL="${GAUSSDB_JDBC_BASE}/seata_account?currentSchema=public"
ORDER_URL="${GAUSSDB_JDBC_BASE}/seata_order?currentSchema=public"
STORAGE_URL="${GAUSSDB_JDBC_BASE}/seata_storage?currentSchema=public"
# business 也连 account 库（应用层只需要读 account_tbl）
BUSINESS_URL="${GAUSSDB_JDBC_BASE}/seata_account?currentSchema=public"

# ─── 启动 3 个 Provider 服务 ───
echo "[AT] 启动 Provider 服务..."

java -jar "$JAR_FILE" \
    --spring.profiles.active=account \
    --server.port="$ACCOUNT_PORT" \
    --spring.datasource.url="$ACCOUNT_URL" \
    --spring.datasource.username="$GAUSSDB_USER" \
    --spring.datasource.password="$GAUSSDB_PASSWORD" \
    > /tmp/seata-at-account.log 2>&1 &
echo "  account :${ACCOUNT_PORT} (pid $!)"

java -jar "$JAR_FILE" \
    --spring.profiles.active=storage \
    --server.port="$STORAGE_PORT" \
    --spring.datasource.url="$STORAGE_URL" \
    --spring.datasource.username="$GAUSSDB_USER" \
    --spring.datasource.password="$GAUSSDB_PASSWORD" \
    > /tmp/seata-at-storage.log 2>&1 &
echo "  storage :${STORAGE_PORT} (pid $!)"

java -jar "$JAR_FILE" \
    --spring.profiles.active=order \
    --server.port="$ORDER_PORT" \
    --spring.datasource.url="$ORDER_URL" \
    --spring.datasource.username="$GAUSSDB_USER" \
    --spring.datasource.password="$GAUSSDB_PASSWORD" \
    > /tmp/seata-at-order.log 2>&1 &
echo "  order   :${ORDER_PORT} (pid $!)"

# ─── 等待 Provider 就绪 ───
echo "[AT] 等待 Provider 就绪..."
READY=0
for i in $(seq 1 20); do
    A=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 1 http://127.0.0.1:${ACCOUNT_PORT}/ 2>/dev/null || echo "000")
    S=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 1 http://127.0.0.1:${STORAGE_PORT}/ 2>/dev/null || echo "000")
    O=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 1 http://127.0.0.1:${ORDER_PORT}/ 2>/dev/null || echo "000")
    if [ "$A" != "000" ] && [ "$S" != "000" ] && [ "$O" != "000" ]; then
        READY=1
        echo "[AT] 全部 Provider 就绪 (${i}s)"
        break
    fi
    sleep 2
done

if [ "$READY" = "0" ]; then
    echo "[AT] WARNING: Provider 未全部就绪，但继续尝试启动 Business"
fi

# ─── 启动 Business 服务（自动触发测试） ───
echo "[AT] 启动 Business 服务 (force-rollback=${TEST_TYPE})..."

if [ "$TEST_TYPE" = "rollback" ]; then
    FORCE_ROLLBACK="true"
else
    FORCE_ROLLBACK="false"
fi

java -jar "$JAR_FILE" \
    --spring.profiles.active=business \
    --server.port="$BUSINESS_PORT" \
    --spring.datasource.url="$BUSINESS_URL" \
    --spring.datasource.username="$GAUSSDB_USER" \
    --spring.datasource.password="$GAUSSDB_PASSWORD" \
    --business.auto-trigger.enabled=true \
    --business.auto-trigger.force-rollback="$FORCE_ROLLBACK" \
    > /tmp/seata-at-business.log 2>&1 &
BUSINESS_PID=$!
echo "  business :${BUSINESS_PORT} (pid $BUSINESS_PID)"

echo ""
echo "[AT] 服务已全部启动，等待测试完成（约 30 秒）..."
echo "  Business 日志: tail -f /tmp/seata-at-business.log"
echo "  Provider 日志: tail -f /tmp/seata-at-{account,storage,order}.log"
echo ""
echo "  测试完成后验证数据:"
echo "    cd $SCRIPT_DIR && source env.sh && ./check-data.sh"
