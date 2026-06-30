package com.dashboard.dto;

import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.util.List;

public record CreateOrderRequest(
        @NotNull Integer customerId,
        @NotNull Integer regionId,
        String currency,
        String notes,
        @NotEmpty List<Item> items
) {
    public record Item(
            @NotNull Integer productId,
            @NotNull Integer quantity,
            @NotNull BigDecimal unitPrice,
            BigDecimal discount
    ) {}
}
