package com.offlinemesh.backend.service;

import com.offlinemesh.backend.dto.FileMetadataCreateRequest;
import com.offlinemesh.backend.dto.FileMetadataResponse;
import com.offlinemesh.backend.entity.FileMetadata;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.exception.UnauthorizedMessagingException;
import com.offlinemesh.backend.repository.FileMetadataRepository;
import com.offlinemesh.backend.repository.FriendshipRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

class FileMetadataServiceTest {

    @Mock
    private FileMetadataRepository fileMetadataRepository;

    @Mock
    private UserService userService;

    @Mock
    private FriendshipRepository friendshipRepository;

    @InjectMocks
    private FileMetadataService fileMetadataService;

    private User sender;
    private User recipient;
    private User unrelatedUser;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);

        sender = User.builder().id(UUID.randomUUID()).offlineMeshId("OM-SENDER").build();
        recipient = User.builder().id(UUID.randomUUID()).offlineMeshId("OM-RECIPIENT").build();
        unrelatedUser = User.builder().id(UUID.randomUUID()).offlineMeshId("OM-OTHER").build();
    }

    @Test
    void testGetMetadata_BySender_Success() {
        UUID fileId = UUID.randomUUID();
        FileMetadata metadata = FileMetadata.builder()
                .id(fileId)
                .sender(sender)
                .recipient(recipient)
                .originalFileName("test.txt")
                .build();

        when(fileMetadataRepository.findById(fileId)).thenReturn(Optional.of(metadata));

        FileMetadataResponse response = fileMetadataService.getMetadata(sender, fileId);
        assertEquals("test.txt", response.getOriginalFileName());
    }

    @Test
    void testGetMetadata_ByRecipient_Success() {
        UUID fileId = UUID.randomUUID();
        FileMetadata metadata = FileMetadata.builder()
                .id(fileId)
                .sender(sender)
                .recipient(recipient)
                .originalFileName("test.txt")
                .build();

        when(fileMetadataRepository.findById(fileId)).thenReturn(Optional.of(metadata));

        FileMetadataResponse response = fileMetadataService.getMetadata(recipient, fileId);
        assertEquals("test.txt", response.getOriginalFileName());
    }

    @Test
    void testGetMetadata_ByUnrelatedUser_ThrowsException() {
        UUID fileId = UUID.randomUUID();
        FileMetadata metadata = FileMetadata.builder()
                .id(fileId)
                .sender(sender)
                .recipient(recipient)
                .originalFileName("test.txt")
                .build();

        when(fileMetadataRepository.findById(fileId)).thenReturn(Optional.of(metadata));

        assertThrows(UnauthorizedMessagingException.class, () -> fileMetadataService.getMetadata(unrelatedUser, fileId));
    }
}
