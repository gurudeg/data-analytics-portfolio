/* 03_generate_data.sql
   Project 01: Ops KPI (SQL Server)
   Populates dimensions + generates a large fact table (default 500,000 rows)

   Run after:
   - 01_create_database.sql
   - 02_create_schema.sql
*/

USE OpsKPI;
GO
SET NOCOUNT ON;

--------------------------------------------------------------------------------
-- 0) PARAMETERS (you can scale up later)
--------------------------------------------------------------------------------
DECLARE @TicketRows      int  = 500000;      -- Increase later (1,000,000+ is fine)
DECLARE @AgentRows       int  = 250;
DECLARE @QueueRows       int  = 24;
DECLARE @CustomerRows    int  = 10000;

DECLARE @StartDate date = '2023-01-01';
DECLARE @EndDate   date = '2025-12-31';

--------------------------------------------------------------------------------
-- 1) CLEAR EXISTING DATA (safe re-run)
--------------------------------------------------------------------------------
-- Fact first (FK dependencies)
IF EXISTS (SELECT 1 FROM sys.tables WHERE name='fact_ticket' AND schema_id=SCHEMA_ID('dbo'))
BEGIN
    DELETE FROM dbo.fact_ticket;
    DBCC CHECKIDENT ('dbo.fact_ticket', RESEED, 0) WITH NO_INFOMSGS;
END

-- Dimensions
DELETE FROM dbo.dim_agent;
DBCC CHECKIDENT ('dbo.dim_agent', RESEED, 0) WITH NO_INFOMSGS;

DELETE FROM dbo.dim_queue;
DBCC CHECKIDENT ('dbo.dim_queue', RESEED, 0) WITH NO_INFOMSGS;

DELETE FROM dbo.dim_customer;
DBCC CHECKIDENT ('dbo.dim_customer', RESEED, 0) WITH NO_INFOMSGS;

DELETE FROM dbo.dim_date;

--------------------------------------------------------------------------------
-- 2) BUILD dim_date (daily grain)
--------------------------------------------------------------------------------
;WITH n AS (
    SELECT TOP (DATEDIFF(DAY, @StartDate, @EndDate) + 1)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
),
d AS (
    SELECT DATEADD(DAY, n.n, @StartDate) AS [date]
    FROM n
)
INSERT dbo.dim_date (date_key, [date], [year], [quarter], [month], month_name, [day],
                     day_of_week, day_name, is_weekend)
SELECT
    CONVERT(int, CONVERT(char(8), d.[date], 112))                         AS date_key,
    d.[date],
    DATEPART(YEAR, d.[date])                                              AS [year],
    DATEPART(QUARTER, d.[date])                                           AS [quarter],
    DATEPART(MONTH, d.[date])                                             AS [month],
    DATENAME(MONTH, d.[date])                                             AS month_name,
    DATEPART(DAY, d.[date])                                               AS [day],
    -- Make Monday=1 ... Sunday=7
    CASE WHEN DATEPART(WEEKDAY, d.[date]) = 1 THEN 7 ELSE DATEPART(WEEKDAY, d.[date]) - 1 END AS day_of_week,
    DATENAME(WEEKDAY, d.[date])                                           AS day_name,
    CASE WHEN DATENAME(WEEKDAY, d.[date]) IN ('Saturday','Sunday') THEN 1 ELSE 0 END         AS is_weekend
FROM d
ORDER BY d.[date];

--------------------------------------------------------------------------------
-- 3) BUILD dim_agent
--------------------------------------------------------------------------------
;WITH n AS (
    SELECT TOP (@AgentRows) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects
)
INSERT dbo.dim_agent (agent_name, team_name, hire_date, is_active)
SELECT
    CONCAT('Agent ', RIGHT(CONCAT('0000', n.n), 4)) AS agent_name,
    CASE (n.n % 5)
        WHEN 0 THEN 'Intake'
        WHEN 1 THEN 'Claims Ops'
        WHEN 2 THEN 'Member Svcs'
        WHEN 3 THEN 'Billing'
        ELSE 'Escalations'
    END AS team_name,
    DATEADD(DAY, -1 * (365 * (1 + (n.n % 6))) - (n.n % 120), CAST(GETDATE() AS date)) AS hire_date,
    CASE WHEN (n.n % 20) = 0 THEN 0 ELSE 1 END AS is_active
