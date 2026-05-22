#!/bin/bash
# ============================================================
# Seata 2.5.0-GaussDB 内网测试环境配置
# ============================================================
# 用法: source env.sh [centralized|distributed]
#       不传参数默认使用 centralized
#
# 所有 GaussDB 连接参数集中在这里修改。
# 客户部署时改这一个文件即可，不碰任何 application.yml。
# ============================================================

MODE="${1:-centralized}"
export MODE

# ─── Seata Server 本地端口 ───
export SEATA_SERVER_PORT=8091

# ═══════════════════════════════════════════════════════════
# 集中式 GaussDB
# ═══════════════════════════════════════════════════════════
CENTRALIZED_HOST="1.92.120.69"
CENTRALIZED_PORT="8000"
CENTRALIZED_USER="root"
CENTRALIZED_PASSWORD="GaussDB123"

# ═══════════════════════════════════════════════════════════
# 分布式 GaussDB (CN 节点)
# ═══════════════════════════════════════════════════════════
DISTRIBUTED_HOST="60.204.173.73"
DISTRIBUTED_PORT="8000"
DISTRIBUTED_USER="root"
DISTRIBUTED_PASSWORD="Gauss_234net,"

# ═══════════════════════════════════════════════════════════
# 根据 MODE 设置当前环境变量
# ═══════════════════════════════════════════════════════════
if [ "$MODE" = "distributed" ]; then
    export GAUSSDB_HOST="$DISTRIBUTED_HOST"
    export GAUSSDB_PORT="$DISTRIBUTED_PORT"
    export GAUSSDB_USER="$DISTRIBUTED_USER"
    export GAUSSDB_PASSWORD="$DISTRIBUTED_PASSWORD"
    echo "[env] 模式: 分布式 GaussDB → ${GAUSSDB_HOST}:${GAUSSDB_PORT}"
else
    export GAUSSDB_HOST="$CENTRALIZED_HOST"
    export GAUSSDB_PORT="$CENTRALIZED_PORT"
    export GAUSSDB_USER="$CENTRALIZED_USER"
    export GAUSSDB_PASSWORD="$CENTRALIZED_PASSWORD"
    echo "[env] 模式: 集中式 GaussDB → ${GAUSSDB_HOST}:${GAUSSDB_PORT}"
fi

# ─── JDBC URL 模板 ───
export GAUSSDB_JDBC_BASE="jdbc:gaussdb://${GAUSSDB_HOST}:${GAUSSDB_PORT}"

# ─── Seata Server 存储库（使用 postgres 库，存放 global_table 等 5 张元数据表） ───
export SEATA_STORE_DB_URL="${GAUSSDB_JDBC_BASE}/postgres?currentSchema=public"
export SEATA_STORE_DB_USER="${GAUSSDB_USER}"
export SEATA_STORE_DB_PASSWORD="${GAUSSDB_PASSWORD}"

# ─── 样本应用数据库连接（Spring Boot relaxed binding） ───
export SPRING_DATASOURCE_DRIVERCLASSNAME="com.huawei.gaussdb.jdbc.Driver"
export SPRING_DATASOURCE_USERNAME="${GAUSSDB_USER}"
export SPRING_DATASOURCE_PASSWORD="${GAUSSDB_PASSWORD}"

# ─── 业务库 URL（各 profile 用不同库名） ───
export DB_ACCOUNT_URL="${GAUSSDB_JDBC_BASE}/seata_account?currentSchema=public"
export DB_ORDER_URL="${GAUSSDB_JDBC_BASE}/seata_order?currentSchema=public"
export DB_STORAGE_URL="${GAUSSDB_JDBC_BASE}/seata_storage?currentSchema=public"

# ─── Seata 客户端注册/配置 ───
export SEATA_REGISTRY_TYPE="file"
export SEATA_CONFIG_TYPE="file"
export SEATA_TX_SERVICE_GROUP="my_test_tx_group"
export SEATA_SERVICE_GROUP="default"

# ─── 包路径（根据实际部署位置修改） ───
# Seata Server 自包含包路径
export SEATA_PACKAGE_DIR="${SEATA_PACKAGE_DIR:-/opt/seata-package}"
# 样本应用自包含包路径
export SAMPLES_PACKAGE_DIR="${SAMPLES_PACKAGE_DIR:-/opt/seata-samples-package}"
# JDBC 驱动（优先用 seata-package/lib 里的，其次用 seata-intranet 里的）
if [ -f "$SEATA_PACKAGE_DIR/lib/gaussdbjdbc-506.0.0.b058-jdk7.jar" ]; then
    export JDBC_JAR="$SEATA_PACKAGE_DIR/lib/gaussdbjdbc-506.0.0.b058-jdk7.jar"
elif [ -f "$(dirname "${BASH_SOURCE[0]}")/gaussdbjdbc.jar" ]; then
    export JDBC_JAR="$(dirname "${BASH_SOURCE[0]}")/gaussdbjdbc.jar"
else
    export JDBC_JAR="${JDBC_JAR:-$HOME/.m2/repository/com/huaweicloud/gaussdb/gaussdbjdbc/506.0.0.b058-jdk7/gaussdbjdbc-506.0.0.b058-jdk7.jar}"
fi

echo "[env] 配置加载完成"
echo "  SEATA_STORE_DB_URL = ${SEATA_STORE_DB_URL}"
echo "  SPRING_DATASOURCE_USERNAME = ${SPRING_DATASOURCE_USERNAME}"
echo "  SEATA_SERVER_PORT = ${SEATA_SERVER_PORT}"
