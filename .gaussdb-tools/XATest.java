import java.sql.*;
import javax.sql.*;
import javax.transaction.xa.*;
import java.lang.reflect.*;

public class XATest {
    public static void main(String[] a) throws Exception {
        String url = "jdbc:gaussdb://1.92.120.69:8000/seata_storage?currentSchema=public";
        String user = "root", pass = "GaussDB123";
        Connection c = DriverManager.getConnection(url, user, pass);
        Class<?> cls = Class.forName("com.huawei.gaussdb.jdbc.xa.PGXAConnection");
        Constructor<?> ctor = null;
        for (Constructor<?> k : cls.getConstructors()) { System.out.println("ctor: " + k); }
        for (Constructor<?> k : cls.getDeclaredConstructors()) {
            if (k.getParameterCount() == 1) { ctor = k; ctor.setAccessible(true); break; }
        }
        XAConnection xac = (XAConnection) ctor.newInstance(c.unwrap(Class.forName("com.huawei.gaussdb.jdbc.core.BaseConnection")));
        XAResource xar = xac.getXAResource();
        Xid xid = new Xid() {
            byte[] gtrid = new byte[]{1,2,3,4};
            byte[] bqual = new byte[]{5,6,7,8};
            public int getFormatId(){return 1;}
            public byte[] getGlobalTransactionId(){return gtrid;}
            public byte[] getBranchQualifier(){return bqual;}
        };
        try {
            System.out.println("start...");
            xar.start(xid, XAResource.TMNOFLAGS);
            Connection phys = xac.getConnection();
            try (Statement s = phys.createStatement()) { s.executeUpdate("update stock_tbl set count = count - 1 where commodity_code='C00321'"); }
            System.out.println("end TMSUCCESS...");
            xar.end(xid, XAResource.TMSUCCESS);
            System.out.println("prepare...");
            int p = xar.prepare(xid);
            System.out.println("prepare ret=" + p);
            System.out.println("commit...");
            xar.commit(xid, false);
            System.out.println("DONE OK");
        } catch (XAException xe) {
            System.out.println("XAException errorCode=" + xe.errorCode);
            xe.printStackTrace();
            try { xar.rollback(xid); } catch (Exception ig) {}
        }
    }
}
