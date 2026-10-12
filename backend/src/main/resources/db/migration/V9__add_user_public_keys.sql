CREATE TABLE user_public_keys (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    offline_mesh_id VARCHAR(255) NOT NULL UNIQUE,
    public_key TEXT NOT NULL,
    key_id VARCHAR(255) NOT NULL,
    fingerprint VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_user_public_keys_offline_mesh_id ON user_public_keys(offline_mesh_id);

ALTER TABLE file_metadata ADD COLUMN is_encrypted BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE file_metadata ADD COLUMN encrypted_key_envelope TEXT;
