use clique_bait;

------------------------------------- CLIQUE_BAIT -------------------------------------------

-- Checking and Modifying Datatype of columns in all the tables 

-- ALTER TABLE event_identifier MODIFY event_type integer;

-- ALTER TABLE events MODIFY page_id integer;

-- ALTER TABLE events MODIFY event_type integer;

-- ALTER TABLE events MODIFY sequence_number integer;

-- ALTER TABLE page_hierarchy MODIFY page_id integer;

-- ALTER TABLE page_hierarchy MODIFY product_id integer;

-- ALTER TABLE users MODIFY user_id integer;

------------------------------------- BASIC ANALYSIS -------------------------------------------

-- Checking the number of rows in all tables 

SELECT table_name, table_rows
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'clique_bait';

---- Creating Views for further analysis 

CREATE VIEW events_view 
AS
SELECT e.visit_id,u.user_id,e.cookie_id,ph.page_name,ph.product_category,ph.product_id,ei.event_name,e.sequence_number,e.event_time
FROM events e 
JOIN event_identifier ei on e.event_type=ei.event_type
JOIN users u on u.cookie_id=e.cookie_id
JOIN page_hierarchy ph on ph.page_id=e.page_id
ORDER BY e.event_time;

select * from events_view;

CREATE VIEW visits_view 
AS
SELECT visit_id,
sum(case when event_name like '%add%' then 1 else 0 end) as Cart_adds,
sum(case when page_name like '%checkout%' then 1 else 0 end) as checkouts,
sum(case when event_name like '%purchase%' then 1 else 0 end) as purchases 
FROM events_view
GROUP BY 1;

select * from visits_view;

----------------------------- DIGITAL ANALYSIS ----------------------------------------------

---- 1.How many users are there?---- 

SELECT COUNT(DISTINCT USER_ID) as Unique_user_count FROM USERS;

---- There are 500 unique users.

----------------------------------------------------------------------------------------------

---- 2.How many cookies does each user have on average?----

SELECT DISTINCT CEIL((SELECT count(DISTINCT cookie_id) FROM users)/(SELECT COUNT(DISTINCT user_id) FROM users)) as average_cookie_per_user 
FROM users;

---- Each user has an average of 4 cookies.

----------------------------------------------------------------------------------------------

---- 3.What is the unique number of visits by all users per month?----

SELECT event_month,sum(unique_visit_count) as total_user_visits
FROM
(
SELECT x.user_id,x.event_month,COUNT(DISTINCT x.visit_id) as unique_visit_count
FROM
(
SELECT u.user_id,u.cookie_id,e.visit_id,MONTHNAME(e.event_time) as event_month,MONTH(e.event_time) as month
FROM events e 
JOIN users u ON e.cookie_id=u.cookie_id
) x
GROUP BY 1,2,x.month
ORDER BY x.user_id,x.month
)user_visit
GROUP BY 1;

----------------------------------------------------------------------------------------------

---- 4.What is the number of events for each event type?----

SELECT ei.*,x.No_of_events
FROM
(SELECT DISTINCT event_type,COUNT(*) OVER (PARTITION BY event_type) as No_of_events
FROM events )x
JOIN event_identifier ei ON x.event_type=ei.event_type
ORDER BY ei.event_type;

----------------------------------------------------------------------------------------------

---- 5.What is the percentage of visits which have a purchase event?----

SELECT  CONCAT(ROUND( (SELECT COUNT(DISTINCT e.visit_id) 
FROM events e 
JOIN event_identifier ei On e.event_type=ei.event_type
WHERE ei.event_name like 'Purchase')/(SELECT COUNT(DISTINCT visit_id) FROM events)*100,2),'%') as Visits_with_purchase
FROM events LIMIT 1;

---- Around 49.86% of the site visits ends with a purchase. 

----------------------------------------------------------------------------------------------

---- 6.What is the percentage of visits which view the checkout page but do not have a purchase event?----

SELECT ROUND((SELECT count(distinct visit_id) FROM visits_view WHERE checkouts=1  AND purchases=0)/
(SELECT COUNT(DISTINCT visit_id) FROM visits_view)*100,2) as checkout_but_not_purchased
FROM visits_view LIMIT 1;

---- Around 9% of users visit the checkout page but do not purchase.

----------------------------------------------------------------------------------------------

---- 7.What are the top 3 pages by number of views?----

SELECT p.page_name,count(e.sequence_number) as No_of_views
FROM events e
JOIN event_identifier ei ON e.event_type=ei.event_type
JOIN page_hierarchy p ON p.page_id=e.page_id 
WHERE ei.event_name like 'Page View'
GROUP BY 1
ORDER BY No_of_views DESC
LIMIT 3;

--- The pages with most number of visits are All produts,checkout,homepage

----------------------------------------------------------------------------------------------

---- 8.What is the number of views and cart adds for each product category?----

SELECT x.product_category,sum(x.No_Of_views) as view_count,
sum(x.No_of_cart_ads) as Cart_ads_count
FROM
(
SELECT product_id,product_category,page_name,
sum(case when event_name like '%view%' then 1 else 0 end) as No_of_views,
sum(case when event_name like '%add%' then 1 else 0 end) as No_of_cart_ads
FROM events_view
WHERE product_category is not null
GROUP BY 1,2,3
ORDER BY product_id
)x
GROUP BY 1;

----------------------------------------------------------------------------------------------

---- 9.What are the top 3 products by purchases?----

WITH cte AS (
  SELECT DISTINCT visit_id AS purchase_id
  FROM events 
  WHERE event_type=3
),
cte2 AS (
  SELECT p.page_name,e.visit_id 
  FROM events e
  LEFT JOIN page_hierarchy p ON p.page_id = e.page_id
  WHERE p.product_id IS NOT NULL 
    AND e.event_type = 2
)
SELECT page_name as Product,COUNT(*) AS Quantity_purchased
FROM cte 
LEFT JOIN cte2 ON visit_id = purchase_id 
GROUP BY page_name
ORDER BY COUNT(*) DESC 
LIMIT 3;

