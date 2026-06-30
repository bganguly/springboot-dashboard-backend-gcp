package com.dashboard.service;

import com.dashboard.dto.RegionDTO;
import com.dashboard.entity.Region;
import com.dashboard.repository.RegionRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@RequiredArgsConstructor
public class RegionService {

    private final RegionRepository regionRepository;

    public List<RegionDTO> listRegions() {
        return regionRepository.findAll().stream()
                .sorted((a, b) -> a.getCode().compareTo(b.getCode()))
                .map(r -> new RegionDTO(r.getId(), r.getCode(), r.getName()))
                .toList();
    }
}
