package com.offlinemesh.backend.repository;

import com.offlinemesh.backend.entity.Conversation;
import com.offlinemesh.backend.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public interface ConversationRepository extends JpaRepository<Conversation, UUID> {

    @Query("SELECT c FROM Conversation c WHERE (c.user1 = :userA AND c.user2 = :userB) OR (c.user1 = :userB AND c.user2 = :userA)")
    Optional<Conversation> findConversationBetween(@Param("userA") User userA, @Param("userB") User userB);
}
