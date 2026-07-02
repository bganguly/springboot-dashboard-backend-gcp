package com.dashboard.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.core.namedparam.SqlParameterSource;

import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

class CountCacheWarmupTest {

    private NamedParameterJdbcTemplate jdbc;
    private CountCacheWarmup warmup;

    @BeforeEach
    void setUp() {
        jdbc = mock(NamedParameterJdbcTemplate.class);
        warmup = new CountCacheWarmup(jdbc);
    }

    /** Runs the private warmup() synchronously so assertions are deterministic. */
    private void runWarmupSynchronously() throws Exception {
        Method m = CountCacheWarmup.class.getDeclaredMethod("warmup");
        m.setAccessible(true);
        m.invoke(warmup);
    }

    private static Map<String, Object> name(String first, String last) {
        Map<String, Object> m = new HashMap<>();
        m.put("firstName", first);
        m.put("lastName", last);
        return m;
    }

    @Test
    void warmup_cachesMissingTokensAndSkipsCachedOnes() throws Exception {
        when(jdbc.queryForList(contains("WITH recent"), any(SqlParameterSource.class)))
                .thenReturn(List.of(name("John", "Doe"), name("john", null), name(" ", "")));
        // "john" already cached, "doe" is a miss
        when(jdbc.queryForList(contains("FROM count_cache"), any(SqlParameterSource.class), eq(Long.class)))
                .thenReturn(List.of(10L))
                .thenReturn(List.of());
        when(jdbc.queryForObject(contains("COUNT(*)"), any(SqlParameterSource.class), eq(Long.class)))
                .thenReturn(3L);

        runWarmupSynchronously();

        // only the miss ("doe") triggers a COUNT + upsert
        verify(jdbc, times(1)).queryForObject(contains("COUNT(*)"), any(SqlParameterSource.class), eq(Long.class));
        verify(jdbc, times(1)).update(contains("INSERT INTO count_cache"), any(SqlParameterSource.class));
    }

    @Test
    void warmup_failure_isSwallowed() throws Exception {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenThrow(new RuntimeException("db down"));

        runWarmupSynchronously(); // must not throw

        verify(jdbc, never()).update(anyString(), any(SqlParameterSource.class));
    }

    @Test
    void run_startsBackgroundWarmup() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of());

        warmup.run(null);

        verify(jdbc, timeout(5000)).queryForList(contains("WITH recent"), any(SqlParameterSource.class));
    }
}
