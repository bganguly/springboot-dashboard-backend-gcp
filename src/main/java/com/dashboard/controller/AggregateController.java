package com.dashboard.controller;

import com.dashboard.service.AggregateService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executor;

@RestController
@RequestMapping("/api/aggregates")
@RequiredArgsConstructor
public class AggregateController {

    private final AggregateService aggregateService;
    private final Executor virtualThreadExecutor = java.util.concurrent.Executors.newVirtualThreadPerTaskExecutor();

    @GetMapping
    public ResponseEntity<?> get(
            @RequestParam String from,
            @RequestParam String to,
            @RequestParam(required = false) String q,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String regionCode,
            @RequestParam(required = false) BigDecimal minTotal,
            @RequestParam(required = false) BigDecimal maxTotal,
            @RequestParam(required = false) Integer topCategories) {
        // The category breakdown and the exact total are independent queries
        // over the same range/filters — run them concurrently (each on its
        // own DB connection) instead of back-to-back so the request's latency
        // is max(query) rather than the sum of both.
        var dataFuture = CompletableFuture.supplyAsync(
                () -> aggregateService.getDailyAggregates(from, to, q, status, regionCode, minTotal, maxTotal, topCategories),
                virtualThreadExecutor);
        // Exact distinct order count for this same range/filters — see
        // AggregateService.getExactTotal. Preferred over summing category
        // rows, which double-counts any order whose items span more than one
        // category.
        var totalFuture = CompletableFuture.supplyAsync(
                () -> aggregateService.getExactTotal(from, to, q, status, regionCode, minTotal, maxTotal),
                virtualThreadExecutor);

        var data = dataFuture.join();
        var totalOrders = totalFuture.join();
        return ResponseEntity.ok(Map.of("data", data, "totalOrders", totalOrders));
    }
}
