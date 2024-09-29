/*
Based on the following query, there are a couple of apps that have multiple prices, 
but on inspection, neither looks like a good candidate for purchase,
so I'm simply going to take the MAX price to calculate the purchase price.
*/
(
	SELECT
		name,
		COUNT(DISTINCT price),
		'Google Play' AS store
	FROM play_store_apps
	GROUP BY name, store
	HAVING COUNT(DISTINCT price) > 1
)
UNION
(
	SELECT
		name,
		COUNT(DISTINCT price),
		'Apple Store' AS store
	FROM app_store_apps
	GROUP BY name, store
	HAVING COUNT(DISTINCT price) > 1
)

/* 
Here is code to calculate the purchase price of each app
*/
WITH apps AS (
		(SELECT 
			name,
		 	CAST(TRIM(REPLACE(price, '$', '')) AS numeric(5,2)) AS cleaned_price
		FROM play_store_apps)
	UNION
		(SELECT 
		 	name,
		 	price AS cleaned_price
		FROM app_store_apps)
)
SELECT
	name,
	MAX(cleaned_price) AS cleaned_price,
	CASE
		WHEN MAX(cleaned_price) < 1 THEN 10000
		ELSE 10000 * MAX(cleaned_price)
	END AS purchase_price
FROM apps
GROUP BY name;

/*
Note: There are 19 apps that show up on the Google Play store multiple times with different ratings. 
I'll resolve this by taking the rating with the most reviews.
*/
WITH apps AS (
		(SELECT 
			name,
			'Google Play' AS store,
			rating
		FROM play_store_apps)
	UNION
		(SELECT name,
				'Apple Store' AS store,
				rating
		FROM app_store_apps)
)
SELECT
	name,
	store,
	COUNT(*)
FROM apps
GROUP BY name, store
HAVING COUNT(*) > 1;

/*
Here is code to find the lifespan of each app.
*/
WITH apps AS (
		(SELECT 
			name,
			'Google Play' AS store,
			rating,
		 	review_count::int,
		 	RANK() OVER(PARTITION BY name ORDER BY review_count::int DESC)
		FROM play_store_apps)
	UNION
		(SELECT 
		 	name,
			'Apple Store' AS store,
			rating,
			review_count::int,
			RANK() OVER(PARTITION BY name ORDER BY review_count::int DESC)
		FROM app_store_apps)
)
SELECT
	name,
	AVG(rating) AS rating,
	ROUND(2 * AVG(rating)) / 2 AS rating_rounded,  --Trick to round to nearest half star
	1 + ROUND(2 * AVG(rating)) AS lifespan
FROM apps
WHERE rank = 1
GROUP BY name;

/*
Finally, this brings everything together into one query
*/

WITH apps AS (
		(SELECT 
			name,
			'Google Play' AS store,
		 	CAST(TRIM(REPLACE(price, '$', '')) AS numeric(5,2)) AS cleaned_price,
			rating,
		 	review_count::int,
		 	RANK() OVER(PARTITION BY name ORDER BY review_count::int DESC)
		FROM play_store_apps)
	UNION
		(SELECT 
		 	name,
			'Apple Store' AS store,
		 	price AS cleaned_price,
			rating,
			review_count::int,
			RANK() OVER(PARTITION BY name ORDER BY review_count::int DESC)
		FROM app_store_apps)
),
lifespan_calculations AS (
	SELECT
		name,
		COUNT(store) AS num_stores,
		AVG(rating) AS rating,
		ROUND(2 * AVG(rating)) / 2 AS rating_rounded,  --Trick to round to nearest half star
		1 + ROUND(2 * AVG(rating)) AS lifespan
	FROM apps
	WHERE rank = 1
	GROUP BY name),
purchase_prices AS (
	SELECT
		name,
		MAX(cleaned_price) AS cleaned_price,
		CASE
			WHEN MAX(cleaned_price) < 1 THEN 10000
			ELSE 10000 * MAX(cleaned_price)
		END AS purchase_price
	FROM apps
	GROUP BY name
),
revenue_cost_calculations AS (
	SELECT 
		name,
		num_stores,
		rating_rounded,
		lifespan,
		num_stores * 5000 * 12 * lifespan AS total_revenue,
		1000 * 12 * lifespan AS total_marketing_cost,
		purchase_price
	FROM lifespan_calculations
	INNER JOIN purchase_prices
	USING(name))
SELECT
	name,
	total_revenue - total_marketing_cost - purchase_price AS expected_profit
FROM revenue_cost_calculations
WHERE total_revenue - total_marketing_cost - purchase_price IS NOT NULL
ORDER BY expected_profit DESC;