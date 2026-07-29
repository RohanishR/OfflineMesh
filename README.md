# MeshLink

> A secure hybrid communication platform that enables messaging, file sharing, and real-time communication over the Internet, Local Area Networks (LAN), and nearby peer-to-peer connections without relying solely on centralized infrastructure.

---

# Project Overview

OfflineMesh is a hybrid communication application designed to ensure uninterrupted communication even when internet connectivity is unavailable. The application intelligently switches between Internet, Local Wi-Fi/LAN, and Bluetooth-based peer-to-peer communication, allowing users to exchange messages, files, and communicate securely in nearby environments such as hostels, campuses, offices, and disaster-affected areas.

Unlike traditional messaging applications that become unusable without an internet connection, OfflineMesh continues to provide local communication through direct device-to-device networking.

---

# Problem it Solves

Current messaging applications such as WhatsApp, Telegram, and Signal depend heavily on internet connectivity.

During situations such as:
- Internet outages
- Natural disasters
- Campus network failures
- Rural areas with poor connectivity
- Temporary communication blackouts

users lose the ability to communicate with people around them despite being physically nearby.

OfflineMesh addresses this problem by enabling communication over Bluetooth and Local Wi-Fi without requiring external servers or cellular networks.

---

# Target Users (Personas)

## 1. College Student
- Lives in a hostel
- Wants to share notes and chat without internet
- Needs fast file sharing between nearby devices

### Needs
- Offline messaging
- Group chats
- File transfer

---

## 2. Emergency Response Teams

Firefighters, volunteers, and rescue teams operating in disaster zones where communication infrastructure is unavailable.

### Needs
- Reliable nearby communication
- Secure messaging
- Offline operation

---

## 3. Organizations & Offices

Employees working within the same building or campus.

### Needs
- Internal communication
- Secure file sharing
- Communication during network outages

---

## 4. Event Participants

Users attending festivals, conferences, concerts, or sports events where mobile networks become congested.

### Needs
- Nearby messaging
- Group announcements
- File sharing

---

# Vision Statement

> To build a secure, decentralized communication platform that enables seamless communication anytime and anywhere, regardless of internet availability, while protecting user privacy through end-to-end encryption.

---

# Key Features / Goals

## Phase 1
- Secure user authentication
- One-to-one messaging
- Group chats
- End-to-end encrypted messages

---

## Phase 2
- Bluetooth device discovery
- Offline peer-to-peer messaging
- Automatic nearby user detection
- Message synchronization

---

## Phase 3
- Wi-Fi LAN messaging
- Wi-Fi Direct communication
- File sharing
- Image and document transfer

---

## Phase 4
- Internet messaging
- Online synchronization
- Voice calls
- Video calls
- Push notifications

---

## Phase 5
- Automatic switching between
  - Internet
  - LAN
  - Bluetooth
- Offline message queue
- Smart synchronization after reconnection
- Multi-device support

---

# Security Goals

- End-to-End Encryption (E2EE)
- AES-256-GCM encryption
- X25519 secure key exchange
- Ed25519 digital signatures
- Secure local key storage
- Message integrity verification

---

# Success Metrics

The project will be considered successful if it achieves:

- Offline messaging between nearby devices
- Secure encrypted communication
- Successful Bluetooth device discovery
- File sharing without internet
- LAN messaging between multiple users
- Automatic transition between online and offline communication
- Low message delivery latency
- Stable communication across multiple nearby devices

---

# Assumptions

- Users have Bluetooth and Wi-Fi enabled.
- Devices are within communication range.
- Android devices support Bluetooth Low Energy (BLE).
- Internet is available only for online mode.
- Users grant required permissions for nearby communication.

---

# Constraints

## Technical Constraints

- Bluetooth communication range is limited.
- Voice/video calls require higher bandwidth than Bluetooth.
- Offline communication works only between nearby devices.
- Different Android versions may support different APIs.

## Project Constraints

- Initial release targets Android devices only.
- iOS support is not included in Version 1.
- Large file transfers may require Wi-Fi Direct or LAN.

---

