-- ============================================================================
-- Synthetic User Lab - indexes
-- Migration: 006_indexes_and_constraints.sql
--
-- Most lookup queries filter by locale (sometimes gender), order by id, and
-- read name + weight. Covering indexes keep weighted selection cheap even
-- when a benchmark requests many thousands of users.
-- ============================================================================

CREATE INDEX IF NOT EXISTS first_names_lookup_idx
    ON sul.first_names (locale_code, gender, id) INCLUDE (name, weight);

CREATE INDEX IF NOT EXISTS middle_names_lookup_idx
    ON sul.middle_names (locale_code, id) INCLUDE (name, weight);

CREATE INDEX IF NOT EXISTS last_names_lookup_idx
    ON sul.last_names (locale_code, id) INCLUDE (name, weight);

CREATE INDEX IF NOT EXISTS titles_lookup_idx
    ON sul.titles (locale_code, id) INCLUDE (title, gender, weight);

CREATE INDEX IF NOT EXISTS street_names_lookup_idx
    ON sul.street_names (locale_code, id) INCLUDE (name, weight);

CREATE INDEX IF NOT EXISTS cities_lookup_idx
    ON sul.cities (locale_code, id) INCLUDE (name, region_id, postal_prefix, weight);

CREATE INDEX IF NOT EXISTS cities_region_idx ON sul.cities (region_id);

CREATE INDEX IF NOT EXISTS email_domains_lookup_idx
    ON sul.email_domains (locale_code, id) INCLUDE (domain, weight);

CREATE INDEX IF NOT EXISTS email_patterns_lookup_idx
    ON sul.email_patterns (locale_code, id) INCLUDE (pattern, weight);

CREATE INDEX IF NOT EXISTS phone_formats_lookup_idx
    ON sul.phone_formats (locale_code, id) INCLUDE (format_pattern, weight);

CREATE INDEX IF NOT EXISTS eye_colors_lookup_idx
    ON sul.eye_colors (locale_code, id) INCLUDE (color_name, weight);

CREATE INDEX IF NOT EXISTS hair_colors_lookup_idx
    ON sul.hair_colors (locale_code, id) INCLUDE (color_name, weight);
