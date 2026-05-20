/********** NIVELL 1 **********/
--  Exercici 2: Ingesta en Capa Bronze (Connexió DDL)

CREATE EXTERNAL TABLE `sprint3_bronze.transactions_raw`
OPTIONS (
  format = 'CSV',
  uris = ['gs://bootcamp-data-analytics-public/ERP/transactions.csv'],
  field_delimiter = ';',
  skip_leading_rows = 1
);


CREATE EXTERNAL TABLE `sprint3_bronze.companies_raw`
(
  company_id STRING,
  company_name STRING,
  company_email STRING,
  country STRING
)
OPTIONS (
  format = 'CSV',
  uris = ['gs://bootcamp-data-analytics-public/ERP/companies.csv'],
  skip_leading_rows = 1
);

CREATE OR REPLACE EXTERNAL TABLE `sprint3_bronze.american_users_raw`
OPTIONS (
  format = 'CSV',
  uris = ['gs://bootcamp-data-analytics-public/CRM/american_users.csv'],
  skip_leading_rows = 1
);

CREATE OR REPLACE EXTERNAL TABLE `sprint3_bronze.european_users_raw`
OPTIONS (
  format = 'CSV',
  uris = ['gs://bootcamp-data-analytics-public/CRM/european_users.csv'],
  skip_leading_rows = 1
);

CREATE OR REPLACE EXTERNAL TABLE `sprint3_bronze.credit_cards_raw`
OPTIONS (
  format = 'CSV',
  uris = ['gs://bootcamp-data-analytics-public/CRM/credit_cards.csv'],
  skip_leading_rows = 1
);


SELECT timestamp FROM `sprint3_bronze.transactions_raw`;


-- Exercici 5: Adaptació de Sintaxi (Reporting)

SELECT
  DATE(timestamp) AS data_dia,
  ROUND(SUM(amount),2) AS ingressos_totals
FROM
  `sprint3_bronze.transactions_raw`
WHERE
  EXTRACT(YEAR FROM timestamp) = 2021
GROUP BY
  1
ORDER BY
  ingressos_totals DESC
LIMIT 5;


-- Exercici 6: Consultes Complexes

SELECT 
  companies_raw.company_name, 
  companies_raw.country,  
  DATE(transactions_raw.timestamp) AS data_dia, 
  ROUND(transactions_raw.amount, 2) AS import_transaccio
FROM `sprint3_bronze.companies_raw` AS companies_raw
JOIN `sprint3_bronze.transactions_raw` AS transactions_raw
  ON companies_raw.company_id = transactions_raw.business_id
WHERE ROUND(transactions_raw.amount, 2) BETWEEN 100 AND 200
  AND (DATE(transactions_raw.timestamp) = '2015-04-29'
    OR DATE(transactions_raw.timestamp) = '2018-07-20'
    OR DATE(transactions_raw.timestamp) = '2024-03-13')
  AND transactions_raw.declined = 0
ORDER BY import_transaccio DESC;



/******** NIVELL 2 ********/

-- Exercici 1: Neteja de Productes (Data Quality)

CREATE OR REPLACE TABLE `sprint3_silver.products_clean` AS
SELECT
  CAST(id AS STRING) AS product_id,
  CAST(product_name AS STRING) AS name,
  
  CAST(REGEXP_REPLACE(warehouse_id, r'^WH-', '') AS INT64) AS warehouse_id, price, weight
 FROM `sprint3_bronze.products_raw`;
 
 -- Exercici 2: Creació de Transaccions Netes (Capa Silver)


  CREATE OR REPLACE TABLE `sprint3_silver.transactions_clean` AS
 SELECT
  CAST(id AS STRING) AS transaction_id,
  IFNULL(SAFE_CAST(amount AS FLOAT64), 0.0) AS amount,
  CAST(timestamp AS TIMESTAMP) AS timestamp,
  SAFE_CAST(lat AS FLOAT64) AS lat,
  SAFE_CAST(longitude AS FLOAT64) AS longitude,card_id, business_id, declined, 
  ARRAY(
    SELECT SAFE_CAST(TRIM(id_individual) AS INT64) 
    FROM UNNEST(SPLIT(product_ids, ',')) AS id_individual
  ) AS product_ids,
  user_id
 FROM `sprint3_bronze.transactions_raw`;



-- Exercici 3: Unificació d'Usuaris (UNION)

CREATE OR REPLACE TABLE `sprint3_silver.users_combined` AS
SELECT 
  CAST(id AS STRING) AS user_id,  
  name, surname, phone, email, 
  SAFE.PARSE_DATE('%b %e, %Y', birth_date) AS birth_date, country, city, postal_code, address,
  'EUA' AS origin                
FROM `sprint3_bronze.american_users_raw`
UNION ALL
SELECT 
  CAST(id AS STRING) AS user_id,  
  name, surname, phone, email, 
  SAFE.PARSE_DATE('%b %e, %Y', birth_date) AS birth_date, country, city, postal_code, address, 
  'Europe' AS origin              
FROM `sprint3_bronze.european_users_raw`;

-- Exercici 4: Materialització de Companyies i Targetes de Crèdit

CREATE OR REPLACE TABLE `sprint3_silver.companies_clean` AS
SELECT
  CAST(company_id AS STRING) AS company_id, 
  CAST(company_name AS STRING) AS name, 
  CAST(company_phone AS STRING) AS phone,
  CAST(company_email AS STRING) AS email, country, website
FROM `sprint3_bronze.companies_raw`;


CREATE OR REPLACE TABLE `sprint3_silver.credit_cards_clean` AS
SELECT
  CAST(id AS STRING) AS card_id, user_id, iban, pan, pin, cvv track1, track2, expiring_date
FROM `sprint3_bronze.credit_cards_raw`;


/******** NIVELL 3 ********/

-- Exercici 1: La Vista de Màrqueting (Lògica de Negoci)

CREATE OR REPLACE VIEW `sprint3_gold.v_marketing_kpis` AS
SELECT c.name AS company_name, c.phone, c.country, ROUND(AVG(t.amount), 2) AS average_purchase,
  CASE 
    WHEN AVG(t.amount) > 260 THEN 'Premium'
    ELSE 'Standard'
  END AS client_tier
FROM 
  `sprint3_silver.companies_clean` AS c
JOIN 
  `sprint3_silver.transactions_clean` AS t
  ON c.company_id = t.business_id
GROUP BY c.name, c.phone, c.country;

-- Exercici 2: Rànquing de Productes (La Potència dels Arrays)

CREATE OR REPLACE TABLE `sprint3_gold.product_sales_ranking` AS
WITH product_counts AS (
  SELECT 
    individual_product_id,
    COUNT(*) AS total_sold
  FROM 
    `sprint3_silver.transactions_clean`,
    UNNEST(product_ids) AS individual_product_id 
  GROUP BY 
    individual_product_id
)
SELECT p.product_id, p.name, p.price, p.colour, 
  IFNULL(c.total_sold, 0) AS total_sold
FROM 
  `sprint3_silver.products_clean` AS p
LEFT JOIN 
  product_counts AS c
  ON CAST(p.product_id AS INT64) = c.individual_product_id
ORDER BY 
  total_sold DESC; 
  
SELECT * FROM product_sales_ranking;