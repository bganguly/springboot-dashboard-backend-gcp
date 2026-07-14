package com.dashboard.controller;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api")
public class RuntimeController {

    @Value("${BACKEND_RUNTIME:cr}")
    private String runtime;

    @GetMapping("/runtime")
    public Map<String, String> runtime() {
        return Map.of("runtime", runtime);
    }
}
