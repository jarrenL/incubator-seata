import java.io.*;
import java.nio.file.*;
import java.sql.*;
import java.util.*;

/**
 * Minimal DDL bootstrapper for GaussDB centralized edition.
 * Usage:
 *   java -cp gaussdbjdbc.jar GaussDbDdlRunner <jdbcUrl> <user> <pass> <sqlFile> [sqlFile ...]
 */
public class GaussDbDdlRunner {
    public static void main(String[] args) throws Exception {
        if (args.length < 4) {
            System.err.println("Usage: GaussDbDdlRunner <jdbcUrl> <user> <pass> <sqlFile> [sqlFile ...]");
            System.exit(2);
        }
        String url  = args[0];
        String user = args[1];
        String pass = args[2];

        Class.forName("com.huawei.gaussdb.jdbc.Driver");
        try (Connection conn = DriverManager.getConnection(url, user, pass)) {
            conn.setAutoCommit(true);
            System.out.println("[OK] connected. product=" + conn.getMetaData().getDatabaseProductName()
                    + " version=" + conn.getMetaData().getDatabaseProductVersion());
            for (int i = 3; i < args.length; i++) {
                runFile(conn, Paths.get(args[i]));
            }
        }
    }

    private static void runFile(Connection conn, Path path) throws Exception {
        System.out.println("\n===== Executing: " + path + " =====");
        String body = new String(Files.readAllBytes(path), "UTF-8");
        StringBuilder buf = new StringBuilder();
        for (String line : body.split("\n")) {
            String trimmed = line.trim();
            if (trimmed.startsWith("--") || trimmed.isEmpty()) continue;
            buf.append(line).append('\n');
        }
        String[] stmts = buf.toString().split(";\\s*(?:\\r?\\n|$)");
        try (Statement st = conn.createStatement()) {
            int idx = 0;
            for (String raw : stmts) {
                String sql = raw.trim();
                if (sql.isEmpty()) continue;
                idx++;
                try {
                    st.execute(sql);
                    System.out.println("  [" + idx + "] OK: " + first(sql));
                } catch (SQLException e) {
                    String msg = e.getMessage() == null ? "" : e.getMessage();
                    if (msg.toLowerCase().contains("already exists")
                        || msg.toLowerCase().contains("duplicate")) {
                        System.out.println("  [" + idx + "] SKIP (exists): " + first(sql));
                    } else {
                        System.out.println("  [" + idx + "] FAIL: " + first(sql));
                        System.out.println("         " + msg);
                        throw e;
                    }
                }
            }
        }
    }

    private static String first(String s) {
        s = s.replaceAll("\\s+", " ");
        return s.length() > 100 ? s.substring(0, 100) + "..." : s;
    }
}
