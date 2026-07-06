package com.dashboard.config;

import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.configuration.Configuration;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.Mockito.*;

class FlywayConfigTest {

    private Flyway flyway;
    private Statement stmt;

    @BeforeEach
    void setUp() throws Exception {
        flyway = mock(Flyway.class);
        Configuration config = mock(Configuration.class);
        DataSource dataSource = mock(DataSource.class);
        Connection conn = mock(Connection.class);
        stmt = mock(Statement.class);
        when(flyway.getConfiguration()).thenReturn(config);
        when(config.getDataSource()).thenReturn(dataSource);
        when(dataSource.getConnection()).thenReturn(conn);
        when(conn.createStatement()).thenReturn(stmt);
    }

    private ResultSet countResult(int count) throws SQLException {
        ResultSet rs = mock(ResultSet.class);
        when(rs.next()).thenReturn(true);
        when(rs.getInt(1)).thenReturn(count);
        return rs;
    }

    @Test
    void staleBaseline_clearsHistoryThenMigrates() throws Exception {
        ResultSet rs = countResult(0);
        when(stmt.executeQuery(anyString())).thenReturn(rs);
        when(stmt.executeQuery(contains("orders"))).thenThrow(new SQLException("relation \"orders\" does not exist"));

        new FlywayConfig().resetOnStaleBaseline().migrate(flyway);

        verify(stmt).execute(contains("DROP TABLE flyway_schema_history"));
        verify(flyway).migrate();
    }

    @Test
    void versionedMigrationsPresent_leavesHistoryAlone() throws Exception {
        ResultSet rs = countResult(3);
        when(stmt.executeQuery(anyString())).thenReturn(rs);
        when(stmt.executeQuery(contains("orders"))).thenThrow(new SQLException("relation \"orders\" does not exist"));

        new FlywayConfig().resetOnStaleBaseline().migrate(flyway);

        verify(stmt, never()).execute(anyString());
        verify(flyway).migrate();
    }

    @Test
    void realHistoryAndPreexistingSchema_neverAttemptsBaseline() throws Exception {
        // Regression: a database already fully managed by Flyway (e.g. prod)
        // has both real history AND a pre-existing "orders" table. Baseline
        // must never be attempted here — Flyway's baseline() refuses to run
        // against a schema history that already has real migrations, which
        // previously crashed the app on boot against an already-healthy DB.
        ResultSet rs = countResult(3);
        when(stmt.executeQuery(anyString())).thenReturn(rs);

        new FlywayConfig().resetOnStaleBaseline().migrate(flyway);

        verify(stmt, never()).execute(anyString());
        verify(flyway, never()).info();
        verify(flyway).migrate();
    }

    @Test
    void missingHistoryTable_stillMigrates() throws Exception {
        when(stmt.executeQuery(anyString())).thenThrow(new SQLException("relation does not exist"));

        new FlywayConfig().resetOnStaleBaseline().migrate(flyway);

        verify(flyway).migrate();
    }
}
