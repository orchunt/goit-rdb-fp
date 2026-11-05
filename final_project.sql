-- =====================================================================
-- goit-rdb-fp: фінальний проєкт, датасет infectious_cases (PostgreSQL 16)
--
-- Запуск у psql з кореня репозиторію:
--     psql -d <database> -f final_project.sql
-- Notebook fp_pandemic.ipynb виконує ті самі блоки (розмітка "-- @block").
-- =====================================================================


-- @block task1_schema
-- =====================================================================
-- Завдання 1. Схема pandemic і імпорт даних
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS pandemic;
SET search_path TO pandemic;

DROP FUNCTION IF EXISTS fn_years_since(INTEGER);
DROP FUNCTION IF EXISTS fn_avg_cases_per_period(NUMERIC, INTEGER);
DROP TABLE IF EXISTS disease_cases CASCADE;
DROP TABLE IF EXISTS entities CASCADE;
DROP TABLE IF EXISTS infectious_cases CASCADE;

-- Raw table mirrors the CSV 1:1. Every column is TEXT so that the import never fails
-- and the original values (including empty strings) are preserved as they are in the file.
-- Column names are the CSV header in lower case (PostgreSQL folds unquoted identifiers).
CREATE TABLE infectious_cases (
    entity               TEXT,
    code                 TEXT,
    year                 TEXT,
    number_yaws          TEXT,
    polio_cases          TEXT,
    cases_guinea_worm    TEXT,
    number_rabies        TEXT,
    number_malaria       TEXT,
    number_hiv           TEXT,
    number_tuberculosis  TEXT,
    number_smallpox      TEXT,
    number_cholera_cases TEXT
);


-- @block task1_import psql-only
-- In psql: client-side \copy reads the file from the local machine.
-- FORCE_NOT_NULL keeps empty fields as '' (exactly as in the file) instead of NULL.
\copy infectious_cases FROM 'data/infectious_cases.csv' WITH (FORMAT csv, HEADER true, FORCE_NOT_NULL (entity, code, year, number_yaws, polio_cases, cases_guinea_worm, number_rabies, number_malaria, number_hiv, number_tuberculosis, number_smallpox, number_cholera_cases))


-- @block task1_preview
SELECT *
FROM infectious_cases
LIMIT 10;


-- @block task1_profile
-- Structure overview: row count, distinct entities, year range and empty values per column
SELECT
    COUNT(*)                                           AS n_rows,
    COUNT(DISTINCT entity)                             AS n_entities,
    COUNT(DISTINCT NULLIF(code, ''))                   AS n_codes,
    MIN(year::INTEGER)                                 AS min_year,
    MAX(year::INTEGER)                                 AS max_year,
    COUNT(*) FILTER (WHERE code = '')                  AS empty_code,
    COUNT(*) FILTER (WHERE number_rabies = '')         AS empty_rabies,
    COUNT(*) FILTER (WHERE number_malaria = '')        AS empty_malaria,
    COUNT(*) FILTER (WHERE polio_cases = '')           AS empty_polio,
    COUNT(*) FILTER (WHERE number_yaws = '')           AS empty_yaws
FROM infectious_cases;


-- @block task2_ddl
-- =====================================================================
-- Завдання 2. Нормалізація до 3НФ
--
-- Ключ вихідної таблиці: (entity, year). Функціональні залежності:
--   entity -> code          (у кожної сутності рівно один код; перевірено в task2_fd_check)
--   (entity, year) -> number_* (показники конкретного року)
-- code залежить лише від частини ключа (entity), а не від усього ключа, тобто це
-- часткова залежність: порушення 2НФ (а отже й 3НФ). Звідси повтор пари (entity, code)
-- у кожному з ~40 років сутності. Декомпозиція:
--   entities(entity_id PK, entity_name UNIQUE, entity_code UNIQUE)
--   disease_cases(entity_id FK, year, number_*; PK (entity_id, year))
-- =====================================================================
CREATE TABLE entities (
    entity_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entity_name  TEXT NOT NULL UNIQUE,
    -- NULL for aggregates (World regions, income groups) that have no code in the source;
    -- UNIQUE still allows several NULLs
    entity_code  TEXT UNIQUE
        CHECK (entity_code ~ '^([A-Z]{3}|OWID_[A-Z]{3})$')
);

