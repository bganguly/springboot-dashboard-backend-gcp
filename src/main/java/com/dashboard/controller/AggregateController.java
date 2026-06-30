package com.dashboard.controller;

import com.dashboard.service.AggregateService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.Map;

@RestController
@RequestMapping("/api/aggregates")
@RequiredArgsConstructor
public class AggregateController {

    private final AggregateService aggregateService;

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
        var data = aggregateService.getDailyAggregates(from, to, q, status, regionCode, minTotal, maxTotal, topCategories);
        return ResponseEntity.ok(Map.of("data", data));
    }
}
