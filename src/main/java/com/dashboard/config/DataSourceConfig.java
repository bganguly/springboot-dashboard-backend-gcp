package com.dashboard.config;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import javax.sql.DataSource;

@Configuration
public class DataSourceConfig {

    @Bean
    public DataSource dataSource(@Value("${DATABASE_URL}") String databaseUrl) {
        // Accept postgresql:// (Heroku/GCP style) or jdbc:postgresql://
        String jdbcUrl = databaseUrl.startsWith("postgresql://")
                ? "jdbc:" + databaseUrl
                : databaseUrl;
        var config = new HikariConfig();
        config.setJdbcUrl(jdbcUrl);
        config.setMaximumPoolSize(10);
        config.setMinimumIdle(2);
        config.setConnectionTimeout(30_000);
        return new HikariDataSource(config);
    }
}
