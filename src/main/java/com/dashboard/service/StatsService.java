package com.dashboard.service;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.namedparam.EmptySqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.Map;

@Service
@RequiredArgsConstructor
public class StatsService {

    private final NamedParameterJdbcTemplate jdbc;

    public Map<String, Object> getSeedStats() {
        Long customers = jdbc.queryForObject(
                "SELECT COUNT(*) FROM customers", EmptySqlParameterSource.INSTANCE, Long.class);
        Long products = jdbc.queryForObject(
                "SELECT COUNT(*) FROM products", EmptySqlParameterSource.INSTANCE, Long.class);
        return Map.of(
                "customerCount", customers != null ? customers : 0L,
                "productCount", products != null ? products : 0L);
    }
}
