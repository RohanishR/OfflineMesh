package com.offlinemesh.backend.dto;

import com.offlinemesh.backend.entity.enums.FileTransferStatus;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FileMetadataResponse {
    private String id;
    private String senderOfflineMeshId;
    private String recipientOfflineMeshId;
    private String originalFileName;
    private String contentType;
    private Long fileSize;
    private String checksum;
    private FileTransferStatus status;
    private Instant createdAt;
    private Instant updatedAt;
}
