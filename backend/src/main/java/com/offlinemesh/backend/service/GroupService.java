package com.offlinemesh.backend.service;

import com.offlinemesh.backend.dto.CreateGroupRequest;
import com.offlinemesh.backend.dto.GroupDTO;
import com.offlinemesh.backend.dto.GroupMemberDTO;
import com.offlinemesh.backend.dto.MessageResponse;
import com.offlinemesh.backend.dto.SendMessageRequest;
import com.offlinemesh.backend.entity.Group;
import com.offlinemesh.backend.entity.GroupMember;
import com.offlinemesh.backend.entity.Message;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.enums.GroupRole;
import com.offlinemesh.backend.entity.enums.MessageStatus;
import com.offlinemesh.backend.entity.enums.MessageType;
import com.offlinemesh.backend.entity.enums.TransportType;
import com.offlinemesh.backend.repository.GroupMemberRepository;
import com.offlinemesh.backend.repository.GroupRepository;
import com.offlinemesh.backend.repository.MessageRepository;
import com.offlinemesh.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class GroupService {

    private final GroupRepository groupRepository;
    private final GroupMemberRepository groupMemberRepository;
    private final UserRepository userRepository;
    private final MessageRepository messageRepository;
    private final SimpMessagingTemplate messagingTemplate;

    @Transactional
    public GroupDTO createGroup(User currentUser, CreateGroupRequest request) {
        if (request.getName() == null || request.getName().trim().isEmpty()) {
            throw new IllegalArgumentException("Group name is required");
        }

        Group group = Group.builder()
                .name(request.getName().trim())
                .description(request.getDescription())
                .createdBy(currentUser)
                .members(new ArrayList<>())
                .build();

        final Group savedGroup = groupRepository.save(group);

        // Add creator as ADMIN
        GroupMember adminMember = GroupMember.builder()
                .group(savedGroup)
                .user(currentUser)
                .role(GroupRole.ADMIN)
                .build();
        groupMemberRepository.save(adminMember);
        savedGroup.getMembers().add(adminMember);

        // Add initial members
        if (request.getMemberOfflineMeshIds() != null) {
            for (String meshId : request.getMemberOfflineMeshIds()) {
                if (meshId == null || meshId.equals(currentUser.getOfflineMeshId())) continue;
                userRepository.findByOfflineMeshId(meshId).ifPresent(memberUser -> {
                    GroupMember member = GroupMember.builder()
                            .group(savedGroup)
                            .user(memberUser)
                            .role(GroupRole.MEMBER)
                            .build();
                    groupMemberRepository.save(member);
                    savedGroup.getMembers().add(member);
                });
            }
        }

        return toDTO(savedGroup);
    }

    @Transactional(readOnly = true)
    public List<GroupDTO> getUserGroups(User currentUser) {
        return groupRepository.findAllByUser(currentUser).stream()
                .map(this::toDTO)
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public GroupDTO getGroupDetails(User currentUser, UUID groupId) {
        Group group = groupRepository.findById(groupId)
                .orElseThrow(() -> new IllegalArgumentException("Group not found"));

        boolean isMember = groupMemberRepository.existsByGroupAndUser(group, currentUser);
        if (!isMember) {
            throw new IllegalArgumentException("You are not a member of this group");
        }

        return toDTO(group);
    }

    @Transactional
    public GroupDTO addMember(User currentUser, UUID groupId, String newMemberOfflineMeshId) {
        Group group = groupRepository.findById(groupId)
                .orElseThrow(() -> new IllegalArgumentException("Group not found"));

        boolean isAdmin = groupMemberRepository.existsByGroupAndUserAndRole(group, currentUser, GroupRole.ADMIN);
        if (!isAdmin) {
            throw new SecurityException("Only group admins can add members");
        }

        User newMember = userRepository.findByOfflineMeshId(newMemberOfflineMeshId)
                .orElseThrow(() -> new IllegalArgumentException("User not found: " + newMemberOfflineMeshId));

        if (groupMemberRepository.existsByGroupAndUser(group, newMember)) {
            return toDTO(group);
        }

        GroupMember member = GroupMember.builder()
                .group(group)
                .user(newMember)
                .role(GroupRole.MEMBER)
                .build();
        groupMemberRepository.save(member);
        group.getMembers().add(member);

        return toDTO(group);
    }

    @Transactional
    public GroupDTO removeMember(User currentUser, UUID groupId, String targetOfflineMeshId) {
        Group group = groupRepository.findById(groupId)
                .orElseThrow(() -> new IllegalArgumentException("Group not found"));

        User targetUser = userRepository.findByOfflineMeshId(targetOfflineMeshId)
                .orElseThrow(() -> new IllegalArgumentException("User not found: " + targetOfflineMeshId));

        boolean isSelf = currentUser.getId().equals(targetUser.getId());
        boolean isAdmin = groupMemberRepository.existsByGroupAndUserAndRole(group, currentUser, GroupRole.ADMIN);

        if (!isSelf && !isAdmin) {
            throw new SecurityException("Only admins can remove other members");
        }

        groupMemberRepository.deleteByGroupAndUser(group, targetUser);
        group.getMembers().removeIf(m -> m.getUser().getId().equals(targetUser.getId()));

        return toDTO(group);
    }

    @Transactional(readOnly = true)
    public List<MessageResponse> getGroupMessages(User currentUser, UUID groupId) {
        Group group = groupRepository.findById(groupId)
                .orElseThrow(() -> new IllegalArgumentException("Group not found"));

        if (!groupMemberRepository.existsByGroupAndUser(group, currentUser)) {
            throw new SecurityException("Access denied: You are not a member of this group");
        }

        return messageRepository.findByGroupOrderByCreatedAtAsc(group).stream()
                .map(m -> MessageResponse.builder()
                        .id(m.getId().toString())
                        .senderOfflineMeshId(m.getSender().getOfflineMeshId())
                        .content(m.getContent())
                        .createdAt(m.getCreatedAt() != null ? m.getCreatedAt().toString() : "")
                        .status(m.getStatus().name().toLowerCase())
                        .isEdited(m.isEdited())
                        .isDeleted(m.isDeleted())
                        .build())
                .collect(Collectors.toList());
    }

    @Transactional
    public MessageResponse sendGroupMessage(User currentUser, UUID groupId, SendMessageRequest request) {
        Group group = groupRepository.findById(groupId)
                .orElseThrow(() -> new IllegalArgumentException("Group not found"));

        if (!groupMemberRepository.existsByGroupAndUser(group, currentUser)) {
            throw new SecurityException("Access denied: Cannot send message to a group you are not a member of");
        }

        UUID messageId = UUID.randomUUID();

        Message message = Message.builder()
                .id(messageId)
                .isNew(true)
                .sender(currentUser)
                .group(group)
                .content(request.getContent())
                .messageType(MessageType.TEXT)
                .status(MessageStatus.SENT)
                .transportType(TransportType.INTERNET)
                .build();

        message = messageRepository.save(message);

        MessageResponse response = MessageResponse.builder()
                .id(message.getId().toString())
                .senderOfflineMeshId(currentUser.getOfflineMeshId())
                .content(message.getContent())
                .createdAt(message.getCreatedAt() != null ? message.getCreatedAt().toString() : "")
                .status("sent")
                .build();

        // Broadcast to all other members in the group via WebSocket
        List<GroupMember> members = groupMemberRepository.findByGroup(group);
        for (GroupMember m : members) {
            if (!m.getUser().getId().equals(currentUser.getId())) {
                messagingTemplate.convertAndSendToUser(
                        m.getUser().getUsername(),
                        "/queue/messages",
                        response
                );
            }
        }

        return response;
    }

    public GroupDTO toDTO(Group group) {
        List<GroupMemberDTO> memberDTOs = group.getMembers() != null
                ? group.getMembers().stream()
                .map(m -> GroupMemberDTO.builder()
                        .offlineMeshId(m.getUser().getOfflineMeshId())
                        .username(m.getUser().getUsername())
                        .role(m.getRole().name())
                        .joinedAt(m.getJoinedAt())
                        .build())
                .collect(Collectors.toList())
                : new ArrayList<>();

        return GroupDTO.builder()
                .id(group.getId())
                .name(group.getName())
                .description(group.getDescription())
                .createdByOfflineMeshId(group.getCreatedBy().getOfflineMeshId())
                .createdAt(group.getCreatedAt())
                .members(memberDTOs)
                .build();
    }
}
