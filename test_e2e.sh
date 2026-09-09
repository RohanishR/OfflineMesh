#!/bin/bash

# Exit on any error
set -e

BASE_URL="http://localhost:8080/api"

echo "=== 3. Verify /api/health ==="
curl -s -X GET "$BASE_URL/health"
echo -e "\n"

echo "=== A. Register User A ==="
RES_A=$(curl -s -X POST "$BASE_URL/auth/register" -H "Content-Type: application/json" -d '{"username":"usera", "password":"password123", "email":"usera@example.com"}')
echo "$RES_A"
ID_A=$(echo "$RES_A" | grep -o '"offlineMeshId":"[^"]*' | cut -d'"' -f4)

echo -e "\n=== B. Register User B ==="
RES_B=$(curl -s -X POST "$BASE_URL/auth/register" -H "Content-Type: application/json" -d '{"username":"userb", "password":"password123", "email":"userb@example.com"}')
echo "$RES_B"
ID_B=$(echo "$RES_B" | grep -o '"offlineMeshId":"[^"]*' | cut -d'"' -f4)

echo -e "\n=== C. Login User A ==="
LOGIN_A=$(curl -s -X POST "$BASE_URL/auth/login" -H "Content-Type: application/json" -d '{"username":"usera", "password":"password123"}')
echo "$LOGIN_A"
JWT_A=$(echo "$LOGIN_A" | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)

echo -e "\n=== D. Login User B ==="
LOGIN_B=$(curl -s -X POST "$BASE_URL/auth/login" -H "Content-Type: application/json" -d '{"username":"userb", "password":"password123"}')
echo "$LOGIN_B"
JWT_B=$(echo "$LOGIN_B" | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)

echo -e "\n=== E. Get User A Profile ==="
curl -s -X GET "$BASE_URL/users/me/profile" -H "Authorization: Bearer $JWT_A"
echo -e "\n"

echo "=== F. Look up User B using OfflineMesh ID ==="
curl -s -X GET "$BASE_URL/users/$ID_B" -H "Authorization: Bearer $JWT_A"
echo -e "\n"

echo "=== G. Connect User A and User B ==="
curl -s -X POST "$BASE_URL/friends/connect" -H "Authorization: Bearer $JWT_A" -H "Content-Type: application/json" -d "{\"offlineMeshId\":\"$ID_B\"}"
echo -e "\n"

echo "=== H. List User A friends ==="
curl -s -X GET "$BASE_URL/friends" -H "Authorization: Bearer $JWT_A"
echo -e "\n"

echo "=== I. Send message from A to B ==="
curl -s -X POST "$BASE_URL/messages/$ID_B" -H "Authorization: Bearer $JWT_A" -H "Content-Type: application/json" -d '{"content":"Hello B!"}'
echo -e "\n"

echo "=== J. Retrieve conversation from A ==="
curl -s -X GET "$BASE_URL/messages/$ID_B" -H "Authorization: Bearer $JWT_A"
echo -e "\n"

echo "=== K. Retrieve conversation from B ==="
curl -s -X GET "$BASE_URL/messages/$ID_A" -H "Authorization: Bearer $JWT_B"
echo -e "\n"

echo "=== L. Remove friendship ==="
curl -s -X DELETE "$BASE_URL/friends/$ID_B" -H "Authorization: Bearer $JWT_A"
echo -e "\n"

echo "=== M. Verify messaging restrictions behave correctly (A tries to send message) ==="
curl -s -X POST "$BASE_URL/messages/$ID_B" -H "Authorization: Bearer $JWT_A" -H "Content-Type: application/json" -d '{"content":"Are you still there?"}'
echo -e "\n"

echo "=== Verify existing conversation records still exist (A viewing history with B) ==="
curl -s -X GET "$BASE_URL/messages/$ID_B" -H "Authorization: Bearer $JWT_A"
echo -e "\n"

echo "=== Verify protected endpoints return 401 without JWT ==="
curl -s -I -X GET "$BASE_URL/users/me/profile"
echo -e "\n"

echo "All tests completed!"
