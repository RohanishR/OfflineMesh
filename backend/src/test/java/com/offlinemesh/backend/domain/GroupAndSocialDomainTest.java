package com.offlinemesh.backend.domain;

import com.offlinemesh.backend.dto.GroupDTO;
import com.offlinemesh.backend.dto.GroupMemberDTO;
import com.offlinemesh.backend.dto.UserPresenceUpdate;
import com.offlinemesh.backend.entity.BlockedUser;
import com.offlinemesh.backend.entity.Group;
import com.offlinemesh.backend.entity.GroupMember;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.enums.GroupRole;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.ArrayList;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class GroupAndSocialDomainTest {

    @Test
    void testGroupAndMemberRoles() {
        User creator = User.builder().id(UUID.randomUUID()).username("alice").offlineMeshId("MESH-ALICE").build();
        User member = User.builder().id(UUID.randomUUID()).username("bob").offlineMeshId("MESH-BOB").build();

        Group group = Group.builder()
                .id(UUID.randomUUID())
                .name("OfflineMesh Core")
                .description("Decentralized mesh developers")
                .createdBy(creator)
                .members(new ArrayList<>())
                .build();

        GroupMember adminMember = GroupMember.builder()
                .id(UUID.randomUUID())
                .group(group)
                .user(creator)
                .role(GroupRole.ADMIN)
                .joinedAt(Instant.now())
                .build();

        GroupMember regularMember = GroupMember.builder()
                .id(UUID.randomUUID())
                .group(group)
                .user(member)
                .role(GroupRole.MEMBER)
                .joinedAt(Instant.now())
                .build();

        assertEquals(GroupRole.ADMIN, adminMember.getRole());
        assertEquals(GroupRole.MEMBER, regularMember.getRole());
        assertEquals("OfflineMesh Core", group.getName());
        assertEquals(creator, group.getCreatedBy());
    }

    @Test
    void testBlockedUserEntity() {
        User blocker = User.builder().id(UUID.randomUUID()).username("alice").offlineMeshId("MESH-ALICE").build();
        User blocked = User.builder().id(UUID.randomUUID()).username("spammer").offlineMeshId("MESH-SPAMMER").build();

        BlockedUser record = BlockedUser.builder()
                .id(UUID.randomUUID())
                .blocker(blocker)
                .blocked(blocked)
                .createdAt(Instant.now())
                .build();

        assertNotNull(record.getId());
        assertEquals("alice", record.getBlocker().getUsername());
        assertEquals("spammer", record.getBlocked().getUsername());
    }

    @Test
    void testUserPresenceUpdateDto() {
        UserPresenceUpdate update = UserPresenceUpdate.builder()
                .offlineMeshId("MESH-ALICE")
                .status("ONLINE")
                .isTyping(true)
                .isRecording(false)
                .lastSeen(Instant.now())
                .build();

        assertEquals("MESH-ALICE", update.getOfflineMeshId());
        assertEquals("ONLINE", update.getStatus());
        assertTrue(update.isTyping());
        assertFalse(update.isRecording());
        assertNotNull(update.getLastSeen());
    }

    @Test
    void testGroupDTOAndMemberDTO() {
        UUID groupId = UUID.randomUUID();
        GroupMemberDTO memberDTO = GroupMemberDTO.builder()
                .offlineMeshId("MESH-BOB")
                .username("bob")
                .role("MEMBER")
                .joinedAt(Instant.now())
                .build();

        GroupDTO groupDTO = GroupDTO.builder()
                .id(groupId)
                .name("Alpha Squad")
                .description("Mesh coordination")
                .createdByOfflineMeshId("MESH-ALICE")
                .createdAt(Instant.now())
                .members(java.util.List.of(memberDTO))
                .build();

        assertEquals(groupId, groupDTO.getId());
        assertEquals("Alpha Squad", groupDTO.getName());
        assertEquals(1, groupDTO.getMembers().size());
        assertEquals("MESH-BOB", groupDTO.getMembers().get(0).getOfflineMeshId());
    }
}
