use Olist
go

select COUNT(*) as totalrows,
COUNT(distinct CONCAT(product_id,'-',order_item_id)) as uniquesrows /*don't achivie unquneness*/
from order_items

select COUNT(*) as totalrows,
COUNT(distinct CONCAT(order_id,'-',order_item_id)) as uniquesrows /*grain*/
from order_items

select COUNT(*) as totalrows,
COUNT(distinct CONCAT(order_id,'-',payment_sequential)) as uniquesrows /*grain*/
from order_payments

select COUNT(*) as totalrows,
COUNT(distinct CONCAT(order_id,'-',review_id)) as uniquesrows, /*grain*/
COUNT(distinct order_id) as uniqueorderid, 
COUNT(distinct review_id) as uniquereviewid 
from order_reviews

select COUNT(*) as totalrows,
COUNT(distinct customer_id) as uniquecustid, /*grain*/
COUNT(distinct customer_unique_id) as uniquecustunqid
from customers

select distinct customer_unique_id, COUNT(distinct customer_city) as numofappears
from customers
group by customer_unique_id
having COUNT(distinct customer_city) > 1
order by customer_unique_id


select * from customers

/*1 fact tables
5 dim tables */
--date dim--
select MIN(d) AS first_date, MAX(d) AS last_date from (
  select TRY_CAST(order_purchase_timestamp AS DATETIME)      AS d from orders
  UNION ALL SELECT TRY_CAST(order_approved_at AS DATETIME)             from orders
  UNION ALL SELECT TRY_CAST(order_delivered_carrier_date AS DATETIME)  from orders
  UNION ALL SELECT TRY_CAST(order_delivered_customer_date AS DATETIME) from orders
  UNION ALL SELECT TRY_CAST(order_estimated_delivery_date AS DATETIME) from orders
  UNION ALL SELECT TRY_CAST(shipping_limit_date AS DATETIME)           from order_items
  UNION ALL SELECT TRY_CAST(review_creation_date AS DATETIME)          from order_reviews
  UNION ALL SELECT TRY_CAST(review_answer_timestamp AS DATETIME)       from order_reviews
) as t

create table dim_date (
  date_key      INT          NOT NULL PRIMARY KEY,  
  full_date     DATE         NOT NULL,
  [year]        INT          NULL,
  quarter       INT          NULL,
  month_num     INT          NULL,
  month_name    VARCHAR(10)  NULL,
  year_month    CHAR(7)      NULL,                   
  day_of_month  INT          NULL,
  weekday_num   INT          NULL,                   
  weekday_name  VARCHAR(10)  NULL,
  is_weekend    BIT          NULL
)

DECLARE @start DATE = '2016-09-04';
DECLARE @end   DATE = '2020-04-09';

WITH dates AS (
  select @start AS d
  UNION ALL
  select DATEADD(DAY, 1, d) from dates where d < @end
)
insert into dim_date
  (date_key, full_date, [year], quarter, month_num, month_name, year_month,
   day_of_month, weekday_num, weekday_name, is_weekend)
select
  YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d),
  d,
  YEAR(d),
  DATEPART(QUARTER, d),
  MONTH(d),
  CHOOSE(MONTH(d), 'January','February','March','April','May','June',
                   'July','August','September','October','November','December'),
  CONCAT(YEAR(d), '-', RIGHT('0' + CAST(MONTH(d) AS VARCHAR(2)), 2)),
  DAY(d),
  (DATEDIFF(DAY, '19000101', d) % 7) + 1,
  CHOOSE((DATEDIFF(DAY, '19000101', d) % 7) + 1,
         'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'),
  CASE WHEN (DATEDIFF(DAY, '19000101', d) % 7) + 1 IN (6, 7) THEN 1 ELSE 0 END
from dates
OPTION (MAXRECURSION 0)

insert into dim_date
  (date_key, full_date, [year], quarter, month_num, month_name, year_month,
   day_of_month, weekday_num, weekday_name, is_weekend)
values
  (-1, '1900-01-01', NULL, NULL, NULL, 'Unknown', 'Unknown', NULL, NULL, 'Unknown', NULL);

select * from dim_date


select DATEDIFF(DAY, MIN(full_date), MAX(full_date)) + 1 - COUNT(*) AS missing_days
from dim_date where date_key <> -1;
----------------------------------------------------------------------------------------------------------
--Customer Dim--
select * from customers
select * from orders

select *
from customers c
full JOIN orders o
ON c.customer_id = o.customer_id
where customer_unique_id is null 

