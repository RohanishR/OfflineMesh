package com.offlinemesh.backend.repository;

import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.UserPublicKey;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public interface UserPublicKeyRepository extends JpaRepository<UserPublicKey, UUID> {
    Optional<UserPublicKey> findByOfflineMeshId(String offlineMeshId);
    Optional<UserPublicKey> findByUser(User user);
    boolean existsByOfflineMeshId(String offlineMeshId);
}
