-- 02_create_schema.sql
-- Project 01: Ops KPI (SQL Server)
-- Creates a star-schema style model for ticket/operations reporting.

USE OpsKPI;
GO

-- Drop tables if you rerun (safe reset)
IF OBJECT_ID('dbo.fact_ticket', 'U') IS NOT NULL DROP TABLE dbo.fact_ticket;
IF OBJECT_ID('dbo.dim_agent', 'U') IS NOT NULL DROP TABLE dbo.dim_agent;
IF OBJECT_ID('dbo.dim_queue', 'U') IS NOT NULL DROP TABLE dbo.dim_queue;
IF OBJECT_ID('dbo.dim_customer', 'U') IS NOT NULL DROP TABLE dbo.dim_customer;
IF OBJECT_ID('dbo.dim_date', 'U') IS NOT NULL DROP TABLE dbo.dim_date;
GO

-- Date dimension (daily grain)
CREATE TABLE dbo.dim_date (
    date_key        int         NOT NULL PRIMARY KEY,   -- yyyymmdd
    [date]          date        NOT NULL,
    [year]          smallint    NOT NULL,
    [quarter]       tinyint     NOT NULL,
    [month]         tinyint     NOT NULL,
    month_name      varchar(9)  NOT NULL,
    [day]           tinyint     NOT NULL,
    day_of_week     tinyint     NOT NULL,                -- 1=Mon..7=Sun (we'll keep consistent later)
    day_name        varchar(9)  NOT NULL,
    is_weekend      bit         NOT NULL
);

-- Agents (people doing the work)
CREATE TABLE dbo.dim_agent (
    agent_id        int IDENTITY(1,1) NOT NULL PRIMARY KEY,
    agent_name      varchar(100) NOT NULL,
    team_name       varchar(50)  NOT NULL,
    hire_date       date         NOT NULL,
    is_active       bit          NOT NULL
);

-- Queues (work categories / lines of business)
CREATE TABLE dbo.dim_queue (
    queue_id        int IDENTITY(1,1) NOT NULL PRIMARY KEY,
    queue_name      varchar(80)  NOT NULL,
    business_unit   varchar(50)  NOT NULL,
    priority_tier   tinyint      NOT NULL                -- 1 high .. 3 low
);

-- Customers (internal/external requesters)
CREATE TABLE dbo.dim_customer (
    customer_id     int IDENTITY(1,1) NOT NULL PRIMARY KEY,
    customer_name   varchar(120) NOT NULL,
    customer_type   varchar(30)  NOT NULL,               -- Consumer / Employer / Internal / Broker, etc.
    state_code      char(2)      NOT NULL
);

-- Fact table: one row per ticket
CREATE TABLE dbo.fact_ticket (
    ticket_id               bigint IDENTITY(1,1) NOT NULL PRIMARY KEY,
    created_date_key        int     NOT NULL,
    closed_date_key         int     NULL,

    agent_id                int     NULL,                -- who closed it (nullable for open)
    queue_id                int     NOT NULL,
    customer_id             int     NOT NULL,

    status                  varchar(20) NOT NULL,        -- Open / Closed / Cancelled
    severity                tinyint     NOT NULL,         -- 1 critical .. 4 low
    channel                 varchar(20) NOT NULL,         -- Phone / Email / Web / Chat

    sla_minutes_target      int         NOT NULL,
    minutes_to_close        int         NULL,
    met_sla                 bit         NULL,

    reopen_count            tinyint     NOT NULL,
    csat_score              tinyint     NULL,             -- 1-5

    CONSTRAINT FK_fact_ticket_created_date FOREIGN KEY (created_date_key) REFERENCES dbo.dim_date(date_key),
    CONSTRAINT FK_fact_ticket_closed_date  FOREIGN KEY (closed_date_key)  REFERENCES dbo.dim_date(date_key),
    CONSTRAINT FK_fact_ticket_agent        FOREIGN KEY (agent_id)         REFERENCES dbo.dim_agent(agent_id),
    CONSTRAINT FK_fact_ticket_queue        FOREIGN KEY (queue_id)         REFERENCES dbo.dim_queue(queue_id),
    CONSTRAINT FK_fact_ticket_customer     FOREIGN KEY (customer_id)      REFERENCES dbo.dim_customer(customer_id)
);

-- Helpful indexes for reporting
CREATE INDEX IX_fact_ticket_created_date ON dbo.fact_ticket(created_date_key);
CREATE INDEX IX_fact_ticket_closed_date  ON dbo.fact_ticket(closed_date_key);
CREATE INDEX IX_fact_ticket_queue        ON dbo.fact_ticket(queue_id);
CREATE INDEX IX_fact_ticket_agent        ON dbo.fact_ticket(agent_id);
GO
