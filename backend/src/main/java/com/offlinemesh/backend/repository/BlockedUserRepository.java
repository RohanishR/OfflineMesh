package com.offlinemesh.backend.repository;

import com.offlinemesh.backend.entity.BlockedUser;
import com.offlinemesh.backend.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface BlockedUserRepository extends JpaRepository<BlockedUser, UUID> {

    boolean existsByBlockerAndBlocked(User blocker, User blocked);

    List<BlockedUser> findByBlocker(User blocker);

    Optional<BlockedUser> findByBlockerAndBlocked(User blocker, User blocked);

    void deleteByBlockerAndBlocked(User blocker, User blocked);
}
