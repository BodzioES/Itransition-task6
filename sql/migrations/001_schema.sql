-- ============================================================================
-- Synthetic User Lab - schema
-- Migration: 001_schema.sql
-- Target: PostgreSQL 15+
--
-- All generator objects live in the dedicated `sul` schema. Lookup data is
-- shared across locales and partitioned by locale_code, so adding a locale
-- means adding data rather than adding tables.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS sul;

COMMENT ON SCHEMA sul IS
    'Synthetic User Lab: lookup data and SQL-native deterministic fake-user generation.';

-- pgcrypto provides SHA-256 digests. This extension is mandatory. The
-- migration intentionally fails loudly if the database cannot install it.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

-- ---------------------------------------------------------------------------
-- Locale configuration
-- ---------------------------------------------------------------------------
CREATE TABLE sul.locales (
    locale_code                       VARCHAR(5)  PRIMARY KEY,
    display_order                     SMALLINT    NOT NULL,
    language_code                     VARCHAR(8)  NOT NULL,
    language_name                     TEXT        NOT NULL,
    country_code                      CHAR(2)     NOT NULL,
    country_name                      TEXT        NOT NULL,
    default_phone_prefix              VARCHAR(8)  NOT NULL,
    full_name_format                  TEXT        NOT NULL,
    street_address_format             TEXT        NOT NULL,
    address_format                    TEXT        NOT NULL,
    middle_name_probability           NUMERIC(5, 4) NOT NULL,
    title_probability                 NUMERIC(5, 4) NOT NULL,
    postal_code_length                SMALLINT    NOT NULL,
    postal_code_regex                 TEXT        NOT NULL,
    house_number_min                  INTEGER     NOT NULL,
    house_number_max                  INTEGER     NOT NULL,
    house_number_suffix_probability   NUMERIC(5, 4) NOT NULL,
    CONSTRAINT locales_locale_code_format
        CHECK (locale_code ~ '^[a-z]{2}_[A-Z]{2}$'),
    CONSTRAINT locales_probabilities
        CHECK (middle_name_probability BETWEEN 0 AND 1
           AND title_probability BETWEEN 0 AND 1
           AND house_number_suffix_probability BETWEEN 0 AND 1),
    CONSTRAINT locales_postal_length
        CHECK (postal_code_length BETWEEN 3 AND 10),
    CONSTRAINT locales_house_numbers
        CHECK (house_number_min > 0 AND house_number_max >= house_number_min),
    CONSTRAINT locales_display_order_unique UNIQUE (display_order)
);

COMMENT ON TABLE sul.locales IS
    'Locale-level configuration: country, formatting patterns and optional-field probabilities.';
COMMENT ON COLUMN sul.locales.address_format IS
    'Full address pattern using {street_address}, {city}, {region_name}, {region_code}, {postal_code}, {country}.';
COMMENT ON COLUMN sul.locales.street_address_format IS
    'Street line pattern using {street_name}, {house_number}, {house_suffix}.';
COMMENT ON COLUMN sul.locales.full_name_format IS
    'Name pattern using {first}, {middle}, {last}. Empty optional components are removed.';

-- ---------------------------------------------------------------------------
-- Regions and cities
-- ---------------------------------------------------------------------------
CREATE TABLE sul.regions (
    id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    locale_code  VARCHAR(5) NOT NULL REFERENCES sul.locales(locale_code) ON DELETE CASCADE,
    name         TEXT       NOT NULL,
    code         TEXT       NOT NULL,
    CONSTRAINT regions_locale_code_unique UNIQUE (locale_code, code),
    CONSTRAINT regions_id_locale_unique UNIQUE (id, locale_code)
);

COMMENT ON TABLE sul.regions IS 'State/province/Bundesland names and display codes.';

CREATE TABLE sul.cities (
    id             INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    locale_code    VARCHAR(5) NOT NULL,
    region_id      INTEGER    NOT NULL,
    name           TEXT       NOT NULL,
    postal_prefix  VARCHAR(10) NOT NULL,
    weight         INTEGER    NOT NULL DEFAULT 50 CHECK (weight > 0),
    CONSTRAINT cities_region_fk
        FOREIGN KEY (region_id, locale_code)
        REFERENCES sul.regions(id, locale_code) ON DELETE CASCADE,
    CONSTRAINT cities_locale_name_unique UNIQUE (locale_code, region_id, name),
    CONSTRAINT cities_postal_prefix_format CHECK (postal_prefix ~ '^[0-9]{2,10}$')
);

COMMENT ON TABLE sul.cities IS
    'Locale-aware cities with region and postal-code prefix used to build plausible postal codes.';

