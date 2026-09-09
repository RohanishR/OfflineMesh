CREATE TABLE offline_message_queue (
    id UUID PRIMARY KEY,
    message_id UUID NOT NULL REFERENCES messages(id),
    recipient_id UUID NOT NULL REFERENCES users(id),
    status VARCHAR(50) NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMP,
    delivered_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_offline_queue_recipient_status ON offline_message_queue(recipient_id, status);
