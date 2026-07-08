package com.dashboard.service;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.Optional;
import java.util.concurrent.TimeUnit;

/**
 * In-process Caffeine cache for the no-filter /api/aggregates response body.
 * Keyed on (from, to, topCategories). Evicted on every order creation and
 * expires after 10 minutes so stale data never persists across refreshes.
 */
@Component
public class AggregatesCache {

    private final Cache<String, Map<String, Object>> cache = Caffeine.newBuilder()
            .expireAfterWrite(10, TimeUnit.MINUTES)
            .maximumSize(50)
            .build();

    public static String key(String from, String to, int topCategories) {
        return from + "|" + to + "|" + topCategories;
    }

    public Optional<Map<String, Object>> get(String key) {
        return Optional.ofNullable(cache.getIfPresent(key));
    }

    public void put(String key, Map<String, Object> value) {
        cache.put(key, value);
    }

    public void invalidateAll() {
        cache.invalidateAll();
    }
}
