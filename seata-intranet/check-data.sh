#!/bin/bash
# ============================================================
# 数据验证 & 重置脚本（多库连接，使用 SqlRunner）
# ============================================================
# 用法:
#   source env.sh [centralized|distributed]
#   ./check-data.sh                # 查看当前数据
#   ./check-data.sh reset          # 重置种子数据
#   ./check-data.sh verify-commit  # AT/XA commit 验证（money=9600, 1 order, stock=98）
#   ./check-data.sh verify-rollback # AT/XA rollback 验证（money=10000, 0 order, stock=100）
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

get_val() {
    local db="$1"; local sql="$2"
    local url="${BASE}/${db}?currentSchema=public&defaultTransactionReadOnly=false"
    java -cp "$RUNNER_CP" SqlRunner "$url" "$GAUSSDB_USER" "$GAUSSDB_PASSWORD" - "$sql" 2>/dev/null | tail -1
}

get_undo_all() {
    local a=$(get_val "seata_account" "SELECT count(*) FROM public.undo_log")
    local o=$(get_val "seata_order" "SELECT count(*) FROM public.undo_log")
    local s=$(get_val "seata_storage" "SELECT count(*) FROM public.undo_log")
    echo "${a:-?}/${o:-?}/${s:-?}"
}

print_table() {
    local label="$1" m_exp="$2" o_exp="$3" s_exp="$4"
    local money=$(get_val "seata_account" "SELECT money FROM public.account_tbl WHERE user_id='U100001'")
    local orders=$(get_val "seata_order" "SELECT count(*) FROM public.order_tbl")
    local stock=$(get_val "seata_storage" "SELECT count FROM public.stock_tbl WHERE commodity_code='C00321'")
    local undo=$(get_undo_all)
    local u_exp="0/0/0"

    local m_ok="❌"; [ "${money:-x}" = "$m_exp" ] && m_ok="✅"
    local o_ok="❌"; [ "${orders:-x}" = "$o_exp" ] && o_ok="✅"
    local s_ok="❌"; [ "${stock:-x}" = "$s_exp" ] && s_ok="✅"
    local u_ok="❌"; [ "$undo" = "$u_exp" ] && u_ok="✅"
    local all_ok="❌"
    [ "$m_ok" = "✅" ] && [ "$o_ok" = "✅" ] && [ "$s_ok" = "✅" ] && [ "$u_ok" = "✅" ] && all_ok="✅"

    echo ""
    echo "═══ ${label} ═══"
    echo "┌──────────────┬──────────┬──────────┬──────┐"
    echo "│ 指标          │ 期望     │ 实际     │ 结果  │"
    echo "├──────────────┼──────────┼──────────┼──────┤"
    printf "│ account_tbl  │ %-8s │ %-8s │  %s  │\n" "$m_exp" "${money:-?}" "$m_ok"
    printf "│ order_tbl    │ %-8s │ %-8s │  %s  │\n" "$o_exp" "${orders:-?}" "$o_ok"
    printf "│ stock_tbl    │ %-8s │ %-8s │  %s  │\n" "$s_exp" "${stock:-?}" "$s_ok"
    printf "│ undo_log     │ %-8s │ %-8s │  %s  │\n" "$u_exp" "$undo" "$u_ok"
    echo "└──────────────┴──────────┴──────────┴──────┘"
    echo "  综合: $all_ok"
}

# ─── 主逻辑 ───

if [ "$ACTION" = "reset" ]; then
    echo "[check] 重置种子数据..."
    run_on_db "seata_account" "DELETE FROM public.account_tbl WHERE user_id = 'U100001'; INSERT INTO public.account_tbl (user_id, money) VALUES ('U100001', 10000);"
    run_on_db "seata_order"   "DELETE FROM public.order_tbl; DELETE FROM public.undo_log;"
    run_on_db "seata_storage" "DELETE FROM public.stock_tbl WHERE commodity_code = 'C00321'; INSERT INTO public.stock_tbl (commodity_code, count) VALUES ('C00321', 100);"
    run_on_db "seata_account" "DELETE FROM public.undo_log;"
    echo "[check] 重置完成"

elif [ "$ACTION" = "verify-commit" ]; then
    print_table "AT/XA COMMIT 验证" "9600" "1" "98"

elif [ "$ACTION" = "verify-rollback" ]; then
    print_table "AT/XA ROLLBACK 验证" "10000" "0" "100"

else
    # 默认：显示原始数据
    echo "[check] ========== 当前数据状态 =========="

    echo ""
    echo "── seata_account ──"
    run_on_db "seata_account" "SELECT 'account_tbl:' AS info; SELECT * FROM public.account_tbl WHERE user_id = 'U100001'; SELECT 'undo_log:' AS info; SELECT count(*) FROM public.undo_log;"

    echo ""
    echo "── seata_order ──"
    run_on_db "seata_order" "SELECT 'order_tbl count:' AS info; SELECT count(*) FROM public.order_tbl; SELECT 'undo_log:' AS info; SELECT count(*) FROM public.undo_log;"

    echo ""
    echo "── seata_storage ──"
    run_on_db "seata_storage" "SELECT 'stock_tbl:' AS info; SELECT * FROM public.stock_tbl WHERE commodity_code = 'C00321'; SELECT 'undo_log:' AS info; SELECT count(*) FROM public.undo_log;"

    # 同时显示两种期望供参考
    echo ""
    echo "参考期望:"
    echo "  commit:   money=9600 | orders=1 | stock=98  | undo=0"
    echo "  rollback: money=10000| orders=0 | stock=100 | undo=0"
fi
