package com.dashboard.service;

import com.dashboard.dto.CustomerDTO;
import com.dashboard.dto.CustomerListResult;
import com.dashboard.dto.RegionDTO;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@Service
@RequiredArgsConstructor
public class CustomerService {

    private final NamedParameterJdbcTemplate jdbc;

    public CustomerListResult listCustomers(Integer cursor, int limit, String q, Integer regionId) {
        limit = Math.min(Math.max(limit, 1), 100);
        var params = new MapSqlParameterSource();
        List<String> clauses = new ArrayList<>();

        if (cursor != null) { clauses.add("c.id > :cursor"); params.addValue("cursor", cursor); }
        if (q != null && !q.isBlank()) {
            clauses.add("(c.\"firstName\" || ' ' || c.\"lastName\" || ' ' || c.email) ILIKE :q");
            params.addValue("q", "%" + q.strip() + "%");
        }
        if (regionId != null) { clauses.add("c.\"regionId\" = :regionId"); params.addValue("regionId", regionId); }

        String where = clauses.isEmpty() ? "" : "WHERE " + String.join(" AND ", clauses);
        params.addValue("limit", limit + 1);

        String sql = """
                SELECT c.id, c.email, c."firstName", c."lastName", c.phone, c."createdAt",
                       r.id AS r_id, r.code, r.name AS r_name
                FROM customers c
                JOIN regions r ON r.id = c."regionId"
                """ + where + " ORDER BY c.id LIMIT :limit";

        List<Map<String, Object>> rows = jdbc.queryForList(sql, params);
        boolean hasMore = rows.size() > limit;
        if (hasMore) rows = rows.subList(0, limit);

        List<CustomerDTO> data = rows.stream().map(r -> new CustomerDTO(
                ((Number) r.get("id")).intValue(),
                (String) r.get("email"),
                (String) r.get("firstName"),
                (String) r.get("lastName"),
                (String) r.get("phone"),
                new RegionDTO(((Number) r.get("r_id")).intValue(), (String) r.get("code"), (String) r.get("r_name")),
                r.get("createdAt") != null ? r.get("createdAt").toString() : null
        )).toList();

        Integer nextCursor = hasMore && !data.isEmpty() ? data.getLast().id() : null;
        return new CustomerListResult(data, nextCursor, hasMore);
    }
}
