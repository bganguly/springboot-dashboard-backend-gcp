package com.dashboard.dto;

import java.util.Map;

public record DailyAggregateDTO(String date, Map<String, CategoryAggregateDTO> categories) {
    public record CategoryAggregateDTO(
            long totalOrders,
            double totalRevenue,
            long totalItems,
            double avgOrderValue
    ) {}
}
