package com.offlinemesh.backend.service;

import com.offlinemesh.backend.dto.RegistrationRequest;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.exception.DuplicateEmailException;
import com.offlinemesh.backend.exception.DuplicateUsernameException;
import com.offlinemesh.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    private String generateUniqueOfflineMeshId() {
        String chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        java.util.Random rnd = new java.security.SecureRandom();
        while (true) {
            StringBuilder sb = new StringBuilder("OM-");
            for (int i = 0; i < 8; i++) {
                sb.append(chars.charAt(rnd.nextInt(chars.length())));
            }
            String id = sb.toString();
            if (!userRepository.existsByOfflineMeshId(id)) {
                return id;
            }
        }
    }

    @Transactional
    public User registerUser(RegistrationRequest request) {
        if (userRepository.existsByUsername(request.getUsername())) {
            throw new DuplicateUsernameException("Username '" + request.getUsername() + "' is already taken.");
        }

        if (userRepository.existsByEmail(request.getEmail())) {
            throw new DuplicateEmailException("Email '" + request.getEmail() + "' is already registered.");
        }

        User user = User.builder()
                .username(request.getUsername())
                .email(request.getEmail())
                .passwordHash(passwordEncoder.encode(request.getPassword()))
                .offlineMeshId(generateUniqueOfflineMeshId())
                .build();

        return userRepository.save(user);
    }

    public User login(com.offlinemesh.backend.dto.LoginRequest request) {
        User user = userRepository.findByUsername(request.getUsername())
                .orElseThrow(() -> new com.offlinemesh.backend.exception.InvalidCredentialsException("Invalid username or password"));

        if (!passwordEncoder.matches(request.getPassword(), user.getPasswordHash())) {
            throw new com.offlinemesh.backend.exception.InvalidCredentialsException("Invalid username or password");
        }

        return user;
    }

    public User findByUsername(String username) {
        return userRepository.findByUsername(username)
                .orElseThrow(() -> new com.offlinemesh.backend.exception.InvalidCredentialsException("User not found"));
    }

    public User getPublicProfile(String offlineMeshId) {
        return userRepository.findByOfflineMeshId(offlineMeshId)
                .orElseThrow(() -> new com.offlinemesh.backend.exception.UserNotFoundException("User not found"));
    }

    @Transactional
    public User updateProfile(User currentUser, com.offlinemesh.backend.dto.UpdateProfileRequest request) {
        if (request.getUsername() != null && !request.getUsername().equals(currentUser.getUsername())) {
            if (userRepository.existsByUsername(request.getUsername())) {
                throw new DuplicateUsernameException("Username '" + request.getUsername() + "' is already taken.");
            }
            currentUser.setUsername(request.getUsername());
        }

        if (request.getEmail() != null && !request.getEmail().equals(currentUser.getEmail())) {
            if (userRepository.existsByEmail(request.getEmail())) {
                throw new DuplicateEmailException("Email '" + request.getEmail() + "' is already registered.");
            }
            currentUser.setEmail(request.getEmail());
        }

        return userRepository.save(currentUser);
    }

    @Transactional
    public void changePassword(User currentUser, com.offlinemesh.backend.dto.ChangePasswordRequest request) {
        if (!passwordEncoder.matches(request.getCurrentPassword(), currentUser.getPasswordHash())) {
            throw new com.offlinemesh.backend.exception.InvalidCredentialsException("Current password is incorrect");
        }
        
        if (request.getNewPassword() == null || request.getNewPassword().length() < 6) {
            throw new IllegalArgumentException("New password must be at least 6 characters long");
        }

        currentUser.setPasswordHash(passwordEncoder.encode(request.getNewPassword()));
        userRepository.save(currentUser);
    }
}