-- ---------------------------------------------------------------------------
-- Name, title and street lookups
-- ---------------------------------------------------------------------------
CREATE TABLE sul.first_names (
    id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    locale_code  VARCHAR(5) NOT NULL REFERENCES sul.locales(locale_code) ON DELETE CASCADE,
    name         TEXT       NOT NULL,
    gender       CHAR(1)    NOT NULL,
    weight       INTEGER    NOT NULL DEFAULT 50 CHECK (weight > 0),
    CONSTRAINT first_names_gender_check CHECK (gender IN ('F', 'M')),
    CONSTRAINT first_names_unique UNIQUE (locale_code, name, gender)
);

CREATE TABLE sul.middle_names (
    id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    locale_code  VARCHAR(5) NOT NULL REFERENCES sul.locales(locale_code) ON DELETE CASCADE,
    name         TEXT       NOT NULL,
    weight       INTEGER    NOT NULL DEFAULT 50 CHECK (weight > 0),
    CONSTRAINT middle_names_unique UNIQUE (locale_code, name)
);

CREATE TABLE sul.last_names (
    id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    locale_code  VARCHAR(5) NOT NULL REFERENCES sul.locales(locale_code) ON DELETE CASCADE,
    name         TEXT       NOT NULL,
    weight       INTEGER    NOT NULL DEFAULT 50 CHECK (weight > 0),
    CONSTRAINT last_names_unique UNIQUE (locale_code, name)
);

CREATE TABLE sul.titles (
    id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    locale_code  VARCHAR(5) NOT NULL REFERENCES sul.locales(locale_code) ON DELETE CASCADE,
    title        TEXT       NOT NULL,
    gender       CHAR(1),
    weight       INTEGER    NOT NULL DEFAULT 50 CHECK (weight > 0),
    CONSTRAINT titles_gender_check CHECK (gender IS NULL OR gender IN ('F', 'M')),
    CONSTRAINT titles_unique UNIQUE (locale_code, title)
);

COMMENT ON TABLE sul.titles IS
    'Optional salutations/titles. A NULL gender means the title applies to every gender.';

CREATE TABLE sul.street_names (
    id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    locale_code  VARCHAR(5) NOT NULL REFERENCES sul.locales(locale_code) ON DELETE CASCADE,
    name         TEXT       NOT NULL,
    weight       INTEGER    NOT NULL DEFAULT 50 CHECK (weight > 0),
    CONSTRAINT street_names_unique UNIQUE (locale_code, name)
);

-- ---------------------------------------------------------------------------
-- Contact and physical-attribute lookups
-- ---------------------------------------------------------------------------
CREATE TABLE sul.email_domains (
    id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    locale_code  VARCHAR(5) REFERENCES sul.locales(locale_code) ON DELETE CASCADE,
    domain       TEXT       NOT NULL,
    weight       INTEGER    NOT NULL DEFAULT 50 CHECK (weight > 0),
    CONSTRAINT email_domains_lowercase CHECK (domain = lower(domain)),
    CONSTRAINT email_domains_example_only
        CHECK (domain ~ '^example\.(com|net|org)$')
);

COMMENT ON TABLE sul.email_domains IS
    'RFC 2606 example domains only. A NULL locale_code makes a domain shared by all locales.';

CREATE TABLE sul.email_patterns (
    id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    locale_code  VARCHAR(5) NOT NULL REFERENCES sul.locales(locale_code) ON DELETE CASCADE,
    pattern      TEXT       NOT NULL,
    weight       INTEGER    NOT NULL DEFAULT 50 CHECK (weight > 0),
    CONSTRAINT email_patterns_unique UNIQUE (locale_code, pattern),
    CONSTRAINT email_patterns_tokens
        CHECK (pattern ~ '\{(first|last|fi)\}' AND position('@' IN pattern) = 0)
);

COMMENT ON TABLE sul.email_patterns IS
    'Local-part patterns using {first}, {last} and {fi}. A deterministic row suffix is appended.';

CREATE TABLE sul.phone_formats (
    id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    locale_code  VARCHAR(5) NOT NULL REFERENCES sul.locales(locale_code) ON DELETE CASCADE,
    format_pattern TEXT     NOT NULL,
    weight       INTEGER    NOT NULL DEFAULT 50 CHECK (weight > 0),
    CONSTRAINT phone_formats_unique UNIQUE (locale_code, format_pattern),
    CONSTRAINT phone_formats_hash CHECK (position('#' IN format_pattern) > 0)
);

