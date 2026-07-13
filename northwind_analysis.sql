/*******************************************************************************
  PROJECT : Northwind Business Intelligence Analysis
  DATABASE: PostgreSQL (Northwind)
  AUTHOR  : [Your Name]

  PURPOSE
  -------
  Six self-contained analytical queries that answer real operational questions
  for a wholesale food distributor.  Each query section follows the pattern:

      BUSINESS PROBLEM  →  SQL APPROACH  →  ACTIONABLE CONCLUSION

  Techniques covered: basic filtering, multi-table JOINs, GROUP BY, CTEs,
  DENSE_RANK(), SUM() OVER(PARTITION BY), running totals, moving averages.
*******************************************************************************/


-- =============================================================================
-- 1. INVENTORY MANAGEMENT — Which active products are at risk of stocking out?
-- =============================================================================
-- BUSINESS PROBLEM
--   The warehouse team needs a daily reorder alert.  Products still being sold
--   (discontinued = 0) with fewer than 10 units on hand can cause lost sales
--   and unhappy customers if not restocked promptly.
--
-- APPROACH
--   Simple filter on the products table; results sorted so the most critical
--   items (lowest stock) appear at the top.
--
-- ACTIONABLE CONCLUSION
--   Any row returned by this query should trigger a purchase order.
--   Integrate into a morning dashboard or scheduled report so the procurement
--   team acts before stock reaches zero.
-- =============================================================================

SELECT
    product_name,
    units_in_stock,
    reorder_level                          -- built-in threshold for comparison
FROM products
WHERE discontinued = 0
  AND units_in_stock < 10
ORDER BY units_in_stock ASC;              -- most urgent first
-- result_1.png


-- =============================================================================
-- 2. SALES PERFORMANCE — Who are the top-performing sales employees?
-- =============================================================================
-- BUSINESS PROBLEM
--   Management wants to identify high performers for bonuses and low performers
--   who may need coaching.  Revenue must account for the discounts each employee
--   actually granted — gross revenue figures would be misleading.
--
-- APPROACH
--   Three-table JOIN (employees → orders → order_details).
--   Net revenue formula: unit_price × quantity × (1 − discount).
--   ROUND to 2 dp for clean currency display.
--
-- ACTIONABLE CONCLUSION
--   The ranked list reveals the revenue gap between employees.  A large gap
--   between rank 1 and rank 2 may warrant investigating territory allocation or
--   product portfolio differences.  Bottom performers should be reviewed against
--   their assigned accounts before any HR decisions.
-- =============================================================================

SELECT
    e.first_name || ' ' || e.last_name                              AS employee,
    ROUND(
        SUM(od.unit_price * od.quantity * (1 - od.discount))::numeric,
    2)                                                              AS net_revenue,
    COUNT(DISTINCT o.order_id)                                      AS orders_handled,
    ROUND(
        SUM(od.unit_price * od.quantity * (1 - od.discount))::numeric
        / NULLIF(COUNT(DISTINCT o.order_id), 0),
    2)                                                              AS avg_revenue_per_order
FROM employees e
JOIN orders       o  ON e.employee_id = o.employee_id
JOIN order_details od ON o.order_id  = od.order_id
GROUP BY employee
ORDER BY net_revenue DESC;
-- result_2.png


-- =============================================================================
-- 3. PRICING STRATEGY — Which products are priced above their category average?
-- =============================================================================
-- BUSINESS PROBLEM
--   The category managers need to know which products sit above the category
--   average price so they can justify premium positioning, review margin
--   expectations, or flag potential pricing anomalies.
--
-- APPROACH
--   A CTE (CategoryAverage) pre-calculates the per-category mean price.
--   The outer query joins that result back to products for a clean,
--   readable filter — avoiding a correlated subquery in the WHERE clause.
--
-- ACTIONABLE CONCLUSION
--   Products appearing here carry a premium over their peers.  If customer
--   complaints or low sales volume correlate with these items, a price
--   adjustment or stronger marketing narrative may be warranted.
--   Conversely, consistently high-selling premium items validate the pricing.
-- =============================================================================

WITH CategoryAverage AS (
    SELECT
        category_id,
        AVG(unit_price)                    AS avg_price
    FROM products
    GROUP BY category_id
)
SELECT
    c.category_name,
    p.product_name,
    p.unit_price,
    ROUND(ca.avg_price::numeric, 2)        AS category_avg_price,
    ROUND((p.unit_price - ca.avg_price)::numeric, 2) AS premium_over_avg
FROM products p
JOIN CategoryAverage ca ON p.category_id = ca.category_id
JOIN categories      c  ON p.category_id = c.category_id
WHERE p.unit_price > ca.avg_price
ORDER BY premium_over_avg DESC, c.category_name;
-- result_3.png