----------------------------------------------------------------------------------------------

----------------------------- PRODUCT FUNNEL ANALYSIS ----------------------------------------

----------------------------- ANALYSIS AT PRODUCT LEVEL --------------------------------------

---- How many times was each product viewed?
---- How many times was each product added to cart?
---- How many times was each product added to a cart but not purchased (abandoned)?
---- How many times was each product purchased?

CREATE VIEW products AS 
WITH cte1 as
(
SELECT visit_id,page_name,
sum(case when event_name like '%view%' then 1 else 0 end) as views,
sum(case when event_name like '%add%' then 1 else 0 end) as cart_adds
FROM events_view
WHERE product_id is not null
GROUP BY 1,2
),
cte2 as 
(
SELECT DISTINCT visit_id AS purchase_id
FROM events 
WHERE event_type=3
),
cte3 as
(
SELECT *, 
(case when cte2.purchase_id is not null then 1 else 0 end) as purchase
from cte1 left join cte2
on cte1.visit_id = cte2.purchase_id
)


select page_name, sum(views) as Page_Views, sum(cart_adds) as Cart_Adds, 
sum(case when cart_adds = 1 and purchase = 0 then 1 else 0
 end) as Cart_Add_No_Purchase,
sum(case when cart_adds= 1 and purchase = 1 then 1 else 0
 end) as Cart_Add_with_Purchase
from cte3
group by page_name;

SELECT * FROM products;

----------------------------------------------------------------------------------------------

----------------------------- ANALYSIS AT PRODUCT_CATEGORY LEVEL -----------------------------

CREATE VIEW product_category_view as
WITH cte1 as
(
SELECT visit_id,product_category,
sum(case when event_name like '%view%' then 1 else 0 end) as views,
sum(case when event_name like '%add%' then 1 else 0 end) as cart_adds
FROM events_view
WHERE product_id is not null
GROUP BY 1,2
),
cte2 as 
(
SELECT DISTINCT visit_id AS purchase_id
FROM events 
WHERE event_type=3
),
cte3 as
(
SELECT *, 
(case when cte2.purchase_id is not null then 1 else 0 end) as purchase
from cte1 left join cte2
on cte1.visit_id = cte2.purchase_id
)


select product_category, sum(views) as Page_Views, sum(cart_adds) as Cart_Adds, 
sum(case when cart_adds = 1 and purchase = 0 then 1 else 0
 end) as Cart_Add_No_Purchase,
sum(case when cart_adds= 1 and purchase = 1 then 1 else 0
 end) as Cart_Add_with_Purchase
from cte3
group by product_category;

SELECT * FROM product_category_view;

----------------------------------------------------------------------------------------------

----------------------------- PRODUCT FUNNEL CONVERSION RATE ANALYSIS -------------------------

---- Which product had the most views, cart adds and purchases?

SELECT page_name as Product_with_most_views 
FROM products 
ORDER BY page_views DESC
LIMIT 1;

SELECT page_name as Product_with_most_cart_adds 
FROM products 
ORDER BY cart_adds DESC
LIMIT 1;

SELECT page_name as Product_with_most_purchases 
FROM products 
ORDER BY cart_add_with_purchase DESC
LIMIT 1;

---- Which product was most likely to be abandoned?

SELECT page_name as Product_most_likely_abandoned 
FROM products 
ORDER BY cart_add_no_purchase DESC
LIMIT 1;

---- What is the view to purchase percentage of products ?

SELECT page_name as product,
CONCAT(ROUND((cart_add_with_purchase/page_views)*100,2),'%') as view_to_purchase_percentage
FROM products
ORDER BY view_to_purchase_percentage DESC;

---- What is the average conversion rate from view to cart add ?

SELECT CONCAT(ROUND(avg(cart_adds*100/page_views),2),'%') as view_to_cart_conversion_rate
FROM products;

---- What is the average conversion rate from cart add to purchase ?

SELECT CONCAT(ROUND(avg(cart_add_with_purchase*100/cart_adds),2),'%') as Cart_to_purchase_conversion_rate
FROM products;

----------------------------------------------------------------------------------------------

------------------------------------- CAMPAIGNS ANALYSIS -------------------------------------

with campaign_cart_adds as(
select distinct visit_id, user_id,min(event_time) as visit_start_time,count(page_name) as page_views, sum(case when event_name='Add to Cart' then 1 else 0 end) as cart_adds,
sum(case when event_name='Purchase' then 1 else 0 end) as purchase,
sum(case when event_name='Ad Impression' then 1 else 0 end) as impressions,
sum(case when event_name='Ad Click' then 1 else 0 end) as click,
case
when min(event_time) > '2020-01-01 00:00:00' and min(event_time) < '2020-01-14 00:00:00'
  then 'BOGOF - Fishing For Compliments'
when min(event_time) > '2020-01-15 00:00:00' and min(event_time) < '2020-01-28 00:00:00'
  then '25% Off - Living The Lux Life'
when min(event_time) > '2020-02-01 00:00:00' and min(event_time) < '2020-03-31 00:00:00'
  then 'Half Off - Treat Your Shellf(ish)' 
else NULL
end as Campaign,
group_concat(case when product_id IS NOT NULL AND event_name='Add to Cart'
   then page_name ELSE NULL END, ', ') AS cart_products
from events_view
group by visit_id, user_id
)
select * from campaign_cart_adds;

----------------------------------------------------------------------------------------------

---------------------------------------------THE END -----------------------------------------
