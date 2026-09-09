-- V5__add_communication_routing.sql

-- 1. Safely migrate existing 'WIFI' strings to 'WIFI_LAN' in messages and deliveries tables
UPDATE messages SET transport_type = 'WIFI_LAN' WHERE transport_type = 'WIFI';
UPDATE deliveries SET selected_transport = 'WIFI_LAN' WHERE selected_transport = 'WIFI';
UPDATE deliveries SET actual_transport = 'WIFI_LAN' WHERE actual_transport = 'WIFI';

-- 2. Create communication_routes table
CREATE TABLE communication_routes (
    id UUID PRIMARY KEY,
    sender_id UUID NOT NULL REFERENCES users(id),
    recipient_id UUID NOT NULL REFERENCES users(id),
    transport_type VARCHAR(50) NOT NULL,
    status VARCHAR(50) NOT NULL,
    priority INTEGER NOT NULL,
    metadata TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 3. Indexes for routing lookup performance
CREATE INDEX idx_comm_routes_sender_id ON communication_routes(sender_id);
CREATE INDEX idx_comm_routes_recipient_id ON communication_routes(recipient_id);
CREATE INDEX idx_comm_routes_transport_type ON communication_routes(transport_type);
CREATE INDEX idx_comm_routes_status ON communication_routes(status);