CREATE TABLE disease_cases (
    entity_id            INTEGER  NOT NULL REFERENCES entities (entity_id),
    year                 SMALLINT NOT NULL CHECK (year BETWEEN 1900 AND 2100),
    number_yaws          NUMERIC CHECK (number_yaws          >= 0),
    polio_cases          NUMERIC CHECK (polio_cases          >= 0),
    cases_guinea_worm    NUMERIC CHECK (cases_guinea_worm    >= 0),
    number_rabies        NUMERIC CHECK (number_rabies        >= 0),
    number_malaria       NUMERIC CHECK (number_malaria       >= 0),
    number_hiv           NUMERIC CHECK (number_hiv           >= 0),
    number_tuberculosis  NUMERIC CHECK (number_tuberculosis  >= 0),
    number_smallpox      NUMERIC CHECK (number_smallpox      >= 0),
    number_cholera_cases NUMERIC CHECK (number_cholera_cases >= 0),
    PRIMARY KEY (entity_id, year)
);


-- @block task2_fd_check
-- Verify the functional dependency entity -> code before decomposing:
-- both counts must be 0, otherwise entities(entity_name UNIQUE) would lose information
SELECT
    (SELECT COUNT(*) FROM (
        SELECT entity FROM infectious_cases GROUP BY entity HAVING COUNT(DISTINCT code) > 1
    ) AS x) AS entities_with_several_codes,
    (SELECT COUNT(*) FROM (
        SELECT code FROM infectious_cases WHERE code <> '' GROUP BY code HAVING COUNT(DISTINCT entity) > 1
    ) AS y) AS codes_with_several_entities,
    (SELECT COUNT(*) FROM (
        SELECT entity, year FROM infectious_cases GROUP BY entity, year HAVING COUNT(*) > 1
    ) AS z) AS duplicate_entity_year;


-- @block task2_load
-- Empty strings become SQL NULL ("no data"), and numeric text is cast to NUMERIC
INSERT INTO entities (entity_name, entity_code)
SELECT DISTINCT
    entity,
    NULLIF(code, '')
FROM infectious_cases
ORDER BY entity;

INSERT INTO disease_cases (
    entity_id, year,
    number_yaws, polio_cases, cases_guinea_worm, number_rabies, number_malaria,
    number_hiv, number_tuberculosis, number_smallpox, number_cholera_cases
)
SELECT
    e.entity_id,
    ic.year::SMALLINT,
    NULLIF(ic.number_yaws, '')::NUMERIC,
    NULLIF(ic.polio_cases, '')::NUMERIC,
    NULLIF(ic.cases_guinea_worm, '')::NUMERIC,
    NULLIF(ic.number_rabies, '')::NUMERIC,
    NULLIF(ic.number_malaria, '')::NUMERIC,
    NULLIF(ic.number_hiv, '')::NUMERIC,
    NULLIF(ic.number_tuberculosis, '')::NUMERIC,
    NULLIF(ic.number_smallpox, '')::NUMERIC,
    NULLIF(ic.number_cholera_cases, '')::NUMERIC
FROM infectious_cases AS ic
JOIN entities AS e
    ON e.entity_name = ic.entity;


-- @block task2_counts
SELECT 'infectious_cases (raw)' AS table_name, COUNT(*) AS n_rows FROM infectious_cases
UNION ALL
SELECT 'entities', COUNT(*) FROM entities
UNION ALL
SELECT 'disease_cases', COUNT(*) FROM disease_cases;


