package com.offlinemesh.backend.entity;

import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.UUID;

@Entity
@Table(name = "conversations", uniqueConstraints = {
        @UniqueConstraint(columnNames = {"user1_id", "user2_id"})
})
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Conversation {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @ManyToOne(optional = false)
    @JoinColumn(name = "user1_id", nullable = false)
    private User user1;

    @ManyToOne(optional = false)
    @JoinColumn(name = "user2_id", nullable = false)
    private User user2;

    @PrePersist
    @PreUpdate
    private void normalize() {
        if (user1 == null || user2 == null) {
            return;
        }
        
        if (user1.getId().equals(user2.getId())) {
            throw new IllegalArgumentException("A conversation cannot be with oneself.");
        }

        if (user1.getId().compareTo(user2.getId()) > 0) {
            User temp = user1;
            user1 = user2;
            user2 = temp;
        }
    }
}
