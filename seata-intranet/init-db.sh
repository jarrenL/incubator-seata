#!/bin/bash
# ============================================================
# GaussDB 数据库初始化脚本（使用 SqlRunner）
# ============================================================
# 用法:
#   source env.sh [centralized|distributed]
#   ./init-db.sh [all|server|business|fix-seq]
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$GAUSSDB_HOST" ]; then
    echo "[ERROR] 请先 source env.sh [centralized|distributed]"
    exit 1
fi

TARGET="${1:-all}"
DB_URL="jdbc:gaussdb://${GAUSSDB_HOST}:${GAUSSDB_PORT}/postgres?currentSchema=public"
DB_USER="${GAUSSDB_USER}"
DB_PASS="${GAUSSDB_PASSWORD}"

# SqlRunner classpath
if [ -f "$SCRIPT_DIR/SqlRunner.class" ]; then
    RUNNER_CP="$SCRIPT_DIR:$JDBC_JAR"
else
    echo "[ERROR] 找不到 SqlRunner.class，请先编译: cd $SCRIPT_DIR && javac -cp gaussdbjdbc.jar SqlRunner.java"
    exit 1
fi

echo "[init] 目标: ${GAUSSDB_HOST}:${GAUSSDB_PORT}"
echo "[init] 用户: ${DB_USER}"
echo "[init] JDBC:  ${JDBC_JAR}"
echo "[init] 操作: ${TARGET}"

# ─── 生成 SQL 文件 ───
SQL_DIR="/tmp/seata-db-init-$$"
mkdir -p "$SQL_DIR"

run_sql_file() {
    local desc="$1"; local sql_file="$2"
    echo "  → ${desc}..."
    java -cp "$RUNNER_CP" SqlRunner "$DB_URL" "$DB_USER" "$DB_PASS" "$sql_file"
    echo "  ✓ 完成"
}

# ─── Seata Server 元数据表 ───
generate_server_sql() {
    cat > "$SQL_DIR/01_server_tables.sql" << 'SQLEOF'
CREATE TABLE IF NOT EXISTS public.global_table (
    xid VARCHAR(128) NOT NULL, transaction_id BIGINT, status SMALLINT NOT NULL,
    application_id VARCHAR(32), transaction_service_group VARCHAR(32),
    transaction_name VARCHAR(128), timeout INT, begin_time BIGINT,
    application_data VARCHAR(2000), gmt_create TIMESTAMP(0), gmt_modified TIMESTAMP(0),
    CONSTRAINT pk_global_table PRIMARY KEY (xid)
);
CREATE INDEX IF NOT EXISTS idx_global_table_status_gmt_modified ON public.global_table (status, gmt_modified);
CREATE INDEX IF NOT EXISTS idx_global_table_transaction_id ON public.global_table (transaction_id);

CREATE TABLE IF NOT EXISTS public.branch_table (
    branch_id BIGINT NOT NULL, xid VARCHAR(128) NOT NULL, transaction_id BIGINT,
    resource_group_id VARCHAR(32), resource_id VARCHAR(256), branch_type VARCHAR(32),
    status SMALLINT, client_id VARCHAR(64), application_data VARCHAR(2000),
    gmt_create TIMESTAMP(6), gmt_modified TIMESTAMP(6),
    CONSTRAINT pk_branch_table PRIMARY KEY (branch_id)
);
CREATE INDEX IF NOT EXISTS idx_branch_table_xid ON public.branch_table (xid);

CREATE TABLE IF NOT EXISTS public.lock_table (
    row_key VARCHAR(128) NOT NULL, xid VARCHAR(128), transaction_id BIGINT,
    branch_id BIGINT NOT NULL, resource_id VARCHAR(256), table_name VARCHAR(32),
    pk VARCHAR(36), status SMALLINT NOT NULL DEFAULT 0,
    gmt_create TIMESTAMP(0), gmt_modified TIMESTAMP(0),
    CONSTRAINT pk_lock_table PRIMARY KEY (row_key)
);
CREATE INDEX IF NOT EXISTS idx_lock_table_branch_id ON public.lock_table (branch_id);
CREATE INDEX IF NOT EXISTS idx_lock_table_xid ON public.lock_table (xid);
CREATE INDEX IF NOT EXISTS idx_lock_table_status ON public.lock_table (status);

CREATE TABLE IF NOT EXISTS public.distributed_lock (
    lock_key VARCHAR(20) NOT NULL, lock_value VARCHAR(20) NOT NULL,
    expire BIGINT NOT NULL, CONSTRAINT pk_distributed_lock_table PRIMARY KEY (lock_key)
);
INSERT INTO public.distributed_lock (lock_key, lock_value, expire)
    SELECT 'AsyncCommitting', ' ', 0 WHERE NOT EXISTS (SELECT 1 FROM public.distributed_lock WHERE lock_key = 'AsyncCommitting');
INSERT INTO public.distributed_lock (lock_key, lock_value, expire)
    SELECT 'RetryCommitting', ' ', 0 WHERE NOT EXISTS (SELECT 1 FROM public.distributed_lock WHERE lock_key = 'RetryCommitting');
INSERT INTO public.distributed_lock (lock_key, lock_value, expire)
    SELECT 'RetryRollbacking', ' ', 0 WHERE NOT EXISTS (SELECT 1 FROM public.distributed_lock WHERE lock_key = 'RetryRollbacking');
INSERT INTO public.distributed_lock (lock_key, lock_value, expire)
    SELECT 'TxTimeoutCheck', ' ', 0 WHERE NOT EXISTS (SELECT 1 FROM public.distributed_lock WHERE lock_key = 'TxTimeoutCheck');

CREATE TABLE IF NOT EXISTS public.vgroup_table (
    vGroup VARCHAR(255), namespace VARCHAR(255), cluster VARCHAR(255), PRIMARY KEY (vGroup)
);
SQLEOF
}

