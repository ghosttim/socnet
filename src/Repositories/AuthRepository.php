<?php

namespace Repositories;

use Core\DbInterface;

class AuthRepository
{
    private DbInterface $db;

    public function __construct(DbInterface $db)
    {
        $this->db = $db;
    }

    public function login(): void
    {
        $data = json_decode(file_get_contents('php://input'), true);

        if (empty($data['id']) || empty($data['password'])) {
            http_response_code(400);
            echo json_encode(['error' => 'ID and password required']);
            return;
        }

        $userId = (int)$data['id'];
        $user = $this->findUserById($userId);

        if (!$user || !password_verify($data['password'], $user['password_hash'])) {
            http_response_code(401);
            echo json_encode(['error' => 'Invalid credentials']);
            return;
        }

        // Генерируем токен
        $token = bin2hex(random_bytes(32));

        echo json_encode([
            'token' => $token
        ]);
    }

    private function findUserById(int $id): ?array
    {
        $sql = "SELECT id, password_hash FROM users WHERE id = ?";
        return $this->db->queryOne($sql, [$id]);
    }
}