#!/bin/bash
# ============================================================
# 数据验证 & 重置脚本（多库连接，使用 SqlRunner）
# ============================================================
# 用法:
#   source env.sh [centralized|distributed]
#   ./check-data.sh            # 查看当前数据
#   ./check-data.sh reset      # 重置种子数据
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$GAUSSDB_HOST" ]; then
    echo "[ERROR] 请先 source env.sh"
    exit 1
fi

ACTION="${1:-show}"
BASE="jdbc:gaussdb://${GAUSSDB_HOST}:${GAUSSDB_PORT}"

# SqlRunner classpath
if [ -f "$SCRIPT_DIR/SqlRunner.class" ]; then
    RUNNER_CP="$SCRIPT_DIR:$JDBC_JAR"
else
    echo "[ERROR] 找不到 SqlRunner.class"
    exit 1
fi

# 对指定数据库执行 SQL
run_on_db() {
    local db="$1"; local sql="$2"
    local url="${BASE}/${db}?currentSchema=public"
    java -cp "$RUNNER_CP" SqlRunner "$url" "$GAUSSDB_USER" "$GAUSSDB_PASSWORD" - "$sql"
}

if [ "$ACTION" = "reset" ]; then
    echo "[check] 重置种子数据..."
    run_on_db "seata_account" "DELETE FROM public.account_tbl WHERE user_id = 'U100001'; INSERT INTO public.account_tbl (user_id, money) VALUES ('U100001', 10000);"
    run_on_db "seata_order"   "DELETE FROM public.order_tbl; DELETE FROM public.undo_log;"
    run_on_db "seata_storage" "DELETE FROM public.stock_tbl WHERE commodity_code = 'C00321'; INSERT INTO public.stock_tbl (commodity_code, count) VALUES ('C00321', 100);"
    # 清理 account 库的 undo_log
    run_on_db "seata_account" "DELETE FROM public.undo_log;"
    echo "[check] 重置完成"
else
    echo "[check] ========== 当前数据状态 =========="

    echo ""
    echo "── seata_account ──"
    run_on_db "seata_account" "SELECT 'account_tbl:' AS info; SELECT * FROM public.account_tbl WHERE user_id = 'U100001'; SELECT 'undo_log count:' AS info; SELECT count(*) FROM public.undo_log;"

    echo ""
    echo "── seata_order ──"
    run_on_db "seata_order" "SELECT 'order_tbl count:' AS info; SELECT count(*) FROM public.order_tbl; SELECT 'undo_log count:' AS info; SELECT count(*) FROM public.undo_log;"

    echo ""
    echo "── seata_storage ──"
    run_on_db "seata_storage" "SELECT 'stock_tbl:' AS info; SELECT * FROM public.stock_tbl WHERE commodity_code = 'C00321'; SELECT 'undo_log count:' AS info; SELECT count(*) FROM public.undo_log;"

    echo ""
    echo "┌──────────────────────────────────────┐"
    echo "│  AT commit 期望:                      │"
    echo "│  account_tbl: money=9200 (-800)       │"
    echo "│  order_tbl:   2 rows                  │"
    echo "│  stock_tbl:   count=96 (-4)           │"
    echo "│  undo_log:    全部为 0                │"
    echo "└──────────────────────────────────────┘"
fi
