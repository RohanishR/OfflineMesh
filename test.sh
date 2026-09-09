#!/bin/bash
set -e

run_test() { echo -e "\n=== $1 ==="; }

run_test "4. User registration works"
curl -s -w "\nHTTP: %{http_code}\n" -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "e2e_user", "email": "e2e@example.com", "password": "SecurePassword123"}'

run_test "5. Duplicate users are rejected"
curl -s -w "\nHTTP: %{http_code}\n" -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "e2e_user", "email": "e2e@example.com", "password": "SecurePassword123"}'

run_test "6. Login works & 7. Returns JWT"
LOGIN_RES=$(curl -s -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "e2e_user", "password": "SecurePassword123"}')
echo $LOGIN_RES
TOKEN=$(echo $LOGIN_RES | jq -r .accessToken)
echo "Extracted Token: $TOKEN"

run_test "8. Protected endpoint without token returns 401"
curl -s -w "\nHTTP: %{http_code}\n" -X GET http://localhost:8080/api/auth/me

run_test "9. Protected endpoint with invalid token returns 401"
curl -s -w "\nHTTP: %{http_code}\n" -X GET http://localhost:8080/api/auth/me \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.invalid"

run_test "10. GET /api/auth/me with valid JWT works"
curl -s -w "\nHTTP: %{http_code}\n" -X GET http://localhost:8080/api/auth/me \
  -H "Authorization: Bearer $TOKEN"

