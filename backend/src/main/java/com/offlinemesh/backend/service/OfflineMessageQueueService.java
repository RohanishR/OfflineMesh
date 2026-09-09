package com.offlinemesh.backend.service;

import com.offlinemesh.backend.entity.Message;
import com.offlinemesh.backend.entity.OfflineMessageQueue;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.enums.MessageStatus;
import com.offlinemesh.backend.repository.MessageRepository;
import com.offlinemesh.backend.repository.OfflineMessageQueueRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class OfflineMessageQueueService {

    private final OfflineMessageQueueRepository queueRepository;
    private final MessageRepository messageRepository;

    @Value("${offline.message.max-retries:5}")
    private int maxRetries;

    @Value("${offline.message.retry-delay-ms:5000}")
    private long retryDelayMs;

    @Transactional
    public void enqueueMessage(Message message) {
        if (message.getStatus() == MessageStatus.DELIVERED || message.getStatus() == MessageStatus.READ) {
            return;
        }

        // Change message status to PENDING
        message.setStatus(MessageStatus.PENDING);
        messageRepository.save(message);

        // Add to queue if not exists
        Optional<OfflineMessageQueue> existing = queueRepository.findByMessageAndRecipient(message, message.getRecipient());
        if (existing.isEmpty()) {
            OfflineMessageQueue queueEntry = OfflineMessageQueue.builder()
                    .id(UUID.randomUUID())
                    .message(message)
                    .recipient(message.getRecipient())
                    .status(MessageStatus.PENDING)
                    .attemptCount(0)
                    .build();
            queueRepository.save(queueEntry);
            log.info("Message {} enqueued for recipient {}", message.getId(), message.getRecipient().getOfflineMeshId());
        }
    }

    @Transactional(readOnly = true)
    public List<OfflineMessageQueue> getPendingMessages(User recipient) {
        return queueRepository.findByRecipientAndStatusOrderByCreatedAtAsc(recipient, MessageStatus.PENDING);
    }

    @Transactional
    public void handleAck(User recipient, UUID messageId) {
        Message message = messageRepository.findById(messageId)
                .orElseThrow(() -> new IllegalArgumentException("Message not found"));

        if (!message.getRecipient().getId().equals(recipient.getId())) {
            throw new IllegalArgumentException("You are not the recipient of this message");
        }

        if (message.getStatus() != MessageStatus.DELIVERED) {
            message.setStatus(MessageStatus.DELIVERED);
            messageRepository.save(message);
        }

        Optional<OfflineMessageQueue> queueEntryOpt = queueRepository.findByMessageAndRecipient(message, recipient);
        if (queueEntryOpt.isPresent()) {
            OfflineMessageQueue queueEntry = queueEntryOpt.get();
            if (queueEntry.getStatus() != MessageStatus.DELIVERED) {
                queueEntry.setStatus(MessageStatus.DELIVERED);
                queueEntry.setDeliveredAt(Instant.now());
                queueRepository.save(queueEntry);
                log.info("Message {} ACKed by recipient {}", messageId, recipient.getOfflineMeshId());
            }
        }
    }

    @Transactional
    public void recordDeliveryAttempt(OfflineMessageQueue queueEntry) {
        if (queueEntry.getStatus() == MessageStatus.DELIVERED) {
            return;
        }

        queueEntry.setAttemptCount(queueEntry.getAttemptCount() + 1);
        if (queueEntry.getAttemptCount() >= maxRetries) {
            queueEntry.setStatus(MessageStatus.FAILED);
            // Optionally update the Message entity status to FAILED as well
            Message message = queueEntry.getMessage();
            message.setStatus(MessageStatus.FAILED);
            messageRepository.save(message);
        } else {
            queueEntry.setNextAttemptAt(Instant.now().plusMillis(retryDelayMs));
        }
        queueRepository.save(queueEntry);
    }
}
