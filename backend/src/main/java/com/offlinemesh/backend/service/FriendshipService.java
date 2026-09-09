package com.offlinemesh.backend.service;

import com.offlinemesh.backend.entity.Friendship;
import com.offlinemesh.backend.entity.User;
import com.offlinemesh.backend.repository.FriendshipRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class FriendshipService {

    private final FriendshipRepository friendshipRepository;
    private final UserService userService;

    @Transactional
    public User connect(User currentUser, String targetOfflineMeshId) {
        User targetUser = userService.getPublicProfile(targetOfflineMeshId);

        if (currentUser.getId().equals(targetUser.getId())) {
            throw new IllegalArgumentException("Cannot connect with yourself");
        }

        boolean alreadyFriends = friendshipRepository.existsFriendshipBetween(currentUser, targetUser);
        
        if (!alreadyFriends) {
            Friendship friendship = Friendship.builder()
                    .user1(currentUser)
                    .user2(targetUser)
                    .build();
            friendshipRepository.save(friendship);
        }

        return targetUser;
    }

    public java.util.List<User> getFriends(User currentUser) {
        java.util.List<Friendship> friendships = friendshipRepository.findFriendshipsByUser(currentUser);
        return friendships.stream()
                .map(f -> f.getUser1().getId().equals(currentUser.getId()) ? f.getUser2() : f.getUser1())
                .collect(java.util.stream.Collectors.toList());
    }

    @Transactional
    public void removeFriend(User currentUser, String targetOfflineMeshId) {
        User targetUser = userService.getPublicProfile(targetOfflineMeshId);

        if (currentUser.getId().equals(targetUser.getId())) {
            throw new IllegalArgumentException("Cannot remove yourself");
        }

        Friendship friendship = friendshipRepository.findFriendshipBetween(currentUser, targetUser)
                .orElseThrow(() -> new com.offlinemesh.backend.exception.FriendshipNotFoundException("Friendship not found"));

        friendshipRepository.delete(friendship);
    }
}
