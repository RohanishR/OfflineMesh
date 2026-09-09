package com.offlinemesh.backend.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FileMetadataCreateRequest {
    private String recipientOfflineMeshId;
    private String originalFileName;
    private String contentType;
    private Long fileSize;
    private String checksum;
}
