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

if [ -f "$SCRIPT_DIR/SqlRunner.class" ]; then
    RUNNER_CP="$SCRIPT_DIR:$JDBC_JAR"
else
    echo "[ERROR] 找不到 SqlRunner.class"
    exit 1
fi

run_on_db() {
    local db="$1"; local sql="$2"
    local url="${BASE}/${db}?currentSchema=public&defaultTransactionReadOnly=false"
    java -cp "$RUNNER_CP" SqlRunner "$url" "$GAUSSDB_USER" "$GAUSSDB_PASSWORD" - "$sql"
}

# 获取单个数值
get_val() {
    local db="$1"; local sql="$2"
    local url="${BASE}/${db}?currentSchema=public&defaultTransactionReadOnly=false"
    java -cp "$RUNNER_CP" SqlRunner "$url" "$GAUSSDB_USER" "$GAUSSDB_PASSWORD" - "$sql" | tail -1
}

if [ "$ACTION" = "reset" ]; then
    echo "[check] 重置种子数据..."
    run_on_db "seata_account" "DELETE FROM public.account_tbl WHERE user_id = 'U100001'; INSERT INTO public.account_tbl (user_id, money) VALUES ('U100001', 10000);"
    run_on_db "seata_order"   "DELETE FROM public.order_tbl; DELETE FROM public.undo_log;"
    run_on_db "seata_storage" "DELETE FROM public.stock_tbl WHERE commodity_code = 'C00321'; INSERT INTO public.stock_tbl (commodity_code, count) VALUES ('C00321', 100);"
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

    # 对比
    echo ""
    MONEY=$(get_val "seata_account" "SELECT money FROM public.account_tbl WHERE user_id='U100001'" 2>/dev/null || echo "?")
    ORDERS=$(get_val "seata_order" "SELECT count(*) FROM public.order_tbl" 2>/dev/null || echo "?")
    STOCK=$(get_val "seata_storage" "SELECT count FROM public.stock_tbl WHERE commodity_code='C00321'" 2>/dev/null || echo "?")
    U1=$(get_val "seata_account" "SELECT count(*) FROM public.undo_log" 2>/dev/null || echo "?")
    U2=$(get_val "seata_order" "SELECT count(*) FROM public.undo_log" 2>/dev/null || echo "?")
    U3=$(get_val "seata_storage" "SELECT count(*) FROM public.undo_log" 2>/dev/null || echo "?")

    # 判断
    m_ok="❌"; o_ok="❌"; s_ok="❌"; u_ok="❌"
    [ "$MONEY" = "9600" ] && m_ok="✅"
    [ "$ORDERS" = "1" ] && o_ok="✅"
    [ "$STOCK" = "98" ] && s_ok="✅"
    [ "$U1" = "0" ] && [ "$U2" = "0" ] && [ "$U3" = "0" ] && u_ok="✅"

    echo "┌──────────────┬──────────┬──────────┬──────┐"
    echo "│ 指标          │ 期望     │ 实际     │ 结果  │"
    echo "├──────────────┼──────────┼──────────┼──────┤"
    printf "│ account_tbl  │ %-8s │ %-8s │  %s  │\n" "9600" "$MONEY" "$m_ok"
    printf "│ order_tbl    │ %-8s │ %-8s │  %s  │\n" "1" "$ORDERS" "$o_ok"
    printf "│ stock_tbl    │ %-8s │ %-8s │  %s  │\n" "98" "$STOCK" "$s_ok"
    printf "│ undo_log     │ %-8s │ %-8s │  %s  │\n" "0" "${U1}/${U2}/${U3}" "$u_ok"
    echo "└──────────────┴──────────┴──────────┴──────┘"
fi
