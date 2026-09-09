CREATE TABLE file_metadata (
    id UUID PRIMARY KEY,
    sender_id UUID NOT NULL,
    recipient_id UUID NOT NULL,
    original_file_name VARCHAR(255) NOT NULL,
    content_type VARCHAR(255) NOT NULL,
    file_size BIGINT NOT NULL,
    checksum VARCHAR(255),
    storage_key VARCHAR(255),
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT fk_file_metadata_sender FOREIGN KEY (sender_id) REFERENCES users(id),
    CONSTRAINT fk_file_metadata_recipient FOREIGN KEY (recipient_id) REFERENCES users(id)
);

CREATE INDEX idx_file_metadata_sender ON file_metadata(sender_id);
CREATE INDEX idx_file_metadata_recipient ON file_metadata(recipient_id);
