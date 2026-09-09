package com.offlinemesh.backend.controller;

import com.offlinemesh.backend.dto.FileMetadataCreateRequest;
import com.offlinemesh.backend.dto.FileMetadataResponse;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.service.FileMetadataService;
import com.offlinemesh.backend.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.security.Principal;
import java.util.List;
import java.util.UUID;

import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.multipart.MultipartFile;
import com.offlinemesh.backend.service.FileTransferService;

@RestController
@RequestMapping("/api/files")
@RequiredArgsConstructor
public class FileMetadataController {

    private final FileMetadataService fileMetadataService;
    private final FileTransferService fileTransferService;
    private final UserService userService;

    @PostMapping("/metadata")
    public ResponseEntity<FileMetadataResponse> createMetadata(@RequestBody FileMetadataCreateRequest request, Principal principal) {
        if (principal == null) return ResponseEntity.status(401).build();
        User currentUser = userService.findByUsername(principal.getName());
        FileMetadataResponse response = fileMetadataService.createMetadata(currentUser, request);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/{fileId}")
    public ResponseEntity<FileMetadataResponse> getMetadata(@PathVariable UUID fileId, Principal principal) {
        if (principal == null) return ResponseEntity.status(401).build();
        User currentUser = userService.findByUsername(principal.getName());
        FileMetadataResponse response = fileMetadataService.getMetadata(currentUser, fileId);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/sent")
    public ResponseEntity<List<FileMetadataResponse>> getSentFiles(Principal principal) {
        if (principal == null) return ResponseEntity.status(401).build();
        User currentUser = userService.findByUsername(principal.getName());
        List<FileMetadataResponse> responses = fileMetadataService.getSentFiles(currentUser);
        return ResponseEntity.ok(responses);
    }

    @GetMapping("/received")
    public ResponseEntity<List<FileMetadataResponse>> getReceivedFiles(Principal principal) {
        if (principal == null) return ResponseEntity.status(401).build();
        User currentUser = userService.findByUsername(principal.getName());
        List<FileMetadataResponse> responses = fileMetadataService.getReceivedFiles(currentUser);
        return ResponseEntity.ok(responses);
    }

    @PostMapping("/{fileId}/upload")
    public ResponseEntity<FileMetadataResponse> uploadFile(@PathVariable UUID fileId, @RequestParam("file") MultipartFile file, Principal principal) {
        if (principal == null) return ResponseEntity.status(401).build();
        User currentUser = userService.findByUsername(principal.getName());
        FileMetadataResponse response = fileTransferService.uploadFile(currentUser, fileId, file);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/{fileId}/download")
    public ResponseEntity<org.springframework.core.io.Resource> downloadFile(@PathVariable UUID fileId, Principal principal) {
        if (principal == null) return ResponseEntity.status(401).build();
        User currentUser = userService.findByUsername(principal.getName());
        org.springframework.core.io.Resource resource = fileTransferService.downloadFile(currentUser, fileId);
        com.offlinemesh.backend.entity.FileMetadata metadata = fileTransferService.getMetadata(fileId);

        return ResponseEntity.ok()
                .header(org.springframework.http.HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + metadata.getOriginalFileName() + "\"")
                .header(org.springframework.http.HttpHeaders.CONTENT_TYPE, metadata.getContentType())
                .header(org.springframework.http.HttpHeaders.CONTENT_LENGTH, String.valueOf(metadata.getFileSize()))
                .body(resource);
    }
}
