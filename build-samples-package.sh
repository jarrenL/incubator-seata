#!/bin/bash
# ============================================================
# 构建 seata-samples-package-*.tar.gz
# 用法: ./build-samples-package.sh [版本号]
# ============================================================
set -e

VERSION="${1:-2.5.0-gaussdb}"
SAMPLES_DIR="${SAMPLES_DIR:-$HOME/IdeaProjects/incubator-seata-samples}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp}"
PKG_NAME="seata-samples-package-${VERSION}"

echo "=== 1. 编译所有样本（shaded jar，自包含） ==="
cd "$SAMPLES_DIR"

mvn clean package -DskipTests -Dcheckstyle.skip=true \
    -pl at-sample/springboot-seata \
    -pl xa-sample/springboot-feign-seata-xa \
    -pl tcc-sample/spring-dubbo-seata-tcc \
    -pl saga-sample/spring-seata-saga \
    -am

echo "=== 2. 构建目录结构 ==="
PKG_DIR="$OUTPUT_DIR/seata-samples-package"
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR"/jars/{at,xa,tcc,saga}
mkdir -p "$PKG_DIR/bin"

echo "=== 3. 拷贝 jar ==="
cp "$SAMPLES_DIR"/at-sample/springboot-seata/target/springboot-seata-${VERSION}.jar        "$PKG_DIR/jars/at/"
cp "$SAMPLES_DIR"/xa-sample/springboot-feign-seata-xa/springboot-feign-seata-account/target/springboot-feign-seata-account-${VERSION}.jar   "$PKG_DIR/jars/xa/"
cp "$SAMPLES_DIR"/xa-sample/springboot-feign-seata-xa/springboot-feign-seata-storage/target/springboot-feign-seata-storage-${VERSION}.jar   "$PKG_DIR/jars/xa/"
cp "$SAMPLES_DIR"/xa-sample/springboot-feign-seata-xa/springboot-feign-seata-order/target/springboot-feign-seata-order-${VERSION}.jar       "$PKG_DIR/jars/xa/"
cp "$SAMPLES_DIR"/xa-sample/springboot-feign-seata-xa/springboot-feign-seata-business/target/springboot-feign-seata-business-${VERSION}.jar "$PKG_DIR/jars/xa/"
cp "$SAMPLES_DIR"/tcc-sample/spring-dubbo-seata-tcc/spring-dubbo-seata-tcc-provider/target/spring-dubbo-seata-tcc-provider-${VERSION}.jar   "$PKG_DIR/jars/tcc/"
cp "$SAMPLES_DIR"/tcc-sample/spring-dubbo-seata-tcc/spring-dubbo-seata-tcc-consumer/target/spring-dubbo-seata-tcc-consumer-${VERSION}.jar   "$PKG_DIR/jars/tcc/"
cp "$SAMPLES_DIR"/saga-sample/spring-seata-saga/target/spring-seata-saga-${VERSION}.jar  "$PKG_DIR/jars/saga/"

echo "=== 4. 拷贝启动脚本 ==="
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/seata-intranet" ]; then
    cp "$SCRIPT_DIR/seata-intranet"/start-at-sample.sh "$PKG_DIR/bin/start-at.sh"
    cp "$SCRIPT_DIR/seata-intranet"/start-xa-sample.sh "$PKG_DIR/bin/start-xa.sh"
else
    # 脚本模板从 seata-intranet/ 复制（如果存在）
    INTRA_DIR="${INTRA_DIR:-$HOME/IdeaProjects/incubator-seata/seata-intranet}"
    [ -f "$INTRA_DIR/start-at-sample.sh" ] && cp "$INTRA_DIR/start-at-sample.sh" "$PKG_DIR/bin/start-at.sh"
    [ -f "$INTRA_DIR/start-xa-sample.sh" ] && cp "$INTRA_DIR/start-xa-sample.sh" "$PKG_DIR/bin/start-xa.sh"
fi

# 内联写 TCC/Saga/kill-all 脚本（不依赖外部文件）
cat > "$PKG_DIR/bin/start-tcc.sh" << 'TCCEOF'
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROVIDER="$PKG_DIR/jars/tcc/spring-dubbo-seata-tcc-provider-*.jar"
CONSUMER="$PKG_DIR/jars/tcc/spring-dubbo-seata-tcc-consumer-*.jar"
PROVIDER=$(ls $PROVIDER | head -1)
CONSUMER=$(ls $CONSUMER | head -1)
echo "[TCC] 清理 ZK 端口..."
lsof -ti :2181 2>/dev/null | xargs kill -9 2>/dev/null || true; sleep 1
echo "[TCC] 启动 Provider（内嵌 ZK :2181）..."
java -jar "$PROVIDER" > /tmp/seata-tcc-provider.log 2>&1 &
echo "[TCC] 等待 ZK 就绪..."
for i in $(seq 1 30); do
    if echo stat | nc -w 1 127.0.0.1 2181 2>/dev/null | grep -q "Mode"; then
        echo "[TCC] ZK 就绪 (${i}x2s)"; break
    fi
    [ $i -eq 30 ] && echo "[TCC] ZK 未就绪，额外等 10s..." && sleep 10
    sleep 2
done
echo "[TCC] 启动 Consumer..."
java -jar "$CONSUMER" 2>&1 | tee /tmp/seata-tcc-consumer.log
echo ""; [ ${PIPESTATUS[0]} -eq 0 ] && echo "[TCC] 测试通过 ✅" || echo "[TCC] 测试失败 ❌"
kill $(jobs -p) 2>/dev/null || true
TCCEOF

cat > "$PKG_DIR/bin/start-saga.sh" << 'SAGAEOF'
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
JAR=$(ls "$PKG_DIR/jars/saga/"*.jar | head -1)
echo "[Saga] 运行 Saga 事务测试..."
java -jar "$JAR" 2>&1 | tee /tmp/seata-saga.log
echo ""
grep -q "commit succeed" /tmp/seata-saga.log && grep -q "compensate" /tmp/seata-saga.log \
    && echo "[Saga] 测试通过 ✅" || echo "[Saga] 测试失败 ❌"
SAGAEOF

cat > "$PKG_DIR/bin/kill-all.sh" << 'KILLEOF'
#!/bin/bash
for p in 8091 9081 9082 9083 9084 7081 7082 7083 7084 2181 20880; do
    lsof -ti :$p 2>/dev/null | xargs kill -9 2>/dev/null || true
done
echo "所有测试端口已清理"
KILLEOF

chmod +x "$PKG_DIR"/bin/*.sh

echo "=== 5. 打包 ==="
cd "$OUTPUT_DIR"
rm -f "${PKG_NAME}.tar.gz"
tar czf "${PKG_NAME}.tar.gz" seata-samples-package/

echo ""
echo "=== 完成 ==="
ls -lh "${PKG_NAME}.tar.gz"
echo ""
echo "内网部署:"
echo "  tar xzf ${PKG_NAME}.tar.gz -C /opt/"
echo "  source seata-intranet/env.sh centralized"
echo "  /opt/seata-samples-package/bin/start-at.sh commit"
