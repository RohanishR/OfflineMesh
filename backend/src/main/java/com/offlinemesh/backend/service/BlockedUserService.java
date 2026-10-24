package com.offlinemesh.backend.service;

import com.offlinemesh.backend.dto.PublicUserProfileResponse;
import com.offlinemesh.backend.entity.BlockedUser;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.repository.BlockedUserRepository;
import com.offlinemesh.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class BlockedUserService {

    private final BlockedUserRepository blockedUserRepository;
    private final UserRepository userRepository;

    @Transactional
    public void blockUser(User currentUser, String targetOfflineMeshId) {
        User target = userRepository.findByOfflineMeshId(targetOfflineMeshId)
                .orElseThrow(() -> new IllegalArgumentException("User not found: " + targetOfflineMeshId));

        if (currentUser.getId().equals(target.getId())) {
            throw new IllegalArgumentException("Cannot block yourself");
        }

        if (!blockedUserRepository.existsByBlockerAndBlocked(currentUser, target)) {
            BlockedUser blockedUser = BlockedUser.builder()
                    .blocker(currentUser)
                    .blocked(target)
                    .build();
            blockedUserRepository.save(blockedUser);
            log.info("User {} blocked {}", currentUser.getOfflineMeshId(), targetOfflineMeshId);
        }
    }

    @Transactional
    public void unblockUser(User currentUser, String targetOfflineMeshId) {
        User target = userRepository.findByOfflineMeshId(targetOfflineMeshId)
                .orElseThrow(() -> new IllegalArgumentException("User not found: " + targetOfflineMeshId));

        blockedUserRepository.deleteByBlockerAndBlocked(currentUser, target);
        log.info("User {} unblocked {}", currentUser.getOfflineMeshId(), targetOfflineMeshId);
    }

    @Transactional(readOnly = true)
    public List<PublicUserProfileResponse> getBlockedUsers(User currentUser) {
        return blockedUserRepository.findByBlocker(currentUser).stream()
                .map(b -> PublicUserProfileResponse.builder()
                        .offlineMeshId(b.getBlocked().getOfflineMeshId())
                        .username(b.getBlocked().getUsername())
                        .build())
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public boolean isCommunicationBlocked(User sender, User recipient) {
        if (sender == null || recipient == null) return false;
        return blockedUserRepository.existsByBlockerAndBlocked(recipient, sender)
                || blockedUserRepository.existsByBlockerAndBlocked(sender, recipient);
    }
}
