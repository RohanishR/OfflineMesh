package com.offlinemesh.backend.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;

@Slf4j
@Service
public class LocalFileStorageService implements FileStorageService {

    private final Path rootLocation;

    public LocalFileStorageService(@Value("${file.storage.path:./uploads}") String storagePath) {
        this.rootLocation = Paths.get(storagePath).toAbsolutePath().normalize();
        try {
            Files.createDirectories(this.rootLocation);
        } catch (IOException e) {
            throw new RuntimeException("Could not initialize storage directory at " + rootLocation, e);
        }
    }

    @Override
    public String store(InputStream inputStream, String storageKey) {
        try {
            Path destinationFile = rootLocation.resolve(Paths.get(storageKey)).normalize().toAbsolutePath();
            if (!destinationFile.getParent().equals(rootLocation)) {
                throw new SecurityException("Cannot store file outside current directory. Path traversal attempt.");
            }
            Files.copy(inputStream, destinationFile, StandardCopyOption.REPLACE_EXISTING);
            return storageKey;
        } catch (IOException e) {
            throw new RuntimeException("Failed to store file", e);
        }
    }

    @Override
    public InputStream retrieve(String storageKey) {
        try {
            Path file = rootLocation.resolve(Paths.get(storageKey)).normalize().toAbsolutePath();
            if (!file.getParent().equals(rootLocation)) {
                throw new SecurityException("Cannot read file outside current directory. Path traversal attempt.");
            }
            if (Files.exists(file) && Files.isReadable(file)) {
                return new FileInputStream(file.toFile());
            } else {
                throw new RuntimeException("Could not read file: " + storageKey);
            }
        } catch (IOException e) {
            throw new RuntimeException("Could not read file", e);
        }
    }

    @Override
    public boolean delete(String storageKey) {
        try {
            Path file = rootLocation.resolve(Paths.get(storageKey)).normalize().toAbsolutePath();
            if (!file.getParent().equals(rootLocation)) {
                throw new SecurityException("Cannot delete file outside current directory. Path traversal attempt.");
            }
            return Files.deleteIfExists(file);
        } catch (IOException e) {
            log.error("Failed to delete file: {}", storageKey, e);
            return false;
        }
    }

    @Override
    public boolean exists(String storageKey) {
        Path file = rootLocation.resolve(Paths.get(storageKey)).normalize().toAbsolutePath();
        if (!file.getParent().equals(rootLocation)) {
            return false;
        }
        return Files.exists(file);
    }
}
