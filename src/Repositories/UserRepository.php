<?php

namespace Repositories;

use Core\Database;

class UserRepository
{
    private Database $db;

    public function __construct(Database $db)
    {
        $this->db = $db;
    }

    public function register(): void
    {
        $data = json_decode(file_get_contents('php://input'), true);

        // Если в запросе есть id, проверяем что он не существует
        if (!empty($data['id'])) {
            $userId = (int)$data['id'];
            if ($this->userExists($userId)) {
                http_response_code(400);
                echo json_encode(['error' => 'User with this ID already exists']);
                return;
            }
        }

        $required = ['first_name', 'second_name', 'birthdate', 'city', 'password'];
        foreach ($required as $field) {
            if (empty($data[$field])) {
                http_response_code(400);
                echo json_encode(['error' => "Field '{$field}' is required"]);
                return;
            }
        }

        // Валидация даты
        if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $data['birthdate'])) {
            http_response_code(400);
            echo json_encode(['error' => 'Invalid birthdate format. Use YYYY-MM-DD']);
            return;
        }

        $this->db->beginTransaction();

        try {
            // Создаем пользователя
            $userId = $this->createUser(
                password_hash($data['password'], PASSWORD_BCRYPT)
            );

            // Создаем профиль
            $this->createProfile(
                $userId,
                $data['first_name'],
                $data['second_name'],
                $data['birthdate'],
                $data['biography'] ?? null,
                $data['city']
            );

            $this->db->commit();

            echo json_encode([
                'user_id' => (string)$userId
            ]);

        } catch (\Exception $e) {
            $this->db->rollBack();
            http_response_code(500);
            echo json_encode(['error' => 'Registration failed: ' . $e->getMessage()]);
        }
    }

    private function userExists(int $id): bool
    {
        $sql = "SELECT 1 FROM users WHERE id = ? LIMIT 1";
        return $this->db->exists($sql, [$id]);
    }

    public function getById(string $id): void
    {
        $userId = (int)$id;

        $user = $this->getUserForApi($userId);

        if (!$user) {
            http_response_code(404);
            echo json_encode(['error' => 'User not found']);
            return;
        }

        echo json_encode([
            'id' => (string)$user['user_id'],
            'first_name' => $user['first_name'],
            'second_name' => $user['second_name'],
            'birthdate' => $user['birthdate'],
            'biography' => $user['biography'] ?? '',
            'city' => $user['city'] ?? ''
        ]);
    }

    private function createUser(string $passwordHash): int
    {
        $sql = "INSERT INTO users (password_hash) VALUES (?) RETURNING id";

        // Выполняем запрос и получаем результат
        $stmt = $this->db->query($sql, [$passwordHash]);
        $result = $stmt->fetch();

        return (int)$result['id'];
    }

    private function createProfile(
        int $userId,
        string $firstName,
        string $secondName,
        string $birthdate,
        ?string $biography,
        string $city
    ): void {
        $sql = "INSERT INTO profiles 
                (user_id, first_name, second_name, birthdate, biography, city) 
                VALUES (?, ?, ?, ?, ?, ?)";

        $this->db->execute($sql, [
            $userId, $firstName, $secondName, $birthdate, $biography, $city
        ]);
    }

    private function getUserForApi(int $userId): ?array
    {
        $sql = "SELECT 
                user_id,
                first_name,
                second_name,
                birthdate,
                biography,
                city
            FROM profiles
            WHERE user_id = ?";

        return $this->db->queryOne($sql, [$userId]);
    }

    public function search(): void
    {
        // Получаем query параметры
        $firstName = $_GET['first_name'] ?? '';
        $lastName = $_GET['second_name'] ?? '';

        // Валидация
        if (empty($firstName) || empty($lastName)) {
            http_response_code(400);
            echo json_encode(['error' => 'Both first_name and second_name parameters are required']);
            return;
        }

        // Преобразуем префиксы для LIKE запроса
        $firstNamePattern = $firstName . '%';
        $lastNamePattern = $lastName . '%';

        try {
            // Ищем анкеты по префиксам имени и фамилии
            $profiles = $this->searchProfiles($firstNamePattern, $lastNamePattern);

            // Форматируем ответ по спецификации
            $response = array_map(function($profile) {
                return [
                    'id' => (string)$profile['user_id'],
                    'first_name' => $profile['first_name'],
                    'second_name' => $profile['second_name'],
                    'birthdate' => $profile['birthdate'],
                    'biography' => $profile['biography'] ?? '',
                    'city' => $profile['city'] ?? ''
                ];
            }, $profiles);

            echo json_encode($response);

        } catch (\Exception $e) {
            http_response_code(500);
            echo json_encode(['error' => 'Search failed: ' . $e->getMessage()]);
        }
    }

    private function searchProfiles(string $firstNamePattern, string $lastNamePattern): array
    {
        $sql = "SELECT 
                user_id,
                first_name,
                second_name,
                birthdate,
                biography,
                city
            FROM profiles
            WHERE first_name LIKE ? 
              AND second_name LIKE ?
              ORDER BY user_id ASC";

        return $this->db->fetchAll($sql, [$firstNamePattern, $lastNamePattern]);
    }
}