import java.sql.*;
public class QuickExec {
    public static void main(String[] args) throws Exception {
        try (Connection c = DriverManager.getConnection(args[0], args[1], args[2]);
             Statement s = c.createStatement()) {
            int n = s.executeUpdate(args[3]);
            System.out.println("rows=" + n);
        }
    }
}
