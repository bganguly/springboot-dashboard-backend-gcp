package com.dashboard.controller;

import com.dashboard.dto.CreateOrderRequest;
import com.dashboard.dto.CustomerListResult;
import com.dashboard.dto.DailyAggregateDTO;
import com.dashboard.dto.OrderListResult;
import com.dashboard.dto.RegionDTO;
import com.dashboard.service.AggregateService;
import com.dashboard.service.CustomerService;
import com.dashboard.service.OrderService;
import com.dashboard.service.RegionService;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class ControllerTest {

    @Test
    void aggregateController_wrapsDataInMap() {
        AggregateService service = mock(AggregateService.class);
        var dto = new DailyAggregateDTO("2026-01-01", Map.of());
        when(service.getDailyAggregates("2026-01-01", "2026-01-31", null, null, null, null, null, null))
                .thenReturn(List.of(dto));

        var response = new AggregateController(service)
                .get("2026-01-01", "2026-01-31", null, null, null, null, null, null);

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        assertThat(response.getBody()).isEqualTo(Map.of("data", List.of(dto)));
    }

    @Test
    void customerController_delegatesToService() {
        CustomerService service = mock(CustomerService.class);
        var result = new CustomerListResult(List.of(), null, false);
        when(service.listCustomers(null, 20, "q", 1)).thenReturn(result);

        var response = new CustomerController(service).list(null, 20, "q", 1);

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        assertThat(response.getBody()).isSameAs(result);
    }

    @Test
    void orderController_list_delegatesToService() {
        OrderService service = mock(OrderService.class);
        var result = new OrderListResult(List.of(), 1, 20, 0, 0, false);
        when(service.listOrders(null, 1, 20, "placedAt", "desc", null, null, null, null, null, null))
                .thenReturn(result);

        var response = new OrderController(service)
                .list(null, 1, 20, "placedAt", "desc", null, null, null, null, null, null);

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        assertThat(response.getBody()).isSameAs(result);
    }

    @Test
    void orderController_create_returns201() {
        OrderService service = mock(OrderService.class);
        Map<String, Object> created = Map.of("id", 1, "total", new BigDecimal("5.00"));
        when(service.createOrder(any(CreateOrderRequest.class))).thenReturn(created);

        var response = new OrderController(service).create(
                new CreateOrderRequest(1, 1, null, null,
                        List.of(new CreateOrderRequest.Item(1, 1, BigDecimal.ONE, null))));

        assertThat(response.getStatusCode().value()).isEqualTo(201);
        assertThat(response.getBody()).isSameAs(created);
    }

    @Test
    void regionController_delegatesToService() {
        RegionService service = mock(RegionService.class);
        var regions = List.of(new RegionDTO(1, "US-E", "US East"));
        when(service.listRegions()).thenReturn(regions);

        var response = new RegionController(service).list();

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        assertThat(response.getBody()).isSameAs(regions);
    }
}
