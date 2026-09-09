package com.offlinemesh.backend.repository;

import com.offlinemesh.backend.entity.Delivery;
import com.offlinemesh.backend.entity.Message;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.UUID;

@Repository
public interface DeliveryRepository extends JpaRepository<Delivery, UUID> {
    List<Delivery> findByMessageOrderBySentAtAsc(Message message);
}
