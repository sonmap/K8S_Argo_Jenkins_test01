package com.example.demo;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class CustomerController {

    private final JdbcTemplate jdbcTemplate;

    public CustomerController(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @GetMapping("/health")
    public Map<String, Object> health() {
        Integer db = jdbcTemplate.queryForObject("SELECT 1", Integer.class);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("application", "demo-backend");
        result.put("status", "UP");
        result.put("database", db != null && db == 1 ? "MYSQL UP" : "MYSQL UNKNOWN");
        return result;
    }

    @GetMapping("/customers")
    public List<Map<String, Object>> customers(
            @RequestParam(name = "name", required = false, defaultValue = "") String name) {

        String keyword = name.trim();
        if (keyword.isEmpty()) {
            return jdbcTemplate.queryForList(
                    "SELECT id, name, email, grade, created_at FROM customers ORDER BY id");
        }

        return jdbcTemplate.queryForList(
                "SELECT id, name, email, grade, created_at FROM customers " +
                        "WHERE name LIKE ? ORDER BY id",
                "%" + keyword + "%");
    }
}
