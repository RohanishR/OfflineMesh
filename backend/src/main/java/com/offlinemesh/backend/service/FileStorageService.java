package com.offlinemesh.backend.service;

import java.io.InputStream;

public interface FileStorageService {
    String store(InputStream inputStream, String storageKey);
    InputStream retrieve(String storageKey);
    boolean delete(String storageKey);
    boolean exists(String storageKey);
}
