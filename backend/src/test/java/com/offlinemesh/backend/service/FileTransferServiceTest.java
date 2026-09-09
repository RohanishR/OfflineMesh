package com.offlinemesh.backend.service;

import com.offlinemesh.backend.dto.FileMetadataResponse;
import com.offlinemesh.backend.entity.FileMetadata;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.entity.enums.FileTransferStatus;
import com.offlinemesh.backend.exception.UnauthorizedMessagingException;
import com.offlinemesh.backend.repository.FileMetadataRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.core.io.Resource;
import org.springframework.web.multipart.MultipartFile;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

class FileTransferServiceTest {

    @Mock
    private FileMetadataRepository fileMetadataRepository;

    @Mock
    private FileStorageService fileStorageService;

    @Mock
    private MultipartFile multipartFile;

    @InjectMocks
    private FileTransferService fileTransferService;

    private User sender;
    private User recipient;
    private FileMetadata metadata;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        sender = User.builder().id(UUID.randomUUID()).offlineMeshId("SENDER").build();
        recipient = User.builder().id(UUID.randomUUID()).offlineMeshId("RECIPIENT").build();
        
        metadata = FileMetadata.builder()
                .id(UUID.randomUUID())
                .sender(sender)
                .recipient(recipient)
                .originalFileName("test.txt")
                .contentType("text/plain")
                .fileSize(12L)
                .status(FileTransferStatus.PENDING)
                .build();
    }

    @Test
    void testUploadFile_Success() throws Exception {
        when(fileMetadataRepository.findById(metadata.getId())).thenReturn(Optional.of(metadata));
        when(fileMetadataRepository.save(any(FileMetadata.class))).thenReturn(metadata);
        
        String content = "hello world!";
        InputStream is = new ByteArrayInputStream(content.getBytes());
        when(multipartFile.getInputStream()).thenReturn(is);
        when(multipartFile.getSize()).thenReturn(12L);
        when(fileStorageService.store(any(InputStream.class), anyString())).thenReturn("test-key");

        FileMetadataResponse response = fileTransferService.uploadFile(sender, metadata.getId(), multipartFile);
        
        assertNotNull(response.getChecksum());
        assertEquals(FileTransferStatus.AVAILABLE, response.getStatus());
        verify(fileStorageService, times(1)).store(any(InputStream.class), anyString());
    }

    @Test
    void testUploadFile_Unauthorized() {
        when(fileMetadataRepository.findById(metadata.getId())).thenReturn(Optional.of(metadata));
        
        assertThrows(UnauthorizedMessagingException.class, () -> fileTransferService.uploadFile(recipient, metadata.getId(), multipartFile));
    }

    @Test
    void testDownloadFile_Success() throws Exception {
        metadata.setStatus(FileTransferStatus.AVAILABLE);
        metadata.setStorageKey("test-key");
        
        when(fileMetadataRepository.findById(metadata.getId())).thenReturn(Optional.of(metadata));
        InputStream is = new ByteArrayInputStream("hello".getBytes());
        when(fileStorageService.retrieve("test-key")).thenReturn(is);

        Resource resource = fileTransferService.downloadFile(recipient, metadata.getId());
        
        assertNotNull(resource);
        assertTrue(resource.exists());
    }
}
