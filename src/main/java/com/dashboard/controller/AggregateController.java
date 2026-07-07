package com.dashboard.controller;

import com.dashboard.service.AggregateService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.HashMap;
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
            @RequestParam(required = false) Integer topCategories,
            // The category breakdown (pre-aggregated, always fast) and the
            // exact total (a raw COUNT(*) — cheap only when count_cache
            // already has this exact range cached, which a brush drag's
            // ever-changing range essentially never does) are independent.
            // Callers that don't want to block a fast render on a slow count
            // — or vice versa — can request just one side.
            @RequestParam(defaultValue = "true") boolean includeData,
            @RequestParam(defaultValue = "true") boolean includeTotal) {
        CompletableFuture<?> dataFuture = includeData
                ? CompletableFuture.supplyAsync(
                        () -> aggregateService.getDailyAggregates(from, to, q, status, regionCode, minTotal, maxTotal, topCategories),
                        virtualThreadExecutor)
                : CompletableFuture.completedFuture(null);
        // Exact distinct order count for this same range/filters — see
        // AggregateService.getExactTotal. Preferred over summing category
        // rows, which double-counts any order whose items span more than one
        // category.
        CompletableFuture<?> totalFuture = includeTotal
                ? CompletableFuture.supplyAsync(
                        () -> aggregateService.getExactTotal(from, to, q, status, regionCode, minTotal, maxTotal),
                        virtualThreadExecutor)
                : CompletableFuture.completedFuture(null);

        var data = dataFuture.join();
        var totalOrders = totalFuture.join();

        Map<String, Object> body = new HashMap<>();
        if (includeData) body.put("data", data);
        if (includeTotal) body.put("totalOrders", totalOrders);
        return ResponseEntity.ok(body);
    }
}
