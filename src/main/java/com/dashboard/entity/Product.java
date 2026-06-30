package com.dashboard.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;
import java.math.BigDecimal;

@Entity
@Table(name = "products")
@Getter @Setter
public class Product {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer id;
    @Column(unique = true, length = 100, nullable = false)
    private String sku;
    @Column(length = 255, nullable = false)
    private String name;
    private String description;
    @Column(precision = 10, scale = 2, nullable = false)
    private BigDecimal price;
    @Column(precision = 10, scale = 2, nullable = false)
    private BigDecimal cost;
    private Integer stock;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "categoryId", nullable = false)
    private Category category;
}
