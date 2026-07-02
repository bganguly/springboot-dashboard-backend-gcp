package com.dashboard.service;

import com.dashboard.dto.DailyAggregateDTO;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.core.namedparam.SqlParameterSource;

import java.math.BigDecimal;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

class AggregateServiceTest {

    private NamedParameterJdbcTemplate jdbc;
    private AggregateService service;

    @BeforeEach
    void setUp() {
        jdbc = mock(NamedParameterJdbcTemplate.class);
        service = new AggregateService(jdbc);
    }

    private static Map<String, Object> row(String day, String cat, long orders, String revenue, long items) {
        Map<String, Object> m = new HashMap<>();
        m.put("day", day);
        m.put("category", cat);
        m.put("total_orders", orders);
        m.put("total_revenue", new BigDecimal(revenue));
        m.put("total_items", items);
        return m;
    }

    private String capturedSql() {
        var captor = ArgumentCaptor.forClass(String.class);
        verify(jdbc, atLeastOnce()).queryForList(captor.capture(), any(SqlParameterSource.class));
        return captor.getValue();
    }

    @Test
    void noFilters_usesDailySummary() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of(row("2026-01-01", "Books", 4, "100.00", 8)));

        List<DailyAggregateDTO> result = service.getDailyAggregates(
                "2026-01-01", "2026-01-31", null, null, null, null, null, null);

        assertThat(capturedSql()).contains("FROM daily_summary");
        assertThat(result).hasSize(1);
        assertThat(result.get(0).date()).isEqualTo("2026-01-01");
        var cat = result.get(0).categories().get("Books");
        assertThat(cat.totalOrders()).isEqualTo(4);
        assertThat(cat.totalRevenue()).isEqualTo(100.0);
        assertThat(cat.totalItems()).isEqualTo(8);
        assertThat(cat.avgOrderValue()).isEqualTo(25.0);
    }

    @Test
    void singleTokenQuery_usesTokenRollup() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of(row("2026-01-02", "Toys", 2, "50.00", 3)));

        service.getDailyAggregates("2026-01-01", "2026-01-31", "smith", null, null, null, null, null);

        assertThat(capturedSql()).contains("FROM daily_customer_token_category_rollup");
    }

    @Test
    void singleTokenQuery_fallsBackToSearchTextWhenRollupEmpty() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of())
                .thenReturn(List.of(row("2026-01-02", "Toys", 2, "50.00", 3)));

        var result = service.getDailyAggregates("2026-01-01", "2026-01-31", "smith", null, null, null, null, null);

        assertThat(capturedSql()).contains("o.search_text ILIKE");
        assertThat(result).hasSize(1);
    }

    @Test
    void multiTokenQuery_usesCte() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of(row("2026-01-03", "Games", 1, "20.00", 1)));

        service.getDailyAggregates("2026-01-01", "2026-01-31", "john doe", null, null, null, null, null);

        assertThat(capturedSql()).contains("WITH matching_customers");
    }

    @Test
    void multiTokenQuery_fallsBackToSearchTextWhenCteEmpty() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of())
                .thenReturn(List.of(row("2026-01-03", "Games", 1, "20.00", 1)));

        service.getDailyAggregates("2026-01-01", "2026-01-31", "john doe", null, null, null, null, null);

        verify(jdbc, times(2)).queryForList(anyString(), any(SqlParameterSource.class));
        assertThat(capturedSql()).contains("o.search_text ILIKE");
    }

    @Test
    void multiTokenQueryWithTotalFilter_usesSearchTextDirectly() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of(row("2026-01-03", "Games", 1, "20.00", 1)));

        service.getDailyAggregates("2026-01-01", "2026-01-31", "john doe", null, null,
                new BigDecimal("10"), null, null);

        verify(jdbc, times(1)).queryForList(anyString(), any(SqlParameterSource.class));
        assertThat(capturedSql()).contains("o.search_text ILIKE").contains("o.total >= :minTotal");
    }

    @Test
    void singleTokenWithStatus_usesTokenCategorySummary() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of(row("2026-01-04", "Books", 3, "60.00", 5)));

        service.getDailyAggregates("2026-01-01", "2026-01-31", "smith", "PENDING", null, null, null, null);

        assertThat(capturedSql())
                .contains("FROM daily_customer_token_category_summary")
                .contains("'PENDING'::\"OrderStatus\"");
    }

    @Test
    void singleTokenWithStatus_fallsBackToSearchTextWhenEmpty() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of())
                .thenReturn(List.of(row("2026-01-04", "Books", 3, "60.00", 5)));

        service.getDailyAggregates("2026-01-01", "2026-01-31", "smith", "PENDING", null, null, null, null);

        assertThat(capturedSql()).contains("o.search_text ILIKE");
    }

    @Test
    void singleTokenWithTotal_usesSearchText() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of(row("2026-01-04", "Books", 3, "60.00", 5)));

        service.getDailyAggregates("2026-01-01", "2026-01-31", "smith", null, null,
                null, new BigDecimal("500"), null);

        assertThat(capturedSql()).contains("o.search_text ILIKE").contains("o.total <= :maxTotal");
    }

    @Test
    void statusOnly_usesStatusCategorySummary() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of(row("2026-01-05", "Books", 2, "40.00", 2)));

        service.getDailyAggregates("2026-01-01", "2026-01-31", null, "SHIPPED,DELIVERED", null, null, null, null);

        assertThat(capturedSql())
                .contains("FROM daily_status_category_summary")
                .contains("'SHIPPED'::\"OrderStatus\"")
                .contains("'DELIVERED'::\"OrderStatus\"");
    }

    @Test
    void regionOnly_usesFilterCategorySummary() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of(row("2026-01-06", "Books", 2, "40.00", 2)));

        service.getDailyAggregates("2026-01-01", "2026-01-31", null, null, "US-E", null, null, null);

        assertThat(capturedSql())
                .contains("FROM daily_filter_category_summary")
                .contains("'US-E'");
    }

    @Test
    void statusAndRegion_usesFilterCategorySummary() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of(row("2026-01-06", "Books", 2, "40.00", 2)));

        service.getDailyAggregates("2026-01-01", "2026-01-31", null, "PENDING", "US-E", null, null, null);

        assertThat(capturedSql())
                .contains("FROM daily_filter_category_summary")
                .contains("'PENDING'::\"OrderStatus\"")
                .contains("'US-E'");
    }

    @Test
    void totalFilterOnly_usesOrderCategoryFacts() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of(row("2026-01-07", "Books", 2, "40.00", 2)));

        service.getDailyAggregates("2026-01-01", "2026-01-31", null, null, null,
                new BigDecimal("10"), new BigDecimal("100"), null);

        assertThat(capturedSql())
                .contains("FROM order_category_facts")
                .contains("\"orderTotal\" >= :minTotal")
                .contains("\"orderTotal\" <= :maxTotal");
    }

    @Test
    void quotesInRegionCode_areEscaped() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of());

        service.getDailyAggregates("2026-01-01", "2026-01-31", null, null, "E'U", null, null, null);

        assertThat(capturedSql()).contains("'E''U'");
    }

    @Test
    void topCategories_limitsAndBucketsOthers() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of(
                        row("2026-01-01", "A", 10, "100.00", 10),
                        row("2026-01-01", "B", 5, "50.00", 5),
                        row("2026-01-01", "C", 2, "20.00", 2),
                        row("2026-01-01", "D", 1, "10.00", 1)));

        var result = service.getDailyAggregates(
                "2026-01-01", "2026-01-31", null, null, null, null, null, 2);

        var cats = result.get(0).categories();
        assertThat(cats).containsKeys("A", "B", "Others");
        assertThat(cats).doesNotContainKeys("C", "D");
        assertThat(cats.get("Others").totalOrders()).isEqualTo(3);
        assertThat(cats.get("Others").totalRevenue()).isEqualTo(30.0);
        assertThat(cats.get("Others").totalItems()).isEqualTo(3);
        assertThat(cats.get("Others").avgOrderValue()).isEqualTo(10.0);
    }

    @Test
    void defaultTopCategories_isFive() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of(
                        row("2026-01-01", "A", 10, "10.00", 1),
                        row("2026-01-01", "B", 9, "9.00", 1),
                        row("2026-01-01", "C", 8, "8.00", 1),
                        row("2026-01-01", "D", 7, "7.00", 1),
                        row("2026-01-01", "E", 6, "6.00", 1),
                        row("2026-01-01", "F", 5, "5.00", 1)));

        var result = service.getDailyAggregates(
                "2026-01-01", "2026-01-31", null, null, null, null, null, null);

        var cats = result.get(0).categories();
        assertThat(cats).containsKeys("A", "B", "C", "D", "E", "Others");
        assertThat(cats).doesNotContainKey("F");
    }

    @Test
    void nonNumericValues_defaultToZero() {
        Map<String, Object> bad = new HashMap<>();
        bad.put("day", "2026-01-01");
        bad.put("category", "A");
        bad.put("total_orders", null);
        bad.put("total_revenue", null);
        bad.put("total_items", null);
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of(bad));

        var result = service.getDailyAggregates(
                "2026-01-01", "2026-01-31", null, null, null, null, null, null);

        var cat = result.get(0).categories().get("A");
        assertThat(cat.totalOrders()).isZero();
        assertThat(cat.totalRevenue()).isZero();
        assertThat(cat.totalItems()).isZero();
        assertThat(cat.avgOrderValue()).isZero();
    }
}
