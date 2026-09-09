package com.offlinemesh.backend.repository;

import com.offlinemesh.backend.entity.Friendship;
import com.offlinemesh.backend.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public interface FriendshipRepository extends JpaRepository<Friendship, UUID> {

    @Query("SELECT f FROM Friendship f WHERE (f.user1 = :userA AND f.user2 = :userB) OR (f.user1 = :userB AND f.user2 = :userA)")
    Optional<Friendship> findFriendshipBetween(@Param("userA") User userA, @Param("userB") User userB);
    
    @Query("SELECT CASE WHEN COUNT(f) > 0 THEN true ELSE false END FROM Friendship f WHERE (f.user1 = :userA AND f.user2 = :userB) OR (f.user1 = :userB AND f.user2 = :userA)")
    boolean existsFriendshipBetween(@Param("userA") User userA, @Param("userB") User userB);

    @Query("SELECT f FROM Friendship f WHERE f.user1 = :user OR f.user2 = :user")
    java.util.List<Friendship> findFriendshipsByUser(@Param("user") User user);
}
