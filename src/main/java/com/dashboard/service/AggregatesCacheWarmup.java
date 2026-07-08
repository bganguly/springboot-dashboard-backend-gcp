package com.dashboard.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.util.HashMap;
import java.util.Map;

/**
 * Pre-warms the in-process aggregates cache with today's default-view response
 * so the first hard reload of the day is served from cache rather than paying
 * the full DB round-trip cost. Runs on a virtual thread so startup is not blocked.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class AggregatesCacheWarmup implements ApplicationRunner {

    private static final String DEFAULT_FROM = "2020-01-01";
    private static final int DEFAULT_TOP_N = 5;

    private final AggregateService aggregateService;
    private final AggregatesCache aggregatesCache;

    @Override
    public void run(ApplicationArguments args) {
        Thread.ofVirtual().name("aggregates-cache-warmup").start(this::warmup);
    }

    private void warmup() {
        try {
            String to = LocalDate.now().toString();
            log.info("AggregatesCacheWarmup: pre-warming {}/{} topN={}", DEFAULT_FROM, to, DEFAULT_TOP_N);

            var data = aggregateService.getDailyAggregates(
                    DEFAULT_FROM, to, null, null, null, null, null, DEFAULT_TOP_N);
            long rawTotal = aggregateService.getExactTotal(
                    DEFAULT_FROM, to, null, null, null, null, null);

            Map<String, Object> body = new HashMap<>();
            body.put("data", data);
            body.put("totalOrders", OrderService.adjustCount(rawTotal));
            body.put("totalOrdersApproximate", OrderService.isApproximateCount(rawTotal));

            aggregatesCache.put(AggregatesCache.key(DEFAULT_FROM, to, DEFAULT_TOP_N), body);
            log.info("AggregatesCacheWarmup: done — {} daily rows, total={}", data.size(), body.get("totalOrders"));
        } catch (Exception e) {
            log.warn("AggregatesCacheWarmup: failed (non-fatal): {}", e.getMessage());
        }
    }
}