FROM n
ORDER BY n.n;

--------------------------------------------------------------------------------
-- 4) BUILD dim_queue
--------------------------------------------------------------------------------
;WITH n AS (
    SELECT TOP (@QueueRows) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects
)
INSERT dbo.dim_queue (queue_name, business_unit, priority_tier)
SELECT
    CONCAT('Queue ', RIGHT(CONCAT('00', n.n), 2)) AS queue_name,
    CASE (n.n % 4)
        WHEN 0 THEN 'Claims'
        WHEN 1 THEN 'Eligibility'
        WHEN 2 THEN 'Billing'
        ELSE 'General'
    END AS business_unit,
    CASE (n.n % 3)
        WHEN 0 THEN 1
        WHEN 1 THEN 2
        ELSE 3
    END AS priority_tier
FROM n
ORDER BY n.n;

--------------------------------------------------------------------------------
-- 5) BUILD dim_customer
--------------------------------------------------------------------------------
;WITH n AS (
    SELECT TOP (@CustomerRows) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
)
INSERT dbo.dim_customer (customer_name, customer_type, state_code)
SELECT
    CONCAT('Customer ', RIGHT(CONCAT('000000', n.n), 6)) AS customer_name,
    CASE (n.n % 4)
        WHEN 0 THEN 'Consumer'
        WHEN 1 THEN 'Employer'
        WHEN 2 THEN 'Broker'
        ELSE 'Internal'
    END AS customer_type,
    CASE (n.n % 10)
        WHEN 0 THEN 'CT'
        WHEN 1 THEN 'MA'
        WHEN 2 THEN 'RI'
        WHEN 3 THEN 'NY'
        WHEN 4 THEN 'NJ'
        WHEN 5 THEN 'PA'
        WHEN 6 THEN 'NH'
        WHEN 7 THEN 'VT'
        WHEN 8 THEN 'ME'
        ELSE 'FL'
    END AS state_code
FROM n
ORDER BY n.n;

--------------------------------------------------------------------------------
-- 6) GENERATE fact_ticket (large)
--------------------------------------------------------------------------------
DECLARE @DateCount int = DATEDIFF(DAY, @StartDate, @EndDate) + 1;

