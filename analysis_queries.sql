/* Проект первого модуля: анализ данных для агентства недвижимости
 * Автор: Щербина Артём
 * Дата: 28.08.2025
*/

-- Очистка данных от аномалий через перцентили
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
        AND (ceiling_height BETWEEN (SELECT ceiling_height_limit_l FROM limits) AND (SELECT ceiling_height_limit_h FROM limits) OR ceiling_height IS NULL))
SELECT city, COUNT(id) AS total_id, 
    AVG(last_price / total_area) AS avg_price_per_squaremetre,
    AVG(total_area) AS avg_total_area,
    AVG(days_exposition) AS avg_days_exposition
FROM (
    SELECT a.id, c.city, a.days_exposition, a.last_price, f.total_area
    FROM real_estate.advertisement AS a
    INNER JOIN real_estate.flats AS f ON a.id = f.id
    INNER JOIN real_estate.city AS c ON f.city_id = c.city_id
    WHERE a.id IN (SELECT id FROM filtered_id) AND c.city != 'Санкт-Петербург'
) AS sub
GROUP BY city
HAVING COUNT(id) > 100
ORDER BY total_id DESC
LIMIT 15;