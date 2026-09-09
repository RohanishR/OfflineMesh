package com.offlinemesh.backend.service;

import com.offlinemesh.backend.dto.FileMetadataCreateRequest;
import com.offlinemesh.backend.dto.FileMetadataResponse;
import com.offlinemesh.backend.entity.FileMetadata;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.enums.FileTransferStatus;
import com.offlinemesh.backend.exception.NotFriendsException;
import com.offlinemesh.backend.exception.UnauthorizedMessagingException;
import com.offlinemesh.backend.repository.FileMetadataRepository;
import com.offlinemesh.backend.repository.FriendshipRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class FileMetadataService {

    private final FileMetadataRepository fileMetadataRepository;
    private final UserService userService;
    private final FriendshipRepository friendshipRepository;

    @Transactional
    public FileMetadataResponse createMetadata(User sender, FileMetadataCreateRequest request) {
        User recipient = userService.getPublicProfile(request.getRecipientOfflineMeshId());

        if (sender.getId().equals(recipient.getId())) {
            throw new IllegalArgumentException("Cannot send a file to yourself");
        }

        if (!friendshipRepository.existsFriendshipBetween(sender, recipient)) {
            throw new NotFriendsException("Cannot send file. You are not friends with this user.");
        }

        FileMetadata metadata = FileMetadata.builder()
                .id(UUID.randomUUID())
                .sender(sender)
                .recipient(recipient)
                .originalFileName(request.getOriginalFileName())
                .contentType(request.getContentType())
                .fileSize(request.getFileSize())
                .checksum(request.getChecksum())
                .status(FileTransferStatus.PENDING)
                .build();

        metadata = fileMetadataRepository.save(metadata);
        return mapToResponse(metadata);
    }

    @Transactional(readOnly = true)
    public FileMetadataResponse getMetadata(User user, UUID fileId) {
        FileMetadata metadata = fileMetadataRepository.findById(fileId)
                .orElseThrow(() -> new IllegalArgumentException("File metadata not found"));

        if (!metadata.getSender().getId().equals(user.getId()) &&
                !metadata.getRecipient().getId().equals(user.getId())) {
            throw new UnauthorizedMessagingException("You are not authorized to view this file metadata.");
        }

        return mapToResponse(metadata);
    }

    @Transactional(readOnly = true)
    public List<FileMetadataResponse> getSentFiles(User sender) {
        return fileMetadataRepository.findBySenderOrderByCreatedAtDesc(sender)
                .stream()
                .map(this::mapToResponse)
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<FileMetadataResponse> getReceivedFiles(User recipient) {
        return fileMetadataRepository.findByRecipientOrderByCreatedAtDesc(recipient)
                .stream()
                .map(this::mapToResponse)
                .collect(Collectors.toList());
    }

    private FileMetadataResponse mapToResponse(FileMetadata metadata) {
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
}
