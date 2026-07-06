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
            @RequestParam(required = false) BigDecimal maxTotal,
            // Optional keyset cursor for Prev/Next on the default placedAt/desc
            // sort — an OFFSET query's cost scales with page depth, but seeking
            // off a known row via the index doesn't. Only engaged for the
            // default sort/dir; any other combination falls back to OFFSET.
            @RequestParam(required = false) Integer cursorId,
            @RequestParam(required = false) String cursorPlacedAt,
            @RequestParam(required = false) String cursorDir) {
        boolean useCursor = cursorId != null && cursorPlacedAt != null
                && "placedAt".equals(sort) && "desc".equalsIgnoreCase(dir);
        if (useCursor) {
            boolean forward = !"prev".equalsIgnoreCase(cursorDir);
            return ResponseEntity.ok(orderService.listOrdersByCursor(
                    q, page, pageSize, status, regionCode, from, to, minTotal, maxTotal,
                    cursorId, cursorPlacedAt, forward));
        }
        return ResponseEntity.ok(
                orderService.listOrders(q, page, pageSize, sort, dir, status, regionCode, from, to, minTotal, maxTotal));
    }

    @PostMapping
    public ResponseEntity<?> create(@Valid @RequestBody CreateOrderRequest req) {
        return ResponseEntity.status(201).body(orderService.createOrder(req));
    }
}
