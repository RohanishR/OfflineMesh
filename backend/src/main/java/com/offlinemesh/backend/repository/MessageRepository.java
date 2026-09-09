package com.offlinemesh.backend.repository;

import com.offlinemesh.backend.entity.Conversation;
import com.offlinemesh.backend.entity.Message;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import com.offlinemesh.backend.entity.User;
import java.time.Instant;

@Repository
public interface MessageRepository extends JpaRepository<Message, UUID> {
    List<Message> findByConversationOrderByCreatedAtAsc(Conversation conversation);
    
    // For initial sync (no cursor), get latest, then we reverse in service
    List<Message> findByRecipientOrderByCreatedAtDesc(User recipient, Pageable pageable);
    
    // For cursor sync
    List<Message> findByRecipientAndCreatedAtGreaterThanOrderByCreatedAtAsc(User recipient, Instant cursor, Pageable pageable);
}
