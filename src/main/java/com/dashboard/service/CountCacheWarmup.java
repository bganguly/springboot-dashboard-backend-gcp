package com.dashboard.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/**
 * After startup, pre-warms count_cache with exact ILIKE counts for the
 * first/last name tokens of customers visible on the first two pages of the
 * default home view (40 most-recent orders by placedAt DESC). Runs on a
 * virtual thread so it never blocks startup.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class CountCacheWarmup implements ApplicationRunner {

    private final NamedParameterJdbcTemplate jdbc;

    @Override
    public void run(ApplicationArguments args) {
        Thread.ofVirtual().name("count-cache-warmup").start(this::warmup);
    }

    // Matches Chart.tsx defaultRange() — "2020-01-01" to today.
    private static final String DEFAULT_FROM = "2020-01-01";

    private void warmup() {
        try {
            String defaultTo = LocalDate.now().toString();

            List<Map<String, Object>> rows = jdbc.queryForList(
                "WITH recent AS (" +
                "  SELECT c.\"firstName\", c.\"lastName\" " +
                "  FROM orders o JOIN customers c ON c.id = o.\"customerId\" " +
                "  ORDER BY o.\"placedAt\" DESC LIMIT 40" +
                ") SELECT DISTINCT \"firstName\", \"lastName\" FROM recent",
                new MapSqlParameterSource());

            Set<String> tokens = new LinkedHashSet<>();
            for (Map<String, Object> row : rows) {
                String first = (String) row.get("firstName");
                String last  = (String) row.get("lastName");
                if (first != null && !first.isBlank()) tokens.add(first.strip().toLowerCase());
                if (last  != null && !last.isBlank())  tokens.add(last.strip().toLowerCase());
            }

            log.info("CountCacheWarmup: pre-warming {} tokens from first-page customers", tokens.size());

            for (String token : tokens) {
                // Key must match buildCountCacheKey with the UI's default date range.
                String key = "q=" + token + "&status=&regionCode=" +
                             "&from=" + DEFAULT_FROM + "&to=" + defaultTo +
                             "&minTotal=&maxTotal=";

                List<Long> hit = jdbc.queryForList(
                    "SELECT total FROM count_cache WHERE cache_key = :k " +
                    "AND cached_at > NOW() - INTERVAL '30 days'",
                    new MapSqlParameterSource("k", key), Long.class);
                if (!hit.isEmpty()) continue;

                long count = Objects.requireNonNull(jdbc.queryForObject(
                    "SELECT COUNT(*) FROM orders o " +
                    "WHERE o.\"placedAt\" >= :from::timestamptz " +
                    "AND o.\"placedAt\" <= (:to::date + interval '1 day' - interval '1 second') " +
                    "AND o.search_text ILIKE :q",
                    new MapSqlParameterSource("q", "%" + token + "%")
                        .addValue("from", DEFAULT_FROM)
                        .addValue("to", defaultTo), Long.class));

                jdbc.update(
                    "INSERT INTO count_cache (cache_key, total, cached_at) VALUES (:k, :t, NOW()) " +
                    "ON CONFLICT (cache_key) DO UPDATE SET total = :t, cached_at = NOW()",
                    new MapSqlParameterSource("k", key).addValue("t", count));

                log.debug("CountCacheWarmup: cached '{}' -> {}", token, count);
            }

            log.info("CountCacheWarmup: done");
        } catch (Exception e) {
            log.warn("CountCacheWarmup: failed (non-fatal): {}", e.getMessage());
        }
    }
}
