ALTER TABLE users ADD COLUMN offline_mesh_id VARCHAR(255) UNIQUE;
UPDATE users SET offline_mesh_id = 'OM-' || upper(substring(md5(random()::text) from 1 for 8)) WHERE offline_mesh_id IS NULL;
ALTER TABLE users ALTER COLUMN offline_mesh_id SET NOT NULL;

CREATE TABLE friendships (
    id UUID PRIMARY KEY,
    user1_id UUID NOT NULL REFERENCES users(id),
    user2_id UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_friendship UNIQUE (user1_id, user2_id)
);

CREATE TABLE conversations (
    id UUID PRIMARY KEY,
    user1_id UUID NOT NULL REFERENCES users(id),
    user2_id UUID NOT NULL REFERENCES users(id),
    CONSTRAINT uq_conversation UNIQUE (user1_id, user2_id)
);

CREATE TABLE messages (
    id UUID PRIMARY KEY,
    conversation_id UUID NOT NULL REFERENCES conversations(id),
    sender_id UUID NOT NULL REFERENCES users(id),
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);
