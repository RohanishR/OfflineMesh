package com.offlinemesh.backend.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Data Transfer Object for group conversation details and members.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class GroupDTO {
    private UUID id;
    private String name;
    private String description;
    private String createdByOfflineMeshId;
    private Instant createdAt;
    private List<GroupMemberDTO> members;
}
