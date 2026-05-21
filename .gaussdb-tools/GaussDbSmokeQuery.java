import java.sql.*;

/**
 * Smoke-query tool: prints distributed_lock / global_table / branch_table / lock_table contents.
 * Used to verify Seata Server is actually interacting with GaussDB after startup.
 */
public class GaussDbSmokeQuery {
    public static void main(String[] args) throws Exception {
        String url  = args[0];
        String user = args[1];
        String pass = args[2];

        Class.forName("com.huawei.gaussdb.jdbc.Driver");
        try (Connection conn = DriverManager.getConnection(url, user, pass);
             Statement  st   = conn.createStatement()) {

            System.out.println("== distributed_lock ==");
            try (ResultSet rs = st.executeQuery(
                    "SELECT lock_key, lock_value, expire FROM public.distributed_lock ORDER BY lock_key")) {
                while (rs.next()) {
                    System.out.printf("  %-20s lock_value=[%s] expire=%d%n",
                            rs.getString(1), rs.getString(2), rs.getLong(3));
                }
            }

            for (String t : new String[]{"global_table", "branch_table", "lock_table", "vgroup_table"}) {
                try (ResultSet rs = st.executeQuery("SELECT COUNT(*) FROM public." + t)) {
                    if (rs.next()) {
                        System.out.printf("%-16s rows = %d%n", t, rs.getLong(1));
                    }
                }
            }
        }
    }
}
