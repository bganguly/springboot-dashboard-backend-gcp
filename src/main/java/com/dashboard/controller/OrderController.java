package com.dashboard.controller;

import com.dashboard.dto.CreateOrderRequest;
import com.dashboard.service.OrderService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;

@RestController
@RequestMapping("/api/orders")
@RequiredArgsConstructor
public class OrderController {

    private final OrderService orderService;

    @GetMapping
    public ResponseEntity<?> list(
            @RequestParam(required = false) String q,
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "20") int pageSize,
            @RequestParam(defaultValue = "placedAt") String sort,
            @RequestParam(defaultValue = "desc") String dir,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String regionCode,
            @RequestParam(required = false) String from,
            @RequestParam(required = false) String to,
            @RequestParam(required = false) BigDecimal minTotal,
            @RequestParam(required = false) BigDecimal maxTotal) {
        return ResponseEntity.ok(
                orderService.listOrders(q, page, pageSize, sort, dir, status, regionCode, from, to, minTotal, maxTotal));
    }

    @PostMapping
    public ResponseEntity<?> create(@Valid @RequestBody CreateOrderRequest req) {
        return ResponseEntity.status(201).body(orderService.createOrder(req));
    }
}
