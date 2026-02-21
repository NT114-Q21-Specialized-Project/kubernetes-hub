CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    password TEXT NOT NULL,
    role VARCHAR(20) DEFAULT 'CUSTOMER',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (name, email, password, role, is_active)
VALUES (
    'Super Admin',
    'admin@ems.com',
    '$2a$10$fV3zI.Mpt5U/8H5F4E4ELe7mX.qO6I5FvL/pL1.A.v6E.qO6I5FvL',
    'ADMIN',
    true
) ON CONFLICT (email) DO NOTHING;
