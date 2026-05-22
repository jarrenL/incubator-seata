import java.sql.*;
import java.io.*;

/**
 * 通用 GaussDB SQL 执行工具。
 * 用法:
 *   java -cp ".:gaussdbjdbc.jar" SqlRunner <jdbc-url> <user> <pass> <sql-file>
 *   java -cp ".:gaussdbjdbc.jar" SqlRunner <jdbc-url> <user> <pass> - <sql>
 *   第三个参数如果是 "-" 则从第 4 个参数读取 SQL 字符串，否则从第 4 个参数读 SQL 文件。
 */
public class SqlRunner {
    public static void main(String[] args) throws Exception {
        if (args.length < 4) {
            System.err.println("SqlRunner <jdbc-url> <user> <pass> <sql-file | -> [sql-string]");
            System.exit(1);
        }

        String url = args[0];
        String user = args[1];
        String pass = args[2];
        String source = args[3];   // file path or "-"
        String inlineSql = args.length > 4 ? args[4] : null;

        StringBuilder sql = new StringBuilder();
        if ("-".equals(source) && inlineSql != null) {
            sql.append(inlineSql);
        } else {
            try (BufferedReader r = new BufferedReader(new FileReader(source))) {
                String line;
                while ((line = r.readLine()) != null) {
                    String t = line.trim();
                    if (t.isEmpty() || t.startsWith("--")) continue;
                    sql.append(t).append(" ");
                }
            }
        }

        Class.forName("com.huawei.gaussdb.jdbc.Driver");

        String[] stmts = sql.toString().split(";");
        try (Connection c = DriverManager.getConnection(url, user, pass);
             Statement s = c.createStatement()) {

            for (String stmt : stmts) {
                stmt = stmt.trim();
                if (stmt.isEmpty()) continue;

                try {
                    String upper = stmt.toUpperCase();
                    if (upper.startsWith("SELECT") || upper.startsWith("SHOW")) {
                        ResultSet rs = s.executeQuery(stmt);
                        ResultSetMetaData md = rs.getMetaData();
                        int cols = md.getColumnCount();
                        while (rs.next()) {
                            StringBuilder row = new StringBuilder();
                            for (int i = 1; i <= cols; i++) {
                                if (i > 1) row.append(" | ");
                                row.append(rs.getString(i));
                            }
                            System.out.println(row);
                        }
                        rs.close();
                    } else {
                        int rows = s.executeUpdate(stmt);
                        System.out.println("OK (" + rows + " rows)");
                    }
                } catch (SQLException e) {
                    String msg = e.getMessage();
                    if (msg != null && (msg.contains("already exists")
                            || msg.contains("duplicate key"))) {
                        System.out.println("SKIP (exists)");
                    } else {
                        String firstLine = msg != null ? msg.split("\n")[0] : "unknown";
                        System.err.println("FAIL: " + firstLine);
                        // Don't rethrow — continue with remaining statements
                    }
                }
            }
        }
    }
}
