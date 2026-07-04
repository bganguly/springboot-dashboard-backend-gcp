package com.dashboard.config;

import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationInfo;
import org.springframework.boot.flyway.autoconfigure.FlywayMigrationStrategy;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class FlywayConfig {

    @Bean
    public FlywayMigrationStrategy resetOnStaleBaseline() {
        return flyway -> {
            // If flyway_schema_history contains only a BASELINE row (no versioned migrations)
            // or nothing at all, the baseline was stamped (or a previous boot failed) without
            // the actual DDL being fully applied through Flyway. Dropping it lets Flyway (or
            // baselineIfDdlPreApplied below) start clean instead of tripping over a
            // table that "already exists, and is empty".
            try (var conn = flyway.getConfiguration().getDataSource().getConnection();
                 var stmt = conn.createStatement()) {
                var rs = stmt.executeQuery(
                        "SELECT COUNT(*) FROM flyway_schema_history WHERE type != 'BASELINE'");
                rs.next();
                if (rs.getInt(1) == 0) {
                    stmt.execute("DROP TABLE flyway_schema_history");
                }
            } catch (Exception ignored) {
                // Table absent (truly fresh DB) — Flyway will initialise it normally.
            }
            baselineIfDdlPreApplied(flyway);
            flyway.migrate();
        };
    }

    // local-dev.sh / prepare-demo-data.sh apply the V*.sql files directly via
    // psql (so seeding can run before the app's first boot). That leaves the
    // schema fully migrated but flyway_schema_history untouched. Baseline at
    // the highest known migration version so migrate() treats those versions
    // as already applied instead of re-running their (non-idempotent) DDL.
    private void baselineIfDdlPreApplied(Flyway flyway) {
        try (var conn = flyway.getConfiguration().getDataSource().getConnection();
             var stmt = conn.createStatement()) {
            stmt.executeQuery("SELECT 1 FROM \"orders\" LIMIT 1");
        } catch (Exception e) {
            return; // no pre-existing schema — let migrate() build it from scratch
        }

        MigrationInfo[] all = flyway.info().all();
        if (all.length == 0) return;
        var latest = all[all.length - 1].getVersion();

        Flyway.configure()
                .configuration(flyway.getConfiguration())
                .baselineVersion(latest)
                .baselineDescription("pre-applied outside Flyway")
                .load()
                .baseline();
    }
}