# Branching Strategy

This project follows a feature-branch workflow to keep development organized and maintain a stable main branch.

## Branches

### main
- Contains stable and production-ready code.
- Only tested and reviewed code is merged into this branch.

### feature/*
- Used for developing new features or enhancements.
- Each feature is implemented in its own branch before being merged into `main`.

Examples:
- `feature/backend-setup`
- `feature/flutter-ui`
- `feature/docker-support`
- `feature/authentication`
- `feature/bluetooth-messaging`

## Development Workflow

1. Create a new feature branch from `main`.

```bash
git checkout main
git pull origin main
git checkout -b feature/docker-support
```

2. Develop and test the feature locally.

3. Commit changes with meaningful commit messages.

```bash
git add .
git commit -m "Add Docker support for Spring Boot backend"
```

4. Push the feature branch to GitHub.

```bash
git push -u origin feature/docker-support
```

5. Create a Pull Request (PR) on GitHub.

6. Review and merge the feature branch into `main`.

7. Delete the feature branch after a successful merge.

## Benefits

- Keeps the `main` branch stable.
- Enables parallel development of multiple features.
- Simplifies code reviews using Pull Requests.
- Makes it easier to track feature-specific changes.
- Reduces merge conflicts during development.

# Technology Stack

## Frontend
- Flutter

## Backend
- Java Spring Boot

## Database
- PostgreSQL
- SQLite (Offline Storage)

## Communication

### Online
- REST APIs
- WebSockets

### Offline
- Bluetooth Low Energy (BLE)
- Wi-Fi Direct
- Local Wi-Fi (LAN)

## Security
- AES-256-GCM
- X25519
- Ed25519

---

# Future Enhancements

- Bluetooth Mesh networking
- Cross-platform support (Android + iOS)
- Desktop client
- Cloud backup
- QR-code based device pairing
- Offline media streaming
- Community communication networks

---

# Development Tools

The following tools are required to build, run, and develop the OfflineMesh application locally.

| Tool | Version | Purpose |
|------|---------|---------|
| Java | 21 | Backend development |
| Spring Boot | 4.1.0 | REST API framework |
| Maven | 3.9.16 | Dependency management & build tool |
| Docker | 29.6.2 | Containerization |
| Docker Compose | v5.3.1 | Multi-container orchestration |
| Flutter SDK | Latest Stable | Mobile application development |
| Git | Latest | Version control |
| GitHub | - | Source code hosting |
| Visual Studio Code | Latest | Code editor |
| H2 Database | Latest | Development database |
| PostgreSQL | 17+ (Planned) | Production database |
| Postman | Latest | API testing |

---

# Development Environment

- **Operating System:** Pop!_OS / Ubuntu Linux
- **Backend IDE:** Visual Studio Code
- **Frontend IDE:** Visual Studio Code
- **Java Version:** OpenJDK 21
- **Container Platform:** Docker Desktop / Docker Engine
- **Version Control:** Git & GitHub

---

# Quick Start – Local Development

## Prerequisites

Ensure the following software is installed:

- Java 21
- Maven
- Docker
- Docker Compose
- Git
- Flutter SDK

## Clone the Repository

```bash
git clone https://github.com/<your-username>/OfflineMesh_dev.git
cd OfflineMesh_dev
```

## Build the Backend

```bash
cd backend
./mvnw clean package -DskipTests
```

## Run with Docker Compose

```bash
cd ..
docker compose up --build
```

## Access the Backend

Open your browser and navigate to:

```
http://localhost:8080/api/health
```

Expected response:

```json
{
  "status": "UP",
  "service": "OfflineMesh Backend"
}
```

## Stop the Application

```bash
docker compose down
```

---

## Docker Commands

Build the Docker image manually:

```bash
cd backend
docker build -t offlinemesh-backend .
```

Run the container:

```bash
docker run -p 8080:8080 offlinemesh-backend
```

# Expected Outcome

OfflineMesh aims to provide a reliable, secure, and hybrid communication platform that ensures users remain connected even in environments where traditional internet-based messaging services fail.


