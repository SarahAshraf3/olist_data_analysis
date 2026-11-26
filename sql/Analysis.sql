use Olist
go

select 
sum(price) as total_orders_value,
COUNT(distinct f.customer_key) as total_customers,
COUNT(distinct order_id) as total_orders,
SUM(price)/COUNT(distinct order_id) as average_order_value
from fact_order_items f
inner JOIN  dim_order_status s
on f.order_status_key = s.order_status_key
where order_status = 'delivered'

select 
p.product_category_name, 
sum(price) as product_orders_value,
100.0*sum(price)/sum(sum(price)) over() as pct_of_revenue,
COUNT(*) as units_sold
from fact_order_items f
inner join dim_product p
on p.product_key = f.product_key
inner join dim_order_status s
on s.order_status_key = f.order_status_key
where order_status = 'delivered'
group by p.product_category_name
order by product_orders_value desc --health_beauty 

select 
c.customer_state,
sum(price) as product_orders_value,
100.0*sum(price)/sum(sum(price)) over() as pct_of_revenue,
COUNT(*) as units_sold
from fact_order_items f
inner join dim_customer c
on c.customer_key = f.customer_key
inner join dim_order_status s
on s.order_status_key = f.order_status_key
where order_status = 'delivered'
group by c.customer_state
order by product_orders_value desc --SP state generates 37% of revenue so sales depend on one region


select top 10
se.seller_id,
sum(price) as product_orders_value,
100.0*sum(price)/sum(sum(price)) over() as pct_of_revenue,
COUNT(*) as units_sold
from fact_order_items f
inner join dim_seller se
on se.seller_key = f.seller_key
inner join dim_order_status s
on s.order_status_key = f.order_status_key
where order_status = 'delivered'
group by se.seller_id
order by product_orders_value desc 

select 
s.order_status,
100.0*count(distinct order_id)/sum(count(distinct order_id)) over() as pct_of_orders,
COUNT(*) as orders
from fact_order_items f
inner join dim_order_status s
on s.order_status_key = f.order_status_key
group by s.order_status
order by orders desc --97.7% of orders reach the customer 

--------------------------------------------------------------------------------
CREATE VIEW vw_order_items AS
SELECT f.*,
       dp.[full_date] AS purchase_date,
       dd.[full_date] AS delivered_date,
       de.[full_date] AS estimated_date
FROM [fact_order_items] f
LEFT JOIN [dim_date] dp ON f.[purchase_date_key]  = dp.[date_key]
LEFT JOIN [dim_date] dd ON f.[delivered_date_key] = dd.[date_key]
LEFT JOIN [dim_date] de ON f.estimated_delivery_date_key = de.[date_key];


WITH o AS (
    SELECT v.[order_id], v.[customer_key],
           v.purchase_date, v.delivered_date, v.estimated_date,
           SUM(v.[price]) AS price, SUM(v.[freight_value]) AS freight
    FROM vw_order_items v
    JOIN dim_order_status s ON v.order_status_key = s.order_status_key
    WHERE s.order_status = 'delivered' AND v.delivered_date_key <> -1
    GROUP BY v.[order_id], v.[customer_key],
             v.purchase_date, v.delivered_date, v.estimated_date
)
SELECT c.customer_state,
       COUNT(*) AS orders,
       AVG(DATEDIFF(day, o.purchase_date, o.delivered_date) * 1.0) AS avg_delivery_days,
       100.0 * SUM(CASE WHEN o.delivered_date > o.estimated_date THEN 1 ELSE 0 END) / COUNT(*) AS pct_late,
       100.0 * SUM(o.freight) / SUM(o.price) AS freight_pct_of_price
FROM o
JOIN [dim_customer] c ON o.[customer_key] = c.[customer_key]
GROUP BY c.customer_state
ORDER BY pct_late DESC

SELECT sl.[seller_id],
       COUNT(DISTINCT v.[order_id]) AS orders,
       100.0 * COUNT(DISTINCT CASE WHEN v.delivered_date > v.estimated_date
                                   THEN v.[order_id] END)
             / COUNT(DISTINCT v.[order_id]) AS pct_late
FROM vw_order_items v
JOIN [dim_seller] sl ON v.[seller_key] = sl.[seller_key]
JOIN dim_order_status s  ON v.order_status_key = s.order_status_key
WHERE s.order_status = 'delivered' AND v.delivered_date_key <> -1
GROUP BY sl.[seller_id]
HAVING COUNT(DISTINCT v.[order_id]) >= 30
ORDER BY pct_late DESC

SELECT p.product_category_name,
       COUNT(DISTINCT v.[order_id]) AS orders,
       100.0 * COUNT(DISTINCT CASE WHEN v.delivered_date > v.estimated_date
                                   THEN v.[order_id] END)
             / COUNT(DISTINCT v.[order_id]) AS pct_late
FROM vw_order_items v
JOIN [dim_product] p ON v.[product_key] = p.[product_key]
JOIN dim_order_status s  ON v.order_status_key = s.order_status_key
WHERE s.order_status = 'delivered' AND v.delivered_date_key <> -1
GROUP BY p.product_category_name
HAVING COUNT(DISTINCT v.[order_id]) >= 100
ORDER BY pct_late DESC

SELECT YEAR(v.purchase_date)  AS yr,
       MONTH(v.purchase_date) AS mth,
       COUNT(DISTINCT v.[order_id]) AS orders,
       100.0 * COUNT(DISTINCT CASE WHEN v.delivered_date > v.estimated_date
                                   THEN v.[order_id] END)
             / COUNT(DISTINCT v.[order_id]) AS pct_late
FROM vw_order_items v
JOIN dim_order_status s  ON v.order_status_key = s.order_status_key
WHERE s.order_status = 'delivered' AND v.delivered_date_key <> -1
GROUP BY YEAR(v.purchase_date), MONTH(v.purchase_date)
ORDER BY yr, mth

WITH c AS (
    SELECT cu.[customer_unique_id], COUNT(DISTINCT f.[order_id]) AS orders
    FROM [fact_order_items] f
    JOIN [dim_customer] cu ON f.[customer_key] = cu.[customer_key]
    JOIN dim_order_status s  ON f.order_status_key   = s.order_status_key
    WHERE s.order_status = 'delivered' 
    GROUP BY cu.[customer_unique_id]
)
SELECT COUNT(*) AS customers,
       SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END) AS repeat_customers,
       100.0 * SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END) / COUNT(*) AS repeat_pct
FROM c

SELECT c.customer_state,
  MIN(DATEDIFF(day, v.purchase_date, v.delivered_date)) AS min_days,
  MAX(DATEDIFF(day, v.purchase_date, v.delivered_date)) AS max_days,
  SUM(CASE WHEN v.delivered_date < v.purchase_date THEN 1 ELSE 0 END) AS negative_days
FROM vw_order_items v
JOIN [dim_customer] c ON v.[customer_key] = c.[customer_key]
WHERE c.customer_state IN ('SP','RS','MG') AND v.delivered_date IS NOT NULL
GROUP BY c.customer_state;


select * from vw_order_items where estimated_delivery_date_key = -1