package com.dashboard.controller;

import com.dashboard.dto.CreateOrderRequest;
import com.dashboard.service.OrderService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.Map;

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

    /** Exact (uncapped) count for the same filters as list. Intended as a
     *  follow-up from the frontend when the main /api/orders response comes
     *  back with approximate=true — fires in the background while the page
     *  is already displayed, then updates the total once it resolves. Also
     *  writes the real count to count_cache so subsequent list calls that
     *  would otherwise re-run the capped subquery get a cache hit instead. */
    @GetMapping("/count")
    public ResponseEntity<?> count(
            @RequestParam(required = false) String q,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String regionCode,
            @RequestParam(required = false) String from,
            @RequestParam(required = false) String to,
            @RequestParam(required = false) BigDecimal minTotal,
            @RequestParam(required = false) BigDecimal maxTotal) {
        long total = orderService.exactCountUncapped(q, status, regionCode, from, to, minTotal, maxTotal);
        return ResponseEntity.ok(Map.of("total", total));
    }

    @PostMapping
    public ResponseEntity<?> create(@Valid @RequestBody CreateOrderRequest req) {
        return ResponseEntity.status(201).body(orderService.createOrder(req));
    }
}
