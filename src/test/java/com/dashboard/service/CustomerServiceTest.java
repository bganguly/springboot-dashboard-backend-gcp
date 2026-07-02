package com.dashboard.service;

import com.dashboard.dto.CustomerListResult;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.core.namedparam.SqlParameterSource;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

class CustomerServiceTest {

    private NamedParameterJdbcTemplate jdbc;
    private CustomerService service;

    @BeforeEach
    void setUp() {
        jdbc = mock(NamedParameterJdbcTemplate.class);
        service = new CustomerService(jdbc);
    }

    private static Map<String, Object> row(int id) {
        Map<String, Object> m = new HashMap<>();
        m.put("id", id);
        m.put("email", "u" + id + "@x.com");
        m.put("firstName", "First" + id);
        m.put("lastName", "Last" + id);
        m.put("phone", null);
        m.put("createdAt", LocalDateTime.of(2026, 1, 1, 0, 0));
        m.put("r_id", 1);
        m.put("code", "US-E");
        m.put("r_name", "US East");
        return m;
    }

    @Test
    void listCustomers_withMoreRows_setsNextCursor() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of(row(1), row(2), row(3)));

        CustomerListResult result = service.listCustomers(null, 2, null, null);

        assertThat(result.hasMore()).isTrue();
        assertThat(result.data()).hasSize(2);
        assertThat(result.nextCursor()).isEqualTo(2);
        assertThat(result.data().get(0).email()).isEqualTo("u1@x.com");
        assertThat(result.data().get(0).region().code()).isEqualTo("US-E");
    }

    @Test
    void listCustomers_lastPage_hasNoCursor() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of(row(1)));

        CustomerListResult result = service.listCustomers(null, 20, null, null);

        assertThat(result.hasMore()).isFalse();
        assertThat(result.nextCursor()).isNull();
        assertThat(result.data()).hasSize(1);
    }

    @Test
    void listCustomers_clampsLimit() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of());

        service.listCustomers(null, 500, null, null);

        var captor = ArgumentCaptor.forClass(SqlParameterSource.class);
        verify(jdbc).queryForList(anyString(), captor.capture());
        assertThat(captor.getValue().getValue("limit")).isEqualTo(101); // clamped to 100, +1 look-ahead

        reset(jdbc);
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class))).thenReturn(List.of());
        service.listCustomers(null, 0, null, null);
        verify(jdbc).queryForList(anyString(), captor.capture());
        assertThat(captor.getValue().getValue("limit")).isEqualTo(2); // clamped to 1, +1 look-ahead
    }

    @Test
    void listCustomers_appliesFilters() {
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of());

        service.listCustomers(10, 20, "smith", 4);

        var sqlCaptor = ArgumentCaptor.forClass(String.class);
        var paramCaptor = ArgumentCaptor.forClass(SqlParameterSource.class);
        verify(jdbc).queryForList(sqlCaptor.capture(), paramCaptor.capture());
        assertThat(sqlCaptor.getValue())
                .contains("c.id > :cursor")
                .contains("ILIKE :q")
                .contains("c.\"regionId\" = :regionId");
        assertThat(paramCaptor.getValue().getValue("q")).isEqualTo("%smith%");
        assertThat(paramCaptor.getValue().getValue("cursor")).isEqualTo(10);
        assertThat(paramCaptor.getValue().getValue("regionId")).isEqualTo(4);
    }

    @Test
    void listCustomers_nullCreatedAt_mapsToNull() {
        Map<String, Object> r = row(1);
        r.put("createdAt", null);
        when(jdbc.queryForList(anyString(), any(SqlParameterSource.class)))
                .thenReturn(List.of(r));

        CustomerListResult result = service.listCustomers(null, 20, null, null);

        assertThat(result.data().get(0).createdAt()).isNull();
    }
}
