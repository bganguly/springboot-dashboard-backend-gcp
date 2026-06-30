package com.dashboard.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;
import java.math.BigDecimal;

@Entity
@Table(name = "order_items")
@Getter @Setter
public class OrderItem {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer id;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "orderId", nullable = false)
    private Order order;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "productId", nullable = false)
    private Product product;
    @Column(nullable = false)
    private Integer quantity;
    @Column(precision = 10, scale = 2, nullable = false)
    private BigDecimal unitPrice;
    @Column(precision = 5, scale = 2, nullable = false)
    private BigDecimal discount = BigDecimal.ZERO;
}