-- @block task2_lossless
-- Lossless-join check: joining the two normalized tables back must reproduce the raw table
-- exactly, in both directions (0 rows on each side)
WITH rebuilt AS (
    SELECT
        e.entity_name AS entity,
        COALESCE(e.entity_code, '') AS code,
        dc.year::TEXT AS year,
        dc.number_rabies,
        dc.number_malaria,
        dc.polio_cases
    FROM disease_cases AS dc
    JOIN entities AS e USING (entity_id)
),
original AS (
    SELECT
        entity,
        code,
        year,
        NULLIF(number_rabies, '')::NUMERIC  AS number_rabies,
        NULLIF(number_malaria, '')::NUMERIC AS number_malaria,
        NULLIF(polio_cases, '')::NUMERIC    AS polio_cases
    FROM infectious_cases
)
SELECT
    (SELECT COUNT(*) FROM (SELECT * FROM original EXCEPT SELECT * FROM rebuilt) AS a) AS only_in_raw,
    (SELECT COUNT(*) FROM (SELECT * FROM rebuilt EXCEPT SELECT * FROM original) AS b) AS only_in_normalized;


-- @block task2_preview
SELECT
    dc.entity_id,
    e.entity_name,
    e.entity_code,
    dc.year,
    dc.number_rabies,
    dc.number_malaria,
    dc.polio_cases
FROM disease_cases AS dc
JOIN entities AS e USING (entity_id)
ORDER BY e.entity_name, dc.year
LIMIT 10;


-- @block task3_rabies
-- =====================================================================
-- Завдання 3. Статистика Number_rabies для кожної Entity / Code
--
-- WHERE number_rabies IS NOT NULL is essential: 19 entities have no rabies data at all,
-- AVG is NULL for them, and ORDER BY ... DESC puts NULLs FIRST in PostgreSQL by default,
-- so without the filter the "top 10" would consist of empty rows (see task3_nulls_pitfall)
-- =====================================================================
SELECT
    e.entity_id,
    e.entity_name,
    e.entity_code,
    ROUND(AVG(dc.number_rabies), 2) AS avg_rabies,
    ROUND(MIN(dc.number_rabies), 2) AS min_rabies,
    ROUND(MAX(dc.number_rabies), 2) AS max_rabies,
    ROUND(SUM(dc.number_rabies), 2) AS sum_rabies,
    COUNT(dc.number_rabies)         AS n_years
FROM disease_cases AS dc
JOIN entities AS e USING (entity_id)
WHERE dc.number_rabies IS NOT NULL
GROUP BY e.entity_id, e.entity_name, e.entity_code
ORDER BY AVG(dc.number_rabies) DESC
LIMIT 10;


-- @block task3_nulls_pitfall
-- The same aggregation without the IS NOT NULL filter: NULL averages float to the top
SELECT
    e.entity_name,
    e.entity_code,
    AVG(dc.number_rabies) AS avg_rabies
FROM disease_cases AS dc
JOIN entities AS e USING (entity_id)
GROUP BY e.entity_name, e.entity_code
ORDER BY avg_rabies DESC
LIMIT 10;


-- @block task3_countries_only
-- Additional view: the top 10 is dominated by aggregates (World, WB/WHO regions, G20);
-- restricting to ISO-3 country codes shows individual countries
SELECT
    e.entity_name,
    e.entity_code,
    ROUND(AVG(dc.number_rabies), 2) AS avg_rabies,
    ROUND(MIN(dc.number_rabies), 2) AS min_rabies,
    ROUND(MAX(dc.number_rabies), 2) AS max_rabies,
    ROUND(SUM(dc.number_rabies), 2) AS sum_rabies
FROM disease_cases AS dc
JOIN entities AS e USING (entity_id)
WHERE dc.number_rabies IS NOT NULL
  AND e.entity_code ~ '^[A-Z]{3}$'
GROUP BY e.entity_name, e.entity_code
ORDER BY AVG(dc.number_rabies) DESC
LIMIT 10;


-- @block task4_year_diff
-- =====================================================================
-- Завдання 4. Дата 1 січня року, поточна дата і різниця в роках (вбудовані функції)
--   MAKE_DATE(year, 1, 1)        -> дата першого січня відповідного року
--   CURRENT_DATE                 -> поточна дата
--   AGE(CURRENT_DATE, first_jan) -> інтервал; EXTRACT(YEAR ...) дає кількість повних років
-- =====================================================================
SELECT
    e.entity_name,
    dc.year,
    MAKE_DATE(dc.year, 1, 1) AS first_jan_date,
    CURRENT_DATE AS today,
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(dc.year, 1, 1)))::INTEGER AS years_diff
FROM disease_cases AS dc
JOIN entities AS e USING (entity_id)
ORDER BY e.entity_name, dc.year
LIMIT 10;


