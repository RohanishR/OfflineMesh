package com.offlinemesh.backend.service;

import com.offlinemesh.backend.dto.MessageResponse;
import com.offlinemesh.backend.dto.MessageSyncResponse;
import com.offlinemesh.backend.entity.Message;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.repository.MessageRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.Collections;
import java.util.List;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class SynchronizationService {

    private final MessageRepository messageRepository;

    @Transactional(readOnly = true)
    public MessageSyncResponse syncMessages(User user, String cursorStr, Integer limit) {
        int maxLimit = 100;
        int actualLimit = (limit != null && limit > 0 && limit <= maxLimit) ? limit : 50;
        
        // We fetch one extra item to accurately determine 'hasMore'
        Pageable pageable = PageRequest.of(0, actualLimit + 1);

        List<Message> messages;
        if (cursorStr == null || cursorStr.isBlank()) {
            // First time sync: fetch the latest 'limit' messages and return in chronological order
            messages = messageRepository.findByRecipientOrderByCreatedAtDesc(user, pageable);
            Collections.reverse(messages);
        } else {
            Instant cursor = Instant.parse(cursorStr);
            messages = messageRepository.findByRecipientAndCreatedAtGreaterThanOrderByCreatedAtAsc(user, cursor, pageable);
        }

        boolean hasMore = messages.size() > actualLimit;
        if (hasMore) {
            // Remove the extra element used for checking hasMore
            if (cursorStr == null || cursorStr.isBlank()) {
                messages.remove(0); // If we reversed, the extra element is at the front (oldest)
            } else {
                messages.remove(messages.size() - 1); // Otherwise it's at the end
            }
        }

        List<MessageResponse> responseList = messages.stream().map(m -> MessageResponse.builder()
                .id(m.getId().toString())
                .senderOfflineMeshId(m.getSender().getOfflineMeshId())
                .content(m.getContent())
                .createdAt(m.getCreatedAt() != null ? m.getCreatedAt().toString() : "")
                .build()
        ).collect(Collectors.toList());

        String nextCursor = null;
        if (!responseList.isEmpty()) {
            nextCursor = responseList.get(responseList.size() - 1).getCreatedAt();
        } else {
            nextCursor = cursorStr;
        }

        return MessageSyncResponse.builder()
                .messages(responseList)
                .nextCursor(nextCursor)
                .hasMore(hasMore)
                .build();
    }
}
