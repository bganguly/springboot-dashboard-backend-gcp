package com.dashboard.dto;

public record CustomerDTO(
        int id,
        String email,
        String firstName,
        String lastName,
        String phone,
        RegionDTO region,
        String createdAt
) {}
