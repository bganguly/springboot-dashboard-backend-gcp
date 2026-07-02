package com.dashboard.service;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.core.namedparam.SqlParameterSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class StatsServiceTest {

    @Test
    void getSeedStats_returnsCounts() {
        NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
        when(jdbc.queryForObject(contains("FROM customers"), any(SqlParameterSource.class), eq(Long.class)))
                .thenReturn(5L);
        when(jdbc.queryForObject(contains("FROM products"), any(SqlParameterSource.class), eq(Long.class)))
                .thenReturn(9L);

        var stats = new StatsService(jdbc).getSeedStats();

        assertThat(stats).containsEntry("customerCount", 5L).containsEntry("productCount", 9L);
    }

    @Test
    void getSeedStats_nullCounts_defaultToZero() {
        NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
        when(jdbc.queryForObject(any(String.class), any(SqlParameterSource.class), eq(Long.class)))
                .thenReturn(null);

        var stats = new StatsService(jdbc).getSeedStats();

        assertThat(stats).containsEntry("customerCount", 0L).containsEntry("productCount", 0L);
    }
}
