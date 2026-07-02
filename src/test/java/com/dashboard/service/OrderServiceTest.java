package com.dashboard.service;

import com.dashboard.dto.CreateOrderRequest;
import com.dashboard.dto.OrderListResult;
import com.dashboard.entity.*;
import com.dashboard.repository.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.SqlParameterSource;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.*;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

class OrderServiceTest {

    private org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate jdbc;
    private OrderRepository orderRepository;
    private CustomerRepository customerRepository;
    private RegionRepository regionRepository;
    private ProductRepository productRepository;
    private OrderService service;

    @BeforeEach
    void setUp() {
        jdbc = mock(org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate.class);
        orderRepository = mock(OrderRepository.class);
        customerRepository = mock(CustomerRepository.class);
        regionRepository = mock(RegionRepository.class);
        productRepository = mock(ProductRepository.class);
        service = new OrderService(jdbc, orderRepository, customerRepository, regionRepository, productRepository);
    }

    private static Map<String, Object> orderRow(int id) {
        Map<String, Object> m = new HashMap<>();
        m.put("id", id);
        m.put("status", "PENDING");
        m.put("total", new BigDecimal("42.00"));
        m.put("currency", "USD");
        m.put("notes", "note");
        m.put("placedAt", LocalDateTime.of(2026, 1, 15, 10, 30, 0));
        m.put("c_id", 7);
        m.put("email", "a@b.com");
        m.put("firstName", "John");
        m.put("lastName", "Doe");
        m.put("phone", "123");
        m.put("r_id", 3);
        m.put("r_code", "US-E");
        m.put("r_name", "US East");
        return m;
    }

    private static Map<String, Object> itemRow(int orderId) {
        Map<String, Object> m = new HashMap<>();
        m.put("id", 100);
        m.put("orderId", orderId);
        m.put("productId", 55);
        m.put("quantity", 2);
        m.put("unitPrice", new BigDecimal("10.00"));
        m.put("discount", new BigDecimal("0.10"));
        m.put("sku", "SKU-1");
        m.put("p_name", "Widget");
        return m;
    }