-- @block task5_functions
-- =====================================================================
-- Завдання 5. Власні функції
-- =====================================================================

-- Years between January 1 of p_year and today.
-- STABLE (not IMMUTABLE): the result depends on CURRENT_DATE, i.e. on the day it is called.
-- STRICT: NULL input -> NULL result without evaluating the body.
CREATE OR REPLACE FUNCTION fn_years_since(p_year INTEGER)
RETURNS INTEGER
LANGUAGE sql
STABLE
STRICT
AS $$
    SELECT EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(p_year, 1, 1)))::INTEGER;
$$;

-- Average number of cases per period: yearly cases divided by an arbitrary divisor
-- (12 = month, 4 = quarter, 2 = half-year).
-- IMMUTABLE: depends only on its arguments. A divisor <= 0 is rejected explicitly
-- instead of failing with a generic "division by zero" or returning a negative average.
CREATE OR REPLACE FUNCTION fn_avg_cases_per_period(p_cases_per_year NUMERIC, p_divisor INTEGER)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $$
BEGIN
    IF p_divisor <= 0 THEN
        RAISE EXCEPTION 'p_divisor must be a positive integer, got %', p_divisor;
    END IF;
    RETURN p_cases_per_year / p_divisor;
END;
$$;


-- @block task5_years_since_use
SELECT
    e.entity_name,
    dc.year,
    fn_years_since(dc.year) AS years_since
FROM disease_cases AS dc
JOIN entities AS e USING (entity_id)
ORDER BY e.entity_name, dc.year
LIMIT 10;


-- @block task5_years_since_check
-- The function must agree with the built-in expression from Task 4 for every row
SELECT
    COUNT(*) AS rows_checked,
    COUNT(*) FILTER (
        WHERE fn_years_since(year)
              IS DISTINCT FROM EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(year, 1, 1)))::INTEGER
    ) AS mismatches,
    fn_years_since(1996) AS example_1996
FROM disease_cases;


-- @block task5_avg_cases_use
-- Only records whose number of cases is numeric: on the raw TEXT table the regex filter
-- drops empty strings (and would drop any other non-numeric text) before the cast
SELECT
    entity,
    year,
    number_rabies::NUMERIC AS rabies_per_year,
    ROUND(fn_avg_cases_per_period(number_rabies::NUMERIC, 12), 4) AS avg_per_month,
    ROUND(fn_avg_cases_per_period(number_rabies::NUMERIC, 4), 4)  AS avg_per_quarter,
    ROUND(fn_avg_cases_per_period(number_rabies::NUMERIC, 2), 4)  AS avg_per_half_year
FROM infectious_cases
WHERE number_rabies ~ '^[0-9]+(\.[0-9]+)?$'
ORDER BY entity, year
LIMIT 10;


-- @block task5_avg_cases_check
-- Consistency: the numeric filter on the raw table selects exactly the non-NULL values of the
-- normalized table, and month * 12 = quarter * 4 = half-year * 2 = yearly value for every row.
-- NUMERIC division is rounded to a finite scale (2.145772 / 12 * 12 = 2.14577199999...),
-- so the round trip is compared with a tolerance instead of exact equality
SELECT
    (SELECT COUNT(*) FROM infectious_cases WHERE number_rabies ~ '^[0-9]+(\.[0-9]+)?$') AS numeric_raw_rows,
    (SELECT COUNT(*) FROM infectious_cases WHERE number_rabies = '')                    AS empty_raw_rows,
    (SELECT COUNT(number_rabies) FROM disease_cases)                                    AS not_null_normalized_rows,
    (SELECT COUNT(*) FROM disease_cases
     WHERE number_rabies IS NOT NULL
       AND GREATEST(
               ABS(fn_avg_cases_per_period(number_rabies, 12) * 12 - number_rabies),
               ABS(fn_avg_cases_per_period(number_rabies, 4)  * 4  - number_rabies),
               ABS(fn_avg_cases_per_period(number_rabies, 2)  * 2  - number_rabies)
           ) > 1e-9
    ) AS period_mismatches;
