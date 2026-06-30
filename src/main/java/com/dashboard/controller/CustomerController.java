package com.dashboard.controller;

import com.dashboard.service.CustomerService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/customers")
@RequiredArgsConstructor
public class CustomerController {

    private final CustomerService customerService;

    @GetMapping
    public ResponseEntity<?> list(
            @RequestParam(required = false) Integer cursor,
            @RequestParam(defaultValue = "20") int limit,
            @RequestParam(required = false) String q,
            @RequestParam(required = false) Integer regionId) {
        return ResponseEntity.ok(customerService.listCustomers(cursor, limit, q, regionId));
    }
}