# ─── 业务库表 ───
generate_business_sql() {
    # 注意：跨库 DDL 在 PostgreSQL/GaussDB 中不支持。
    # 改为分别连接每个数据库执行。
    cat > "$SQL_DIR/02_account.sql" << 'SQLEOF'
CREATE TABLE IF NOT EXISTS public.account_tbl (
    id SERIAL PRIMARY KEY, user_id VARCHAR(255) UNIQUE, money INT DEFAULT 0
);
CREATE TABLE IF NOT EXISTS public.undo_log (
    id SERIAL PRIMARY KEY, branch_id BIGINT NOT NULL, xid VARCHAR(100) NOT NULL,
    context VARCHAR(128) NOT NULL, rollback_info BYTEA NOT NULL,
    log_status INT NOT NULL, log_created TIMESTAMP NOT NULL, log_modified TIMESTAMP NOT NULL,
    CONSTRAINT ux_undo_log UNIQUE (xid, branch_id)
);
DELETE FROM public.account_tbl WHERE user_id = 'U100001';
INSERT INTO public.account_tbl (user_id, money) VALUES ('U100001', 10000);
SQLEOF

    cat > "$SQL_DIR/02_order.sql" << 'SQLEOF'
CREATE TABLE IF NOT EXISTS public.order_tbl (
    id SERIAL PRIMARY KEY, user_id VARCHAR(255), commodity_code VARCHAR(255),
    count INT DEFAULT 0, money INT DEFAULT 0
);
CREATE TABLE IF NOT EXISTS public.undo_log (
    id SERIAL PRIMARY KEY, branch_id BIGINT NOT NULL, xid VARCHAR(100) NOT NULL,
    context VARCHAR(128) NOT NULL, rollback_info BYTEA NOT NULL,
    log_status INT NOT NULL, log_created TIMESTAMP NOT NULL, log_modified TIMESTAMP NOT NULL,
    CONSTRAINT ux_undo_log UNIQUE (xid, branch_id)
);
SQLEOF

    cat > "$SQL_DIR/02_storage.sql" << 'SQLEOF'
CREATE TABLE IF NOT EXISTS public.stock_tbl (
    id SERIAL PRIMARY KEY, commodity_code VARCHAR(255) UNIQUE, count INT DEFAULT 0
);
CREATE TABLE IF NOT EXISTS public.undo_log (
    id SERIAL PRIMARY KEY, branch_id BIGINT NOT NULL, xid VARCHAR(100) NOT NULL,
    context VARCHAR(128) NOT NULL, rollback_info BYTEA NOT NULL,
    log_status INT NOT NULL, log_created TIMESTAMP NOT NULL, log_modified TIMESTAMP NOT NULL,
    CONSTRAINT ux_undo_log UNIQUE (xid, branch_id)
);
DELETE FROM public.stock_tbl WHERE commodity_code = 'C00321';
INSERT INTO public.stock_tbl (commodity_code, count) VALUES ('C00321', 100);
SQLEOF
}

# 对指定数据库执行 SQL 文件
run_sql_on_db() {
    local desc="$1"; local db="$2"; local sql_file="$3"
    local db_url="jdbc:gaussdb://${GAUSSDB_HOST}:${GAUSSDB_PORT}/${db}?currentSchema=public"
    echo "  → ${desc} (库: ${db})..."
    java -cp "$RUNNER_CP" SqlRunner "$db_url" "$DB_USER" "$DB_PASS" "$sql_file"
    echo "  ✓ 完成"
}

# ─── 主流程 ───
echo "[init] ========== 数据库初始化 =========="

if [ "$TARGET" = "all" ] || [ "$TARGET" = "server" ]; then
    generate_server_sql
    run_sql_file "Seata Server 元数据表" "$SQL_DIR/01_server_tables.sql"
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "business" ]; then
    generate_business_sql
    # 先创建数据库（从 postgres 库执行）
    echo "  → 创建数据库..."
    java -cp "$RUNNER_CP" SqlRunner "$DB_URL" "$DB_USER" "$DB_PASS" - \
        "CREATE DATABASE seata_account; CREATE DATABASE seata_order; CREATE DATABASE seata_storage;" \
        2>/dev/null || true  # 忽略"already exists"错误
    run_sql_on_db "seata_account" "seata_account" "$SQL_DIR/02_account.sql"
    run_sql_on_db "seata_order"   "seata_order"   "$SQL_DIR/02_order.sql"
    run_sql_on_db "seata_storage" "seata_storage" "$SQL_DIR/02_storage.sql"
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "fix-seq" ]; then
    echo ""
    echo "  ⚠️  分布式 GaussDB: 请手动修复 undo_log 序列（见测试方案 5.3）"
fi

echo ""
echo "[init] ========== 初始化完成 =========="
