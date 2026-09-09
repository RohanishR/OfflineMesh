ALTER TABLE messages ADD COLUMN recipient_id UUID;
ALTER TABLE messages ADD COLUMN message_type VARCHAR(50);
ALTER TABLE messages ADD COLUMN status VARCHAR(50);
ALTER TABLE messages ADD COLUMN transport_type VARCHAR(50);
ALTER TABLE messages ADD COLUMN file_metadata_reference VARCHAR(255);
ALTER TABLE messages ADD COLUMN reply_to_id UUID REFERENCES messages(id);
ALTER TABLE messages ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE messages ALTER COLUMN content DROP NOT NULL;

-- Backfill recipient_id
UPDATE messages m
SET recipient_id = CASE
    WHEN m.sender_id = c.user1_id THEN c.user2_id
    ELSE c.user1_id
END
FROM conversations c
WHERE m.conversation_id = c.id;

-- Backfill other new columns
UPDATE messages SET message_type = 'TEXT', status = 'SENT', transport_type = 'INTERNET', updated_at = CURRENT_TIMESTAMP;

-- Add Constraints
ALTER TABLE messages ALTER COLUMN recipient_id SET NOT NULL;
ALTER TABLE messages ALTER COLUMN message_type SET NOT NULL;
ALTER TABLE messages ALTER COLUMN status SET NOT NULL;
ALTER TABLE messages ALTER COLUMN transport_type SET NOT NULL;
ALTER TABLE messages ALTER COLUMN updated_at SET NOT NULL;

-- Add Foreign Key for recipient
ALTER TABLE messages ADD CONSTRAINT fk_message_recipient FOREIGN KEY (recipient_id) REFERENCES users(id);

-- Create deliveries table
CREATE TABLE deliveries (
    id UUID PRIMARY KEY,
    message_id UUID NOT NULL REFERENCES messages(id),
    sender_id UUID NOT NULL REFERENCES users(id),
    recipient_id UUID NOT NULL REFERENCES users(id),
    selected_transport VARCHAR(50) NOT NULL,
    actual_transport VARCHAR(50),
    status VARCHAR(50) NOT NULL,
    sent_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    read_at TIMESTAMP WITH TIME ZONE,
    retry_count INTEGER NOT NULL DEFAULT 0
);

-- Indexes for domain model performance
CREATE INDEX idx_messages_conversation_id ON messages(conversation_id);
CREATE INDEX idx_messages_sender_id ON messages(sender_id);
CREATE INDEX idx_messages_recipient_id ON messages(recipient_id);
CREATE INDEX idx_messages_created_at ON messages(created_at);
CREATE INDEX idx_deliveries_message_id ON deliveries(message_id);