-- =============================================================================
-- 4. PRODUCT RANKING — What are the top 3 most expensive products per category?
-- =============================================================================
-- BUSINESS PROBLEM
--   Marketing needs a "premium tier" list per category for catalogue design and
--   targeted promotions.  Ties must be handled fairly — two products at the
--   same price should both be included, not arbitrarily excluded.
--
-- APPROACH
--   DENSE_RANK() inside a CTE partitions rankings by category and orders by
--   price descending.  The outer WHERE keeps only ranks 1-3.
--   DENSE_RANK (vs RANK) ensures no rank number is skipped after a tie.
--
-- ACTIONABLE CONCLUSION
--   This list forms the basis for premium-product promotions or bundle offers.
--   If a category returns fewer than 3 products overall, that signals a narrow
--   catalogue — an opportunity to source additional SKUs.
-- =============================================================================

WITH RankedProducts AS (
    SELECT
        c.category_name,
        p.product_name,
        p.unit_price,
        DENSE_RANK() OVER (
            PARTITION BY p.category_id
            ORDER BY p.unit_price DESC
        )                                  AS price_rank
    FROM products   p
    JOIN categories c ON p.category_id = c.category_id
)
SELECT *
FROM RankedProducts
WHERE price_rank <= 3
ORDER BY category_name, price_rank;
-- result_4.png


-- =============================================================================
-- 5. MARKET SHARE — What share of each category's on-order value does each
--    product represent?
-- =============================================================================
-- BUSINESS PROBLEM
--   The purchasing director wants to understand how much capital exposure each
--   product creates within its category.  A single product dominating on-order
--   value concentrates supply-chain risk.
--
-- APPROACH
--   SUM() OVER(PARTITION BY category_id) calculates the category total without
--   collapsing rows, allowing a per-row percentage alongside full detail.
--   NULLIF(…, 0) prevents division-by-zero where a category has no open orders.
--   Filter: only products with active orders (units_on_order > 0).
--
-- ACTIONABLE CONCLUSION
--   Products with a very high percentage (e.g. > 60 %) within their category
--   represent a concentration risk.  If that supplier delays, the entire
--   category suffers.  The procurement team should consider dual-sourcing or
--   safety-stock strategies for such items.
-- =============================================================================

SELECT
    c.category_name,
    p.product_name,
    p.units_on_order,
    ROUND((p.unit_price * p.units_on_order)::numeric, 2)
                                            AS product_order_value,
    ROUND(
        SUM(p.unit_price * p.units_on_order)
            OVER (PARTITION BY c.category_id)::numeric,
    2)                                      AS category_total_value,
    ROUND(
        (p.unit_price * p.units_on_order)::numeric
        / NULLIF(
            SUM(p.unit_price * p.units_on_order)
                OVER (PARTITION BY c.category_id),
            0
          )::numeric * 100,
    2) || ' %'                              AS pct_of_category
FROM products   p
JOIN categories c ON p.category_id = c.category_id
WHERE p.units_on_order > 0
ORDER BY pct_of_category DESC, c.category_name;
-- result_5.png


-- =============================================================================
-- 6. TIME-SERIES TRENDS — How is daily revenue trending, and what does the
--    smoothed curve reveal?
-- =============================================================================
-- BUSINESS PROBLEM
--   The CFO wants to spot seasonal peaks, prolonged slumps, and whether revenue
--   is on an upward or downward trajectory.  Raw daily figures are too noisy;
--   a moving average smooths short-term variance to expose the real trend.
--
-- APPROACH
--   CTE (DailyRevenue): aggregates net revenue per order date.
--   Running total  : SUM() OVER (ORDER BY order_date) — cumulative revenue
--                    from day one; useful for "how close to target are we?"
--   3-day moving average: AVG() OVER (… ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
--                    — softens day-to-day noise while remaining responsive
--                    to genuine trend changes.
--
-- ACTIONABLE CONCLUSION
--   A rising moving average over several weeks signals healthy momentum.
--   A moving average that flattens or drops while the running total still grows
--   means the growth rate is decelerating — an early warning to investigate.
--   Spikes that appear in daily_total but not in moving_avg_3d are one-off
--   events (e.g. a large bulk order) and should not drive forecast revisions.
-- =============================================================================

WITH DailyRevenue AS (
    SELECT
        o.order_date,
        ROUND(
            SUM(od.unit_price * od.quantity * (1 - od.discount))::numeric,
        2)                                 AS daily_revenue
    FROM orders        o
    JOIN order_details od ON o.order_id = od.order_id
    GROUP BY o.order_date
)
SELECT
    order_date,
    daily_revenue,
    SUM(daily_revenue)  OVER (ORDER BY order_date)
                                           AS running_total,
    ROUND(
        AVG(daily_revenue) OVER (
            ORDER BY order_date
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        )::numeric,
    2)                                     AS moving_avg_3d
FROM DailyRevenue
ORDER BY order_date;
-- result_6.png
