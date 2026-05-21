package org.apache.seata.gaussdb;

import com.alibaba.druid.pool.DruidDataSource;
import org.apache.seata.core.context.RootContext;
import org.apache.seata.core.model.BranchType;
import org.apache.seata.core.model.GlobalStatus;
import org.apache.seata.core.model.TransactionManager;
import org.apache.seata.rm.DefaultResourceManager;
import org.apache.seata.rm.RMClient;
import org.apache.seata.rm.datasource.DataSourceProxy;
import org.apache.seata.rm.datasource.xa.DataSourceProxyXA;
import org.apache.seata.rm.tcc.TCCResource;
import org.apache.seata.rm.tcc.api.BusinessActionContext;
import org.apache.seata.saga.engine.StateMachineEngine;
import org.apache.seata.saga.engine.StateMachineInstance;
import org.apache.seata.tm.DefaultTransactionManager;
import org.apache.seata.tm.TMClient;
import org.apache.seata.tm.api.TransactionalExecutor;
import org.apache.seata.tm.api.TransactionalTemplate;
import org.apache.seata.tm.api.transaction.TransactionInfo;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.context.support.ClassPathXmlApplicationContext;

import java.lang.reflect.Method;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.HashMap;
import java.util.concurrent.atomic.AtomicInteger;

class GaussDbModeVerifierTest {

    private static final String APPLICATION_ID = "gaussdb_mode_verifier";
    private static final String TX_SERVICE_GROUP = "default_tx_group";
    private static final String JDBC_URL = "jdbc:gaussdb://1.92.120.69:8000/postgres?currentSchema=public";
    private static final String USER = "root";
    private static final String PASSWORD = "GaussDB123";

    private static DruidDataSource dataSource;

    @BeforeAll
    static void setup() throws Exception {
        TMClient.init(APPLICATION_ID, TX_SERVICE_GROUP);
        RMClient.init(APPLICATION_ID, TX_SERVICE_GROUP);
        dataSource = new DruidDataSource();
        dataSource.setDriverClassName("com.huawei.gaussdb.jdbc.Driver");
        dataSource.setUrl(JDBC_URL);
        dataSource.setUsername(USER);
        dataSource.setPassword(PASSWORD);
        dataSource.setInitialSize(1);
        dataSource.setMinIdle(1);
        dataSource.setMaxActive(8);
        dataSource.setValidationQuery("SELECT 1");
        dataSource.init();
        resetBusinessTables();
    }

    @AfterAll
    static void teardown() {
        RootContext.unbind();
        if (dataSource != null) {
            dataSource.close();
        }
    }

    @Test
    void verifyAtXaTccAndSagaAgainstGaussDb() throws Throwable {
        verifyAtRollback();
        verifyXaCommitAndRollback();
        verifyTccCommitAndRollback();
        verifySagaStateMachine();
    }

    private static void verifyAtRollback() throws Throwable {
        DataSourceProxy proxy = new DataSourceProxy(dataSource);
        TransactionalTemplate template = new TransactionalTemplate();
        try {
            template.execute(new TransactionalExecutor() {
                @Override
                public Object execute() throws Throwable {
                    try (Connection connection = proxy.getConnection();
                            PreparedStatement ps = connection.prepareStatement(
                                    "UPDATE seata_codex_account SET balance = balance - 100 WHERE id = 1")) {
                        ps.executeUpdate();
                    }
                    throw new ExpectedRollbackException();
                }

                @Override
                public TransactionInfo getTransactionInfo() {
                    TransactionInfo info = new TransactionInfo();
                    info.setName("gaussdb-at-rollback");
                    info.setTimeOut(60000);
                    return info;
                }
            });
            Assertions.fail("AT transaction should roll back");
        } catch (TransactionalExecutor.ExecutionException ex) {
            Assertions.assertEquals(TransactionalExecutor.Code.RollbackDone, ex.getCode());
        }
        Assertions.assertEquals(1000, queryBalance(1), "AT rollback should restore the row");
    }

    private static void verifyXaCommitAndRollback() throws Throwable {
        DataSourceProxyXA xaProxy = new DataSourceProxyXA(dataSource);
        TransactionalTemplate template = new TransactionalTemplate();
        template.execute(new TransactionalExecutor() {
            @Override
            public Object execute() throws Throwable {
                try (Connection connection = xaProxy.getConnection();
                        PreparedStatement ps = connection.prepareStatement(
                                "UPDATE seata_codex_account SET balance = balance + 10 WHERE id = 1")) {
                    connection.setAutoCommit(false);
                    ps.executeUpdate();
                    connection.commit();
                }
                return null;
            }

            @Override
            public TransactionInfo getTransactionInfo() {
                TransactionInfo info = new TransactionInfo();
                info.setName("gaussdb-xa-commit");
                info.setTimeOut(60000);
                return info;
            }
        });
        Assertions.assertEquals(1010, queryBalance(1), "XA commit should persist the row");

        try {
            template.execute(new TransactionalExecutor() {
                @Override
                public Object execute() throws Throwable {
                    try (Connection connection = xaProxy.getConnection();
                            PreparedStatement ps = connection.prepareStatement(
                                    "UPDATE seata_codex_account SET balance = balance + 90 WHERE id = 1")) {
                        connection.setAutoCommit(false);
                        ps.executeUpdate();
                        connection.commit();
                    }
                    throw new ExpectedRollbackException();
                }

                @Override
                public TransactionInfo getTransactionInfo() {
                    TransactionInfo info = new TransactionInfo();
                    info.setName("gaussdb-xa-rollback");
                    info.setTimeOut(60000);
                    return info;
                }
            });
            Assertions.fail("XA transaction should roll back");
        } catch (TransactionalExecutor.ExecutionException ex) {
            Assertions.assertEquals(TransactionalExecutor.Code.RollbackDone, ex.getCode());
        }
        Assertions.assertEquals(1010, queryBalance(1), "XA rollback should restore the row");
    }

