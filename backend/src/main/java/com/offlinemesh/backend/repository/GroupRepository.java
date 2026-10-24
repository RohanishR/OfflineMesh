package com.offlinemesh.backend.repository;

import com.offlinemesh.backend.entity.Group;
import com.offlinemesh.backend.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.UUID;

@Repository
public interface GroupRepository extends JpaRepository<Group, UUID> {

    @Query("SELECT g FROM Group g JOIN g.members m WHERE m.user = :user ORDER BY g.updatedAt DESC")
    List<Group> findAllByUser(@Param("user") User user);
}
