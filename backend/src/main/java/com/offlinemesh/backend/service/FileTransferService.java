package com.offlinemesh.backend.service;

import com.offlinemesh.backend.dto.FileMetadataResponse;
import com.offlinemesh.backend.entity.FileMetadata;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.enums.FileTransferStatus;
import com.offlinemesh.backend.exception.UnauthorizedMessagingException;
import com.offlinemesh.backend.repository.FileMetadataRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.io.InputStreamResource;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.io.InputStream;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class FileTransferService {

    private final FileMetadataRepository fileMetadataRepository;
    private final FileStorageService fileStorageService;

    @Transactional
    public FileMetadataResponse uploadFile(User currentUser, UUID fileId, MultipartFile file) {
        FileMetadata metadata = fileMetadataRepository.findById(fileId)
                .orElseThrow(() -> new IllegalArgumentException("File metadata not found"));

        if (!metadata.getSender().getId().equals(currentUser.getId())) {
            throw new UnauthorizedMessagingException("Only the sender can upload the file");
        }

        if (metadata.getStatus() == FileTransferStatus.COMPLETED || metadata.getStatus() == FileTransferStatus.AVAILABLE) {
            throw new IllegalStateException("File is already uploaded");
        }

        metadata.setStatus(FileTransferStatus.UPLOADING);
        fileMetadataRepository.save(metadata); // Flush UPLOADING state

        String storageKey = UUID.randomUUID().toString();
        
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (InputStream is = file.getInputStream();
                 DigestInputStream dis = new DigestInputStream(is, digest)) {
                
                fileStorageService.store(dis, storageKey);
            }

            byte[] hashBytes = digest.digest();
            StringBuilder hexString = new StringBuilder();
            for (byte b : hashBytes) {
                String hex = Integer.toHexString(0xff & b);
                if (hex.length() == 1) hexString.append('0');
                hexString.append(hex);
            }

            metadata.setChecksum(hexString.toString());
            metadata.setStorageKey(storageKey);
            metadata.setFileSize(file.getSize());
            metadata.setStatus(FileTransferStatus.AVAILABLE);

        } catch (Exception e) {
            metadata.setStatus(FileTransferStatus.FAILED);
            fileStorageService.delete(storageKey);
            fileMetadataRepository.save(metadata);
            throw new RuntimeException("File upload failed", e);
        }

        metadata = fileMetadataRepository.save(metadata);

        return FileMetadataResponse.builder()
                .id(metadata.getId().toString())
                .senderOfflineMeshId(metadata.getSender().getOfflineMeshId())
                .recipientOfflineMeshId(metadata.getRecipient().getOfflineMeshId())
                .originalFileName(metadata.getOriginalFileName())
                .contentType(metadata.getContentType())
                .fileSize(metadata.getFileSize())
                .checksum(metadata.getChecksum())
                .status(metadata.getStatus())
                .createdAt(metadata.getCreatedAt())
                .updatedAt(metadata.getUpdatedAt())
                .build();
    }

    @Transactional(readOnly = true)
    public Resource downloadFile(User currentUser, UUID fileId) {
        FileMetadata metadata = fileMetadataRepository.findById(fileId)
                .orElseThrow(() -> new IllegalArgumentException("File metadata not found"));

        if (!metadata.getSender().getId().equals(currentUser.getId()) &&
            !metadata.getRecipient().getId().equals(currentUser.getId())) {
            throw new UnauthorizedMessagingException("You are not authorized to download this file");
        }

        if (metadata.getStatus() != FileTransferStatus.AVAILABLE && metadata.getStatus() != FileTransferStatus.COMPLETED) {
            throw new IllegalStateException("File is not available for download");
        }

        InputStream is = fileStorageService.retrieve(metadata.getStorageKey());
        return new InputStreamResource(is);
    }
    
    @Transactional(readOnly = true)
    public FileMetadata getMetadata(UUID fileId) {
        return fileMetadataRepository.findById(fileId)
                .orElseThrow(() -> new IllegalArgumentException("File metadata not found"));
    }
}