    private static void verifyTccCommitAndRollback() throws Exception {
        TccCounterAction action = new TccCounterAction();
        registerTccResource("gaussdb-tcc-action", action);
        TransactionManager tm = new DefaultTransactionManager();

        String commitXid = tm.begin(APPLICATION_ID, TX_SERVICE_GROUP, "gaussdb-tcc-commit", 60000);
        DefaultResourceManager.get()
                .branchRegister(BranchType.TCC, "gaussdb-tcc-action", null, commitXid, "{\"mode\":\"commit\"}", "1");
        Assertions.assertEquals(GlobalStatus.Committed, tm.commit(commitXid));
        waitUntil(() -> action.commits.get() == 1);

        String rollbackXid = tm.begin(APPLICATION_ID, TX_SERVICE_GROUP, "gaussdb-tcc-rollback", 60000);
        DefaultResourceManager.get()
                .branchRegister(
                        BranchType.TCC, "gaussdb-tcc-action", null, rollbackXid, "{\"mode\":\"rollback\"}", "2");
        Assertions.assertEquals(GlobalStatus.Rollbacked, tm.rollback(rollbackXid));
        waitUntil(() -> action.rollbacks.get() == 1);
    }

    private static void verifySagaStateMachine() {
        cleanupSagaTables();
        try (ClassPathXmlApplicationContext context =
                new ClassPathXmlApplicationContext("saga/spring/statemachine_engine_gaussdb_test.xml")) {
            StateMachineEngine engine = context.getBean("stateMachineEngine", StateMachineEngine.class);
            StateMachineInstance instance = engine.start("simpleTestStateMachine", null, new HashMap<>());
            Assertions.assertEquals("SU", instance.getStatus().name(), "Saga state machine should succeed");
            Assertions.assertTrue(countRows("seata_state_machine_inst") > 0, "Saga instance should be persisted");
            Assertions.assertTrue(countRows("seata_state_inst") > 0, "Saga states should be persisted");
        }
    }

    private static void registerTccResource(String actionName, TccCounterAction action) throws Exception {
        TCCResource resource = new TCCResource();
        resource.setActionName(actionName);
        resource.setTargetBean(action);
        Method prepare = TccCounterAction.class.getDeclaredMethod("prepare");
        Method commit = TccCounterAction.class.getDeclaredMethod("commit", BusinessActionContext.class);
        Method rollback = TccCounterAction.class.getDeclaredMethod("rollback", BusinessActionContext.class);
        resource.setPrepareMethod(prepare);
        resource.setCommitMethod(commit);
        resource.setRollbackMethod(rollback);
        resource.setCommitMethodName("commit");
        resource.setRollbackMethodName("rollback");
        resource.setCommitArgsClasses(new Class<?>[] {BusinessActionContext.class});
        resource.setRollbackArgsClasses(new Class<?>[] {BusinessActionContext.class});
        resource.setPhaseTwoCommitKeys(new String[] {"ctx"});
        resource.setPhaseTwoRollbackKeys(new String[] {"ctx"});
        DefaultResourceManager.get().registerResource(resource);
    }

    private static void resetBusinessTables() throws Exception {
        try (Connection connection = dataSource.getConnection();
                Statement st = connection.createStatement()) {
            st.execute("CREATE TABLE IF NOT EXISTS seata_codex_account (id INT PRIMARY KEY, balance INT NOT NULL)");
            st.executeUpdate("DELETE FROM seata_codex_account");
            st.executeUpdate("INSERT INTO seata_codex_account (id, balance) VALUES (1, 1000)");
            st.executeUpdate("DELETE FROM undo_log");
        }
    }

    private static void cleanupSagaTables() {
        executeUpdate("DELETE FROM seata_state_inst");
        executeUpdate("DELETE FROM seata_state_machine_inst");
        executeUpdate("DELETE FROM seata_state_machine_def");
    }

    private static int queryBalance(int id) throws Exception {
        try (Connection connection = dataSource.getConnection();
                PreparedStatement ps =
                        connection.prepareStatement("SELECT balance FROM seata_codex_account WHERE id = ?")) {
            ps.setInt(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                Assertions.assertTrue(rs.next());
                return rs.getInt(1);
            }
        }
    }

    private static int countRows(String table) {
        try (Connection connection = dataSource.getConnection();
                Statement st = connection.createStatement();
                ResultSet rs = st.executeQuery("SELECT COUNT(*) FROM " + table)) {
            rs.next();
            return rs.getInt(1);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private static void executeUpdate(String sql) {
        try (Connection connection = dataSource.getConnection();
                Statement st = connection.createStatement()) {
            st.executeUpdate(sql);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private static void waitUntil(CheckedBoolean condition) throws Exception {
        long deadline = System.currentTimeMillis() + 10000;
        while (System.currentTimeMillis() < deadline) {
            if (condition.get()) {
                return;
            }
            Thread.sleep(100);
        }
        Assertions.fail("condition was not met before timeout");
    }

    private interface CheckedBoolean {
        boolean get() throws Exception;
    }

    public static class TccCounterAction {
        final AtomicInteger commits = new AtomicInteger();
        final AtomicInteger rollbacks = new AtomicInteger();

        public boolean prepare() {
            return true;
        }

        public boolean commit(BusinessActionContext context) {
            commits.incrementAndGet();
            return true;
        }

        public boolean rollback(BusinessActionContext context) {
            rollbacks.incrementAndGet();
            return true;
        }
    }

    private static class ExpectedRollbackException extends Exception {}
}
