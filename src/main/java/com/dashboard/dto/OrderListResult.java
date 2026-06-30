package com.dashboard.dto;

import java.util.List;

public record OrderListResult(
        List<OrderDTO> data,
        int page,
        int pageSize,
        long total,
        int totalPages,
        boolean approximate
) {}
