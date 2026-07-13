# Northwind SQL Business Intelligence

> **Six analytical queries that turn raw transactional data into decisions.**
> Built on the classic Northwind wholesale-food database using PostgreSQL.

---

## The Business Context

Northwind Traders is a classic SQL training database modelling 
a wholesale food distributor. This project goes beyond the data — 
each query answers a real operational question and ends with 
a concrete business recommendation.

| Area | Raw data available | Question that needs answering |
|---|---|---|
| **Operations** | Products table, stock levels | Which items are about to run out? |
| **Sales** | Employees, Orders, Order Details | Who is generating the most revenue — and how efficiently? |
| **Pricing** | Products, Categories | Are our premium products actually priced as premiums? |
| **Catalogue** | Products, Categories | What belongs in the "top tier" for marketing? |
| **Procurement** | Units on order, prices | Where is our supply-chain value concentrated? |
| **Finance** | Order dates, revenue | Is daily revenue trending up or down? |

Each query below addresses one of these questions end-to-end.

---

## Queries & Business Outcomes

### 1 · Inventory Reorder Alert

**Problem:** Stock-outs cause lost sales and erode customer trust.  The
procurement team needs a daily list of active products with fewer than 10 units
remaining so they can issue purchase orders before shelves empty.

**SQL approach:** Single-table filter on `products` (`discontinued = 0`,
`units_in_stock < 10`), ordered by urgency (lowest stock first).
`reorder_level` is included so buyers can compare actual stock against the
product's own threshold.

**Outcome / next step:** Any row returned = immediate purchase order.

![Inventory Results](./results/result_1.png)

---

### 2 · Sales-Rep Performance

**Problem:** Annual reviews and bonus calculations require fair, discount-
adjusted revenue figures per employee.  Gross revenue would overstate
performance for reps who approve large discounts.

**SQL approach:** Three-table JOIN (`employees → orders → order_details`).
Net revenue = `unit_price × quantity × (1 − discount)`.  Added
`orders_handled` and `avg_revenue_per_order` to separate volume from
efficiency — a rep closing many small orders looks different from one closing
few large ones.

**Outcome / next step:**
- Large gap between rank 1 and rank 2 → investigate territory or product
  portfolio allocation.
- Low `avg_revenue_per_order` despite high order count → coaching on
  upselling or discount discipline.

![Sales Performance](./results/result_2.png)

---

### 3 · Above-Average Pricing by Category

**Problem:** Category managers need to justify premium prices to buyers or flag
anomalies.  A product priced well above its category peers either has a strong
value proposition or is at risk of being dropped by price-sensitive customers.

**SQL approach:** CTE (`CategoryAverage`) pre-calculates the mean price per
category.  Main query joins back to `products` and `categories`, exposes
`premium_over_avg` as a concrete currency figure rather than a ratio.

**Outcome / next step:**
- High premium + strong sales volume → protect pricing, use in marketing.
- High premium + declining orders → review pricing or add value narrative.

![Pricing Analysis](./results/result_3.png)

---

### 4 · Top-3 Products per Category (Premium Tier)

**Problem:** Marketing wants a "premium tier" catalogue list per category for
seasonal promotions and bundle design.  Ties must be handled fairly.

**SQL approach:** `DENSE_RANK()` inside a CTE partitions by `category_id`,
ranks by price descending.  `DENSE_RANK` (not `RANK`) means two equally-priced
products both appear — no arbitrary exclusion.  Outer query filters `<= 3`.

**Outcome / next step:**
- Categories returning fewer than 3 products signal a thin catalogue — a gap
  that product sourcing can fill.
- The list feeds directly into promotional copy, gift-set curation, or loyalty
  programme rewards.

![Product Rankings](./results/result_4.png)

---

### 5 · Supply-Chain Concentration Risk

**Problem:** The purchasing director needs to know whether a single product
dominates the on-order value within its category.  Concentration = risk: if
that one supplier delays, the entire category is affected.

**SQL approach:** `SUM() OVER(PARTITION BY category_id)` calculates the
category total without collapsing rows, enabling a per-row percentage.
`NULLIF(…, 0)` prevents division-by-zero for categories with no open orders.
Only products with `units_on_order > 0` are included (active exposure only).

**Outcome / next step:**
- Product share > 60 % in its category → flag for dual-sourcing review or
  safety-stock increase.
- Balanced distribution (no single product above ~30 %) → lower risk profile,
  no immediate action needed.

![Market Share](./results/result_5.png)

---

### 6 · Daily Revenue Trend (Running Total + Moving Average)

**Problem:** The CFO wants to distinguish genuine revenue trends from one-off
spikes and identify whether growth momentum is accelerating or decelerating —
before it shows up in monthly summaries.

**SQL approach:**
- **CTE** aggregates net revenue per calendar day.
- **Running total** (`SUM OVER ORDER BY order_date`) answers "how much have we
  earned so far this period?"
- **3-day moving average** (`AVG OVER … ROWS BETWEEN 2 PRECEDING AND CURRENT ROW`)
  smooths day-to-day noise while remaining responsive to real shifts.

**Outcome / next step:**
- Rising moving average over multiple weeks → healthy momentum, no action.
- Moving average flattens while running total still grows → growth rate is
  decelerating; investigate causes before the monthly report.
- Spike in `daily_revenue` not reflected in `moving_avg_3d` → one-off bulk
  order; exclude from forecast revisions.

![Time Series](./results/result_6.png)

---

## Techniques Used

| Technique | Applied in query |
|---|---|
| Filtering & sorting | 1 |
| Multi-table JOIN + GROUP BY | 2 |
| CTE (Common Table Expression) | 3, 6 |
| DENSE_RANK() window function | 4 |
| SUM() OVER(PARTITION BY) | 5 |
| NULLIF (division-by-zero guard) | 5 |
| Running total | 6 |
| Moving average (ROWS BETWEEN frame) | 6 |

---

## How to Run

1. Restore the Northwind database into PostgreSQL (search for "northwind postgresql" to find the setup scripts)..
2. Open `northwind_analysis.sql` in pgAdmin 4 or any PostgreSQL client.
3. Execute each section independently — queries are fully self-contained.

---

## Tech Stack

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?logo=postgresql&logoColor=white)
![SQL](https://img.shields.io/badge/SQL-Advanced-blue)