go
WITH CustomerOrders AS (
    select
        c.customer_unique_id,
        c.customer_city,
        o.order_purchase_timestamp,
        ROW_NUMBER() OVER (
            partition by c.customer_unique_id
            order by o.order_purchase_timestamp DESC
        ) AS rn
    from customers c
    inner join orders o
        on c.customer_id = o.customer_id
)
select
    customer_unique_id,
    customer_city,
    order_purchase_timestamp
from CustomerOrders
where rn = 1;

select distinct customer_unique_id
from customers
go

WITH CustomerOrders AS (
    select
        c.customer_id,
        c.customer_unique_id,
        c.customer_zip_code_prefix,
        c.customer_city,
        c.customer_state,
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp DESC,
                     o.order_id DESC
        ) AS rn

    from customers c
    inner join orders o
        ON c.customer_id = o.customer_id
)
select * from CustomerOrders
where rn = 2

create table dim_customer (
    customer_key INT IDENTITY(1,1) PRIMARY KEY,
    customer_unique_id VARCHAR(50) NOT NULL UNIQUE,
    customer_city VARCHAR(100),
    customer_state CHAR(2)
);

WITH CustomerRank AS (
    SELECT
        c.customer_unique_id,
        c.customer_city,
        c.customer_state,

        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY
                o.order_purchase_timestamp DESC,
                o.order_id DESC
        ) AS rn

    FROM customers c
    INNER JOIN orders o
        ON c.customer_id = o.customer_id
)
INSERT INTO dim_customer (
    customer_unique_id,
    customer_city,
    customer_state
)
select
    customer_unique_id,
    customer_city,
    customer_state
from CustomerRank
where rn = 1

select
    customer_unique_id,
    COUNT(*) AS customer_count
from dim_customer
group by customer_unique_id
having COUNT(*) > 1

select * from dim_customer
----------------------------------------------------------------------------------------------------------
--product dim--
select *
from products p
full join product_category_name_translation t
on p.product_category_name = t.column1 
where product_category_name is null or column2 is null

CREATE TABLE dim_product (
    product_key INT IDENTITY(1,1) PRIMARY KEY,
    product_id VARCHAR(50) NOT NULL UNIQUE,

    product_category_original VARCHAR(100),
    product_category_name VARCHAR(100),

    product_name_length INT,
    product_description_length INT,
    product_photos_qty INT,

    product_weight_g DECIMAL(10,2),
    product_length_cm DECIMAL(10,2),
    product_height_cm DECIMAL(10,2),
    product_width_cm DECIMAL(10,2)
)

INSERT INTO dim_product (
    product_id,
    product_category_original,
    product_category_name,
    product_name_length,
    product_description_length,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
)
select
    p.product_id,
    p.product_category_name,

    COALESCE(
        t.column2,
        p.product_category_name
    ) AS product_category_name,

    p.product_name_lenght,
    p.product_description_lenght,
    p.product_photos_qty,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm

FROM products p
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.column1

select * from dim_product where product_category_name is null

update dim_product
set product_category_name = 'unknown'
where product_category_name is null

select * from dim_product
----------------------------------------------------------------------------------------------------------
--dim seller--
select * from sellers

CREATE TABLE dim_seller (
    seller_key INT IDENTITY(1,1) PRIMARY KEY,
    seller_id VARCHAR(50) NOT NULL UNIQUE,
    seller_city VARCHAR(100),
    seller_state CHAR(2)
)

INSERT INTO dim_seller (
    seller_id,
    seller_city,
    seller_state
)
SELECT
    seller_id,
    seller_city,
    seller_state
FROM sellers

select * from dim_seller
----------------------------------------------------------------------------------------------------------
--dim status--
select distinct order_status
from orders
order by order_status

CREATE TABLE dim_order_status (
    order_status_key INT IDENTITY(1,1) PRIMARY KEY,
    order_status VARCHAR(30) NOT NULL UNIQUE
)

INSERT INTO dim_order_status (order_status)
SELECT DISTINCT order_status
FROM orders

select * from dim_order_status
----------------------------------------------------------------------------------------------------------
--order items fact table--
select COUNT(*) AS source_count
from order_items;

select product_id, COUNT(*)
from dim_product
group by product_id
having COUNT(*) > 1;

select COALESCE(
        CONVERT(INT, CONVERT(CHAR(8), CAST(order_purchase_timestamp AS DATE), 112)), -1
    ) AS date_key
    from orders