;WITH t AS (
    SELECT TOP (@TicketRows)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
),
r AS (
    SELECT
        t.rn,

        -- Deterministic pseudo-random integers per row
        ABS(CHECKSUM(CONCAT('A', t.rn))) AS r1,
        ABS(CHECKSUM(CONCAT('B', t.rn))) AS r2,
        ABS(CHECKSUM(CONCAT('C', t.rn))) AS r3,
        ABS(CHECKSUM(CONCAT('D', t.rn))) AS r4,
        ABS(CHECKSUM(CONCAT('E', t.rn))) AS r5
    FROM t
),
base AS (
    SELECT
        r.rn,

        -- Random created date within range
        DATEADD(DAY, (r.r1 % @DateCount), @StartDate) AS created_date,

        -- Severity 1..4 (weighted toward 3/4)
        CASE
            WHEN (r.r2 % 100) < 5  THEN 1
            WHEN (r.r2 % 100) < 20 THEN 2
            WHEN (r.r2 % 100) < 60 THEN 3
            ELSE 4
        END AS severity,

        -- Channel
        CASE (r.r3 % 4)
            WHEN 0 THEN 'Phone'
            WHEN 1 THEN 'Email'
            WHEN 2 THEN 'Web'
            ELSE 'Chat'
        END AS channel,

        -- FK selections
        (r.r4 % @QueueRows) + 1       AS queue_id,
        (r.r5 % @CustomerRows) + 1    AS customer_id,

        -- "Open" rate ~8%
        CASE WHEN (r.r1 % 100) < 8 THEN 1 ELSE 0 END AS is_open
    FROM r
),
calc AS (
    SELECT
        b.*,

        -- SLA target minutes (based on severity)
        CASE b.severity
            WHEN 1 THEN 60
            WHEN 2 THEN 240
            WHEN 3 THEN 720
            ELSE 1440
        END AS sla_minutes_target,

        -- minutes_to_close (only if closed)
        CASE
            WHEN b.is_open = 1 THEN NULL
            ELSE
                CASE b.severity
                    WHEN 1 THEN 30  + (b.customer_id % 180)     -- 30..209
                    WHEN 2 THEN 60  + (b.customer_id % 600)     -- 60..659
                    WHEN 3 THEN 120 + (b.customer_id % 1800)    -- 120..1919
                    ELSE        240 + (b.customer_id % 4320)    -- 240..4559
                END
        END AS minutes_to_close
    FROM base b
),
final AS (
    SELECT
        c.*,

        -- Closed date derived from minutes_to_close (approx)
        CASE
            WHEN c.minutes_to_close IS NULL THEN NULL
            ELSE
                CASE
                    WHEN DATEADD(DAY, (c.minutes_to_close / 1440), c.created_date) > @EndDate
                        THEN @EndDate
                    ELSE DATEADD(DAY, (c.minutes_to_close / 1440), c.created_date)
                END
        END AS closed_date,

        -- Agent only on closed tickets
        CASE
            WHEN c.minutes_to_close IS NULL THEN NULL
            ELSE ((c.customer_id + c.queue_id) % @AgentRows) + 1
        END AS agent_id,

        -- Status
        CASE
            WHEN c.minutes_to_close IS NULL THEN 'Open'
            ELSE 'Closed'
        END AS status,

        -- Met SLA flag (only on closed)
        CASE
            WHEN c.minutes_to_close IS NULL THEN NULL
            WHEN c.minutes_to_close <= c.sla_minutes_target THEN 1
            ELSE 0
        END AS met_sla,

        -- Reopens (0..3 mostly)
        CASE
            WHEN (c.customer_id % 100) < 85 THEN 0
            WHEN (c.customer_id % 100) < 95 THEN 1
            WHEN (c.customer_id % 100) < 99 THEN 2
            ELSE 3
        END AS reopen_count,

        -- CSAT (only some tickets get scored)
        CASE
            WHEN (c.customer_id % 100) < 35 THEN NULL
            ELSE
                CASE
                    WHEN c.severity IN (1,2) AND c.minutes_to_close IS NOT NULL AND c.minutes_to_close > c.sla_minutes_target THEN 2
                    WHEN c.minutes_to_close IS NOT NULL AND c.minutes_to_close <= c.sla_minutes_target THEN 4 + (c.customer_id % 2) -- 4 or 5
                    ELSE 3
                END
        END AS csat_score
    FROM calc c
)
INSERT dbo.fact_ticket
(
    created_date_key,
    closed_date_key,
    agent_id,
    queue_id,
    customer_id,
    status,
    severity,
    channel,
    sla_minutes_target,
    minutes_to_close,
    met_sla,
    reopen_count,
    csat_score
)
SELECT
    CONVERT(int, CONVERT(char(8), f.created_date, 112)) AS created_date_key,
    CASE WHEN f.closed_date IS NULL THEN NULL
         ELSE CONVERT(int, CONVERT(char(8), f.closed_date, 112))
    END AS closed_date_key,
    f.agent_id,
    f.queue_id,
    f.customer_id,
    f.status,
    f.severity,
    f.channel,
    f.sla_minutes_target,
    f.minutes_to_close,
    f.met_sla,
    f.reopen_count,
    f.csat_score
FROM final f;

--------------------------------------------------------------------------------
-- 7) QUICK VALIDATION
--------------------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM dbo.dim_date)     AS dim_date_rows,
    (SELECT COUNT(*) FROM dbo.dim_agent)    AS dim_agent_rows,
    (SELECT COUNT(*) FROM dbo.dim_queue)    AS dim_queue_rows,
    (SELECT COUNT(*) FROM dbo.dim_customer) AS dim_customer_rows,
    (SELECT COUNT(*) FROM dbo.fact_ticket)  AS fact_ticket_rows;

SELECT TOP (10) *
FROM dbo.fact_ticket
ORDER BY ticket_id DESC;
GO
