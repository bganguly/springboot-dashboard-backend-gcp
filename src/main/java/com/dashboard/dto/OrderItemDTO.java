package com.dashboard.dto;

import java.math.BigDecimal;

public record OrderItemDTO(
        int id,
        int productId,
        String productSku,
        String productName,
        int quantity,
        BigDecimal unitPrice,
        BigDecimal discount
) {}
