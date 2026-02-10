-- Пример фильтрации данных от аномальных значений
-- Аномальные значения (выбросы) по значению перцентилей:
  WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
-- Объявления без выбросов:
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM filtered_id);
-- Задача 1: Время активности объявлений

WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats),
filtered_id AS (
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND (ceiling_height BETWEEN (SELECT ceiling_height_limit_l FROM limits) AND (SELECT ceiling_height_limit_h FROM limits) OR ceiling_height IS NULL)),
category_id AS (
    SELECT a.id AS ad_id, a.last_price, f.total_area, (a.last_price / f.total_area) AS price_per_squaremetre, a.first_day_exposition,
    a.days_exposition, f.city_id, f.rooms, f.ceiling_height,
        CASE WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург' ELSE 'ЛенОбл' END AS category_location,
        CASE
            WHEN a.days_exposition BETWEEN 1 AND 30 THEN 'Месяц'
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN 'Квартал'
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN 'Полгода'
            WHEN a.days_exposition >= 181 THEN 'Больше полугода'
            ELSE 'Активно'
        END AS duration
    FROM real_estate.advertisement AS a
    INNER JOIN real_estate.flats AS f USING(id)
    INNER JOIN real_estate.city AS c USING(city_id)
    INNER JOIN real_estate.TYPE AS t USING(type_id)
    WHERE t.TYPE = 'город' AND f.total_area > 0)
SELECT category_location, duration, rooms, COUNT(ad_id) AS total_id,
    CAST(COUNT(ad_id) AS FLOAT) * 100 / SUM(COUNT(ad_id)) OVER (PARTITION BY category_location) AS persents_forregions,
    AVG(price_per_squaremetre) AS avg_price_per_squaremetre,
    AVG(total_area) AS avg_total_area,
    AVG(ceiling_height) AS avg_ceiling_height,
    AVG(CASE WHEN rooms = 0 THEN 1 ELSE 0 END) AS percentage_ofrooms
FROM category_id
WHERE ad_id IN (SELECT id FROM filtered_id)
GROUP BY category_location, duration, rooms
ORDER BY category_location, duration, rooms;
-- Задача 2: Сезонность объявлений
WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats),
filtered_data AS (
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND (ceiling_height BETWEEN (SELECT ceiling_height_limit_l FROM limits) AND (SELECT ceiling_height_limit_h FROM limits) OR ceiling_height IS NULL)),
publication_months AS (
    SELECT
        EXTRACT(MONTH FROM a.first_day_exposition) AS month_number,
        COUNT(a.id) AS total_id,
        AVG(a.last_price / f.total_area) AS avg_price_per_squaremetre,
        AVG(f.total_area) AS avg_total_area
    FROM real_estate.advertisement AS a
    INNER JOIN real_estate.flats AS f ON a.id = f.id
    INNER JOIN filtered_data ON a.id = filtered_data.id
    INNER JOIN real_estate.TYPE AS t ON t.type_id = f.type_id
    WHERE  a.first_day_exposition IS NOT NULL 
        AND a.last_price IS NOT NULL 
        AND f.total_area > 0
        AND EXTRACT(MONTH FROM a.first_day_exposition) BETWEEN 1 AND 12
        AND t.type = 'город'
    GROUP BY month_number),
removed_publication_months AS (SELECT EXTRACT(MONTH FROM (a.first_day_exposition + a.days_exposition::INTEGER)) AS month_number, 
        COUNT(a.id) AS total_id
    FROM real_estate.advertisement AS a
    INNER JOIN filtered_data ON a.id = filtered_data.id
    INNER JOIN real_estate.flats AS f ON a.id = f.id
    INNER JOIN real_estate.TYPE AS t ON t.type_id = f.type_id
    WHERE a.days_exposition IS NOT NULL AND a.first_day_exposition IS NOT NULL 
        AND EXTRACT(MONTH FROM (a.first_day_exposition + a.days_exposition::INTEGER)) BETWEEN 1 AND 12
        AND t.type = 'город'
    GROUP BY month_number)
SELECT 'Публикация' AS activity_type, month_number, total_id, avg_price_per_squaremetre, avg_total_area,
    RANK() OVER (ORDER BY total_id DESC) AS rankofmonth
FROM publication_months
UNION ALL
SELECT 'Снятие' AS activity_type, month_number, total_id, NULL AS avg_price_per_squaremetre, NULL AS avg_total_area, RANK() OVER (ORDER BY total_id DESC) AS rankofmonth
FROM removed_publication_months
ORDER BY activity_type, rankofmonth;
-- Задача 3: Анализ рынка недвижимости Ленобласти
WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats),
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)),
region_characteristics AS (
    SELECT a.id, c.city, a.days_exposition, a.last_price, f.total_area, (a.last_price / f.total_area) AS price_per_squaremetre
    FROM real_estate.advertisement AS a
    INNER JOIN real_estate.flats AS f ON a.id = f.id
    INNER JOIN real_estate.city AS c ON f.city_id = c.city_id
    INNER JOIN filtered_id ON a.id = filtered_id.id
    WHERE c.city != 'Санкт-Петербург')
SELECT city, COUNT(id) AS total_id, (CAST(COUNT(days_exposition) AS NUMERIC) / COUNT(id)) * 100 AS removed_publication_months,
    AVG(price_per_squaremetre) AS avg_price_per_squaremetre,
    AVG(total_area) AS avg_total_area,
    AVG(days_exposition) AS avg_days_exposition
FROM region_characteristics
GROUP BY city
HAVING COUNT(id) > 100 ---  Использую COUNT(id), так как ТОП-15 населенных пунктов хватит для отслеживания нужных характеристик.
ORDER BY total_id DESC
LIMIT 15;
