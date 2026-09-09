package com.offlinemesh.backend.repository;

import com.offlinemesh.backend.entity.FileMetadata;
import com.offlinemesh.backend.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.UUID;

@Repository
public interface FileMetadataRepository extends JpaRepository<FileMetadata, UUID> {
    List<FileMetadata> findBySenderOrderByCreatedAtDesc(User sender);
    List<FileMetadata> findByRecipientOrderByCreatedAtDesc(User recipient);
}
