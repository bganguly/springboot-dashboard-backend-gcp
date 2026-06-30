package com.dashboard.dto;

import java.util.List;

public record CustomerListResult(List<CustomerDTO> data, Integer nextCursor, boolean hasMore) {}
