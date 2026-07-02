package com.dashboard.service;

import com.dashboard.entity.Region;
import com.dashboard.repository.RegionRepository;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class RegionServiceTest {

    @Test
    void listRegions_sortsByCode() {
        RegionRepository repo = mock(RegionRepository.class);
        Region b = new Region();
        b.setId(2);
        b.setCode("EU-W");
        b.setName("EU West");
        Region a = new Region();
        a.setId(1);
        a.setCode("AP-S");
        a.setName("AP South");
        when(repo.findAll()).thenReturn(List.of(b, a));

        var result = new RegionService(repo).listRegions();

        assertThat(result).extracting("code").containsExactly("AP-S", "EU-W");
        assertThat(result.get(0).name()).isEqualTo("AP South");
    }

    @Test
    void listRegions_emptyRepository_returnsEmptyList() {
        RegionRepository repo = mock(RegionRepository.class);
        when(repo.findAll()).thenReturn(List.of());

        assertThat(new RegionService(repo).listRegions()).isEmpty();
    }
}