COMMENT ON TABLE sul.phone_formats IS
    'Display formats. Every # is replaced by a deterministic digit. Patterns use fictional ranges.';

CREATE TABLE sul.eye_colors (
    id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    locale_code  VARCHAR(5) REFERENCES sul.locales(locale_code) ON DELETE CASCADE,
    color_name   TEXT       NOT NULL,
    weight       INTEGER    NOT NULL DEFAULT 50 CHECK (weight > 0),
    CONSTRAINT eye_colors_unique UNIQUE (locale_code, color_name)
);

CREATE TABLE sul.hair_colors (
    id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    locale_code  VARCHAR(5) REFERENCES sul.locales(locale_code) ON DELETE CASCADE,
    color_name   TEXT       NOT NULL,
    weight       INTEGER    NOT NULL DEFAULT 50 CHECK (weight > 0),
    CONSTRAINT hair_colors_unique UNIQUE (locale_code, color_name)
);

COMMENT ON TABLE sul.eye_colors IS
    'Locale-localised eye colour labels. A NULL locale_code would apply to all locales.';
COMMENT ON TABLE sul.hair_colors IS
    'Locale-localised hair colour labels, providing a second categorical physical attribute.';

-- ---------------------------------------------------------------------------
-- Body statistics used by the deterministic normal distribution
-- ---------------------------------------------------------------------------
CREATE TABLE sul.body_statistics (
    locale_code      VARCHAR(5) NOT NULL REFERENCES sul.locales(locale_code) ON DELETE CASCADE,
    gender           CHAR(1)    NOT NULL,
    height_mean_cm   NUMERIC(5, 2) NOT NULL,
    height_sd_cm     NUMERIC(5, 2) NOT NULL,
    height_min_cm    NUMERIC(5, 2) NOT NULL,
    height_max_cm    NUMERIC(5, 2) NOT NULL,
    weight_mean_kg   NUMERIC(5, 2) NOT NULL,
    weight_sd_kg     NUMERIC(5, 2) NOT NULL,
    weight_min_kg    NUMERIC(5, 2) NOT NULL,
    weight_max_kg    NUMERIC(5, 2) NOT NULL,
    PRIMARY KEY (locale_code, gender),
    CONSTRAINT body_statistics_gender_check CHECK (gender IN ('F', 'M')),
    CONSTRAINT body_statistics_height
        CHECK (height_sd_cm > 0 AND height_min_cm < height_mean_cm AND height_mean_cm < height_max_cm),
    CONSTRAINT body_statistics_weight
        CHECK (weight_sd_kg > 0 AND weight_min_kg < weight_mean_kg AND weight_mean_kg < weight_max_kg)
);

-- ---------------------------------------------------------------------------
-- Public lookup coverage view (used by health checks, docs and tests)
-- ---------------------------------------------------------------------------
CREATE VIEW sul.lookup_coverage AS
SELECT l.locale_code,
       (SELECT count(*) FROM sul.first_names   x WHERE x.locale_code = l.locale_code) AS first_names,
       (SELECT count(*) FROM sul.middle_names  x WHERE x.locale_code = l.locale_code) AS middle_names,
       (SELECT count(*) FROM sul.last_names    x WHERE x.locale_code = l.locale_code) AS last_names,
       (SELECT count(*) FROM sul.titles        x WHERE x.locale_code = l.locale_code) AS titles,
       (SELECT count(*) FROM sul.street_names  x WHERE x.locale_code = l.locale_code) AS street_names,
       (SELECT count(*) FROM sul.cities        x WHERE x.locale_code = l.locale_code) AS cities,
       (SELECT count(*) FROM sul.regions       x WHERE x.locale_code = l.locale_code) AS regions,
       (SELECT count(*) FROM sul.email_domains x
         WHERE x.locale_code = l.locale_code OR x.locale_code IS NULL) AS email_domains,
       (SELECT count(*) FROM sul.email_patterns x WHERE x.locale_code = l.locale_code) AS email_patterns,
       (SELECT count(*) FROM sul.phone_formats x WHERE x.locale_code = l.locale_code) AS phone_formats,
       (SELECT count(*) FROM sul.eye_colors    x
         WHERE x.locale_code = l.locale_code OR x.locale_code IS NULL) AS eye_colors,
       (SELECT count(*) FROM sul.hair_colors   x
         WHERE x.locale_code = l.locale_code OR x.locale_code IS NULL) AS hair_colors
FROM sul.locales l
ORDER BY l.display_order;

COMMENT ON VIEW sul.lookup_coverage IS
    'One row per locale with lookup counts. Use it to verify seed coverage after adding data.';
