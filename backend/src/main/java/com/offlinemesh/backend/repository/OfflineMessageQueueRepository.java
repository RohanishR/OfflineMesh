package com.offlinemesh.backend.repository;

import com.offlinemesh.backend.entity.Message;
import com.offlinemesh.backend.entity.OfflineMessageQueue;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.enums.MessageStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface OfflineMessageQueueRepository extends JpaRepository<OfflineMessageQueue, UUID> {
    List<OfflineMessageQueue> findByRecipientAndStatusOrderByCreatedAtAsc(User recipient, MessageStatus status);
    Optional<OfflineMessageQueue> findByMessageAndRecipient(Message message, User recipient);
}
