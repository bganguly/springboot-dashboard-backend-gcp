package com.dashboard.config;

import org.junit.jupiter.api.Test;
import org.springframework.web.servlet.config.annotation.CorsRegistry;

import static org.mockito.Answers.RETURNS_DEEP_STUBS;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

class WebConfigTest {

    @Test
    void addCorsMappings_registersApiMapping() {
        CorsRegistry registry = mock(CorsRegistry.class, RETURNS_DEEP_STUBS);

        new WebConfig().addCorsMappings(registry);

        verify(registry).addMapping("/api/**");
    }
}