CREATE TABLE fact_order_items (
    order_item_key INT IDENTITY(1,1) PRIMARY KEY,

    order_id VARCHAR(50) NOT NULL,
    order_item_id INT NOT NULL,

    customer_key INT,
    product_key INT,
    seller_key INT,
    order_status_key INT,

    purchase_date_key INT,
    approved_date_key INT,
    carrier_date_key INT,
    delivered_date_key INT,
    estimated_delivery_date_key INT,
    shipping_limit_date_key INT,

    price DECIMAL(10,2),
    freight_value DECIMAL(10,2),

    CONSTRAINT UQ_order_item
        UNIQUE (order_id, order_item_id),

    CONSTRAINT FK_customer
        FOREIGN KEY (customer_key)
        REFERENCES dim_customer(customer_key),

    CONSTRAINT FK_product
        FOREIGN KEY (product_key)
        REFERENCES dim_product(product_key),

    CONSTRAINT FK_seller
        FOREIGN KEY (seller_key)
        REFERENCES dim_seller(seller_key),

    CONSTRAINT FK_status
        FOREIGN KEY (order_status_key)
        REFERENCES dim_order_status(order_status_key),

    CONSTRAINT FK_purchase_date
        FOREIGN KEY (purchase_date_key)
        REFERENCES dim_date(date_key),

    CONSTRAINT FK_approved_date
        FOREIGN KEY (approved_date_key)
        REFERENCES dim_date(date_key),

    CONSTRAINT FK_carrier_date
        FOREIGN KEY (carrier_date_key)
        REFERENCES dim_date(date_key),

    CONSTRAINT FK_delivered_date
        FOREIGN KEY (delivered_date_key)
        REFERENCES dim_date(date_key),

    CONSTRAINT FK_estimated_date
        FOREIGN KEY (estimated_delivery_date_key)
        REFERENCES dim_date(date_key),

    CONSTRAINT FK_shipping_date
        FOREIGN KEY (shipping_limit_date_key)
        REFERENCES dim_date(date_key)
)

INSERT INTO fact_order_items (
    order_id,
    order_item_id,
    customer_key,
    product_key,
    seller_key,
    order_status_key,
    purchase_date_key,
    approved_date_key,
    carrier_date_key,
    delivered_date_key,
    estimated_delivery_date_key,
    shipping_limit_date_key,
    price,
    freight_value
)
select
    oi.order_id,
    oi.order_item_id,

    dc.customer_key,
    dp.product_key,
    ds.seller_key,
    dos.order_status_key,

    COALESCE(
        CONVERT(INT, CONVERT(CHAR(8), CAST(o.order_purchase_timestamp AS DATE), 112)),
        -1
    ),

    COALESCE(
        CONVERT(INT, CONVERT(CHAR(8), CAST(o.order_approved_at AS DATE), 112)),
        -1
    ),

    COALESCE(
        CONVERT(INT, CONVERT(CHAR(8), CAST(o.order_delivered_carrier_date AS DATE), 112)),
        -1
    ),

    COALESCE(
        CONVERT(INT, CONVERT(CHAR(8), CAST(o.order_delivered_customer_date AS DATE), 112)),
        -1
    ),

    COALESCE(
        CONVERT(INT, CONVERT(CHAR(8), CAST(o.order_estimated_delivery_date AS DATE), 112)),
        -1
    ),

    COALESCE(
        CONVERT(INT, CONVERT(CHAR(8), CAST(oi.shipping_limit_date AS DATE), 112)),
        -1
    ),

    oi.price,
    oi.freight_value

from order_items oi

INNER JOIN orders o
    ON oi.order_id = o.order_id

LEFT JOIN customers c
    ON o.customer_id = c.customer_id

LEFT JOIN dim_customer dc
    ON c.customer_unique_id = dc.customer_unique_id

LEFT JOIN dim_product dp
    ON oi.product_id = dp.product_id

LEFT JOIN dim_seller ds
    ON oi.seller_id = ds.seller_id

LEFT JOIN dim_order_status dos
    ON o.order_status = dos.order_status;

select
    (SELECT COUNT(*) FROM order_items) AS source_rows,
    (SELECT COUNT(*) FROM fact_order_items) AS fact_rows

select sum(price) from order_items
select sum(price) from fact_order_items

select * from fact_order_items
 
select COUNT(*) AS total_rows,
       COUNT(DISTINCT CONCAT(order_id, '-', order_item_id)) AS unique_rows
FROM fact_order_items

select SUM(CASE WHEN delivered_date_key = -1 THEN 1 ELSE 0 END) AS undelivered_rows
FROM fact_order_items

select s.order_status, 
COUNT(DISTINCT order_id) AS item_rows
from fact_order_items f
inner join dim_order_status s ON f.order_status_key = s.order_status_key
where f.delivered_date_key = -1
group by s.order_status

select order_status, 
COUNT(DISTINCT order_id) AS orders
from fact_order_items f
inner join  dim_order_status s
on f.order_status_key = s.order_status_key
group by  order_status
order by orders DESC;
--------------------------------------------------------------------------------------------------------
