-- The standard entity table (p6m standards S2). VARCHAR(36) ids keep the DDL identical across
-- PostgreSQL and MySQL; the service generates UUID values.
CREATE TABLE items (
    id VARCHAR(36) PRIMARY KEY,
    display_name VARCHAR(255) NOT NULL
);
