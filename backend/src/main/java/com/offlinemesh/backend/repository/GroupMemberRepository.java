package com.offlinemesh.backend.repository;

import com.offlinemesh.backend.entity.Group;
import com.offlinemesh.backend.entity.GroupMember;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.enums.GroupRole;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface GroupMemberRepository extends JpaRepository<GroupMember, UUID> {

    Optional<GroupMember> findByGroupAndUser(Group group, User user);

    List<GroupMember> findByGroup(Group group);

    boolean existsByGroupAndUser(Group group, User user);

    boolean existsByGroupAndUserAndRole(Group group, User user, GroupRole role);

    void deleteByGroupAndUser(Group group, User user);
}
