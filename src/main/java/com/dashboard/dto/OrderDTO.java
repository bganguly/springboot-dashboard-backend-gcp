package com.dashboard.dto;

import java.math.BigDecimal;
import java.util.List;

public record OrderDTO(
        int id,
        String status,
        BigDecimal total,
        String currency,
        String notes,
        String placedAt,
        CustomerSummaryDTO customer,
        RegionDTO region,
        List<OrderItemDTO> items
) {}
