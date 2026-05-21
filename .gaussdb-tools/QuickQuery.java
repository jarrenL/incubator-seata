import java.sql.*;

public class QuickQuery {
    public static void main(String[] args) throws Exception {
        String url = args[0], user = args[1], pass = args[2], sql = args[3];
        try (Connection c = DriverManager.getConnection(url, user, pass);
             Statement s = c.createStatement();
             ResultSet r = s.executeQuery(sql)) {
            int cols = r.getMetaData().getColumnCount();
            StringBuilder sb = new StringBuilder();
            for (int i = 1; i <= cols; i++) sb.append(i > 1 ? "\t" : "").append(r.getMetaData().getColumnLabel(i));
            System.out.println(sb);
            while (r.next()) {
                sb.setLength(0);
                for (int i = 1; i <= cols; i++) sb.append(i > 1 ? "\t" : "").append(r.getString(i));
                System.out.println(sb);
            }
        }
    }
}
