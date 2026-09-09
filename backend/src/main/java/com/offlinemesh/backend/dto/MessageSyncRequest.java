package com.offlinemesh.backend.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class MessageSyncRequest {
    private String cursor; // ISO-8601 timestamp string
    private Integer limit;
}