    /** Stubs the count-cache miss path and dispatches the data/items queries by SQL content. */
    private void stubQueries(List<Map<String, Object>> dataRows, List<Map<String, Object>> itemRows, long count) {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class), eq(Long.class)))
                .thenReturn(List.of()); // cache miss
        when(jdbc.queryForObject(anyString(), any(SqlParameterSource.class), eq(Long.class)))
                .thenReturn(count);
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenAnswer(inv -> {
                    String sql = inv.getArgument(0);
                    return sql.contains("FROM order_items") ? itemRows : dataRows;
                });
    }

    @Test
    void listOrders_mapsRowsAndItems() {
        stubQueries(List.of(orderRow(1)), List.of(itemRow(1)), 100);

        OrderListResult result = service.listOrders(
                null, 1, 20, "placedAt", "desc", null, null, null, null, null, null);

        assertThat(result.total()).isEqualTo(100);
        assertThat(result.totalPages()).isEqualTo(5);
        assertThat(result.data()).hasSize(1);
        var order = result.data().get(0);
        assertThat(order.id()).isEqualTo(1);
        assertThat(order.placedAt()).isEqualTo("2026-01-15T10:30:00.000Z");
        assertThat(order.customer().email()).isEqualTo("a@b.com");
        assertThat(order.region().code()).isEqualTo("US-E");
        assertThat(order.items()).hasSize(1);
        assertThat(order.items().get(0).productSku()).isEqualTo("SKU-1");
    }

    @Test
    void listOrders_emptyResult_skipsItemFetch() {
        stubQueries(List.of(), List.of(), 0);

        OrderListResult result = service.listOrders(
                null, 1, 20, "placedAt", "desc", null, null, null, null, null, null);

        assertThat(result.data()).isEmpty();
        assertThat(result.total()).isZero();
        verify(jdbc, never()).queryForList(contains("FROM order_items"), any(SqlParameterSource.class));
    }

    @Test
    void listOrders_clampsPageAndPageSize() {
        stubQueries(List.of(), List.of(), 0);

        service.listOrders(null, 0, 1000, "placedAt", "desc", null, null, null, null, null, null);

        var captor = ArgumentCaptor.forClass(SqlParameterSource.class);
        verify(jdbc).queryForList(contains("LIMIT :limit"), captor.capture());
        assertThat(captor.getValue().getValue("limit")).isEqualTo(100);
        assertThat(captor.getValue().getValue("offset")).isEqualTo(0);
    }

    @Test
    void listOrders_sortByCustomerAsc() {
        stubQueries(List.of(), List.of(), 0);

        service.listOrders(null, 1, 20, "customer", "asc", null, null, null, null, null, null);

        verify(jdbc).queryForList(contains("ORDER BY c.\"firstName\" ASC"), any(SqlParameterSource.class));
    }

    @Test
    void listOrders_invalidSortAndDir_fallBackToPlacedAtDesc() {
        stubQueries(List.of(), List.of(), 0);

        service.listOrders(null, 1, 20, "evil; DROP", "sideways", null, null, null, null, null, null);

        verify(jdbc).queryForList(contains("ORDER BY o.\"placedAt\" DESC"), any(SqlParameterSource.class));
    }

    @Test
    void listOrders_buildsAllFilterClauses() {
        stubQueries(List.of(), List.of(), 0);

        service.listOrders("john doe", 1, 20, "total", "asc", "PENDING,SHIPPED", "US-E,EU",
                "2026-01-01", "2026-01-31", new BigDecimal("5"), new BigDecimal("500"));

        var captor = ArgumentCaptor.forClass(String.class);
        verify(jdbc).queryForList(captor.capture(), any(SqlParameterSource.class));
        String sql = captor.getValue();
        assertThat(sql)
                .contains("o.search_text ILIKE :q0")
                .contains("o.search_text ILIKE :q1")
                .contains("'PENDING'::\"OrderStatus\"")
                .contains("'SHIPPED'::\"OrderStatus\"")
                .contains("r.code = ANY(ARRAY['US-E','EU'])")
                .contains(":from::timestamptz")
                .contains(":to::date")
                .contains("o.total >= :minTotal")
                .contains("o.total <= :maxTotal")
                .contains("ORDER BY o.total ASC");
    }

    @Test
    void listOrders_regionFilter_addsRegionJoinToCountQuery() {
        stubQueries(List.of(), List.of(), 0);

        service.listOrders(null, 1, 20, "id", "asc", null, "US-E", null, null, null, null);

        verify(jdbc).queryForObject(
                contains("SELECT COUNT(*) FROM orders o JOIN regions r"),
                any(SqlParameterSource.class), eq(Long.class));
    }

    @Test
    void listOrders_countCacheHit_skipsCountQuery() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class), eq(Long.class)))
                .thenReturn(List.of(42L));
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of());

        OrderListResult result = service.listOrders(
                null, 1, 20, "placedAt", "desc", null, null, null, null, null, null);

        assertThat(result.total()).isEqualTo(42);
        verify(jdbc, never()).queryForObject(anyString(), any(SqlParameterSource.class), eq(Long.class));
    }

    @Test
    void listOrders_cacheReadAndWriteFailures_areIgnored() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class), eq(Long.class)))
                .thenThrow(new RuntimeException("cache table missing"));
        when(jdbc.queryForObject(anyString(), any(SqlParameterSource.class), eq(Long.class)))
                .thenReturn(7L);
        when(jdbc.update(anyString(), any(SqlParameterSource.class)))
                .thenThrow(new RuntimeException("insert failed"));
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of());

        OrderListResult result = service.listOrders(
                null, 1, 20, "placedAt", "desc", null, null, null, null, null, null);

        assertThat(result.total()).isEqualTo(7);
    }

    @Test
    void createOrder_computesTotalWithDiscounts() {
        Customer customer = new Customer();
        customer.setId(7);
        Region region = new Region();
        region.setId(3);
        Product product = new Product();
        product.setId(55);
        when(customerRepository.findById(7)).thenReturn(Optional.of(customer));
        when(regionRepository.findById(3)).thenReturn(Optional.of(region));
        when(productRepository.findById(55)).thenReturn(Optional.of(product));
        when(orderRepository.save(any(Order.class))).thenAnswer(inv -> {
            Order o = inv.getArgument(0);
            o.setId(99);
            return o;
        });

        var req = new CreateOrderRequest(7, 3, null, "gift", List.of(
                new CreateOrderRequest.Item(55, 2, new BigDecimal("10.00"), new BigDecimal("0.10")),
                new CreateOrderRequest.Item(55, 1, new BigDecimal("5.00"), null)));

        Map<String, Object> result = service.createOrder(req);

        assertThat(result.get("id")).isEqualTo(99);
        assertThat(result.get("status")).isEqualTo("PENDING");
        assertThat((BigDecimal) result.get("total")).isEqualByComparingTo("23.00");

        var captor = ArgumentCaptor.forClass(Order.class);
        verify(orderRepository).save(captor.capture());
        Order saved = captor.getValue();
        assertThat(saved.getCurrency()).isEqualTo("USD");
        assertThat(saved.getNotes()).isEqualTo("gift");
        assertThat(saved.getItems()).hasSize(2);
        assertThat(saved.getItems().get(1).getDiscount()).isEqualByComparingTo(BigDecimal.ZERO);
    }

    @Test
    void createOrder_usesExplicitCurrency() {
        Customer customer = new Customer();
        Region region = new Region();
        when(customerRepository.findById(7)).thenReturn(Optional.of(customer));
        when(regionRepository.findById(3)).thenReturn(Optional.of(region));
        when(orderRepository.save(any(Order.class))).thenAnswer(inv -> {
            Order o = inv.getArgument(0);
            o.setId(1);
            return o;
        });

        service.createOrder(new CreateOrderRequest(7, 3, "EUR", null, List.of()));

        var captor = ArgumentCaptor.forClass(Order.class);
        verify(orderRepository).save(captor.capture());
        assertThat(captor.getValue().getCurrency()).isEqualTo("EUR");
    }

    @Test
    void createOrder_unknownCustomer_throws() {
        when(customerRepository.findById(7)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.createOrder(new CreateOrderRequest(7, 3, null, null, List.of())))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Customer not found: 7");
    }

    @Test
    void createOrder_unknownRegion_throws() {
        when(customerRepository.findById(7)).thenReturn(Optional.of(new Customer()));
        when(regionRepository.findById(3)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.createOrder(new CreateOrderRequest(7, 3, null, null, List.of())))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Region not found: 3");
    }

    @Test
    void createOrder_unknownProduct_throws() {
        when(customerRepository.findById(7)).thenReturn(Optional.of(new Customer()));
        when(regionRepository.findById(3)).thenReturn(Optional.of(new Region()));
        when(productRepository.findById(55)).thenReturn(Optional.empty());

        var req = new CreateOrderRequest(7, 3, null, null,
                List.of(new CreateOrderRequest.Item(55, 1, BigDecimal.ONE, null)));

        assertThatThrownBy(() -> service.createOrder(req))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Product not found: 55");
    }
}
