<?php
namespace Core;

class ReplicationDatabase implements DbInterface
{
    private \PDO $masterPdo;
    private array $slavePdos = [];
    private ?\PDO $currentPdo = null;
    private bool $inTransaction = false;
    private bool $isReadOnly = false;

    public function __construct()
    {
        $config = parse_ini_file(__DIR__ . '/../../.env');

        // Подключаемся к master
        $this->masterPdo = $this->createConnection(
            $config['DB_MASTER_HOST'] ?? 'db',
            $config['DB_NAME'] ?? 'social_network',
            $config['DB_USER'] ?? 'postgres',
            $config['DB_PASSWORD'] ?? 'password123'
        );

        // Подключаемся ко всем slave
        $slaveHosts = explode(',', $config['DB_SLAVE_HOSTS'] ?? '');
        foreach ($slaveHosts as $host) {
            $host = trim($host);
            if (!empty($host)) {
                try {
                    $this->slavePdos[] = $this->createConnection(
                        $host,
                        $config['DB_NAME'] ?? 'social_network',
                        $config['DB_USER'] ?? 'postgres',
                        $config['DB_PASSWORD'] ?? 'password123'
                    );
                    error_log("[DB] SUCCESS: Connected to slave {$host}");
                } catch (\Exception $e) {
                    // Логируем ошибку подключения к slave
                    error_log("Failed to connect to slave {$host}: " . $e->getMessage());
                }
            }
        }

        error_log("[DB] Total slaves connected: " . count($this->slavePdos));

        // По умолчанию используем master
        $this->currentPdo = $this->masterPdo;
    }

    private function createConnection(string $host, string $dbname, string $user, string $password): \PDO
    {
        $dsn = "pgsql:host={$host};dbname={$dbname}";

        error_log("[DB] Creating connection to {$host} with DSN: {$dsn}");

        return new \PDO($dsn, $user, $password, [
            \PDO::ATTR_ERRMODE => \PDO::ERRMODE_EXCEPTION,
            \PDO::ATTR_DEFAULT_FETCH_MODE => \PDO::FETCH_ASSOC,
            \PDO::ATTR_PERSISTENT => false
        ]);
    }

    /**
     * Выбирает slave для read-запроса (round-robin)
     */
    private function getSlaveConnection(): \PDO
    {
        if (empty($this->slavePdos)) {
            // Если нет доступных slave, используем master
            return $this->masterPdo;
        }

        // Простой round-robin балансировщик
        static $slaveIndex = 0;
        $selectedSlave = $this->slavePdos[$slaveIndex % count($this->slavePdos)];
        $slaveIndex++;

        return $selectedSlave;
    }

    /**
     * Устанавливает режим только для чтения
     */
    public function setReadOnly(bool $readOnly = true): void
    {
        if ($this->inTransaction) {
            throw new \RuntimeException('Cannot change read-only mode inside transaction');
        }

        $this->isReadOnly = $readOnly;
        $this->currentPdo = $readOnly ? $this->getSlaveConnection() : $this->masterPdo;
    }

    public function queryOne(string $sql, array $params = []): ?array
    {
        // Автоматически определяем тип запроса
        $this->autoDetectQueryType($sql);

        $stmt = $this->currentPdo->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetch() ?: null;
    }

    public function execute(string $sql, array $params = []): void
    {
        // Запись всегда идет на master
        $this->currentPdo = $this->masterPdo;

        $stmt = $this->currentPdo->prepare($sql);
        $stmt->execute($params);
    }

    public function exists(string $sql, array $params = []): bool
    {
        $this->autoDetectQueryType($sql);

        $stmt = $this->currentPdo->prepare($sql);
        $stmt->execute($params);
        return (bool)$stmt->fetchColumn();
    }

    public function beginTransaction(bool $readOnly = false): void
    {
        if ($readOnly) {
            $this->currentPdo = $this->getSlaveConnection();
        } else {
            $this->currentPdo = $this->masterPdo;
        }

        $this->currentPdo->beginTransaction();
        $this->inTransaction = true;
        $this->isReadOnly = $readOnly;
    }

    public function commit(): void
    {
        $this->currentPdo->commit();
        $this->inTransaction = false;
        $this->isReadOnly = false;
        $this->currentPdo = $this->masterPdo;
    }

    public function rollBack(): void
    {
        $this->currentPdo->rollBack();
        $this->inTransaction = false;
        $this->isReadOnly = false;
        $this->currentPdo = $this->masterPdo;
    }

    public function query(string $sql, array $params = []): \PDOStatement
    {
        $this->autoDetectQueryType($sql);

        $stmt = $this->currentPdo->prepare($sql);
        $stmt->execute($params);
        return $stmt;
    }

    public function fetchAll(string $sql, array $params = []): array
    {
        $this->autoDetectQueryType($sql);

        $stmt = $this->query($sql, $params);
        return $stmt->fetchAll(\PDO::FETCH_ASSOC);
    }

    /**
     * Автоматически определяет тип запроса по SQL
     */
    private function autoDetectQueryType(string $sql): void
    {
        if ($this->inTransaction) {
            error_log("[DB] 🔄 IN TRANSACTION - keeping connection: " .
                ($this->currentPdo === $this->masterPdo ? 'MASTER' : 'SLAVE'));
            return;
        }

        $originalSql = $sql;
        $sql = strtoupper(trim($sql));

        $isSelect = str_starts_with($sql, 'SELECT');
        $hasForUpdate = str_contains($sql, ' FOR UPDATE');
        $hasForShare = str_contains($sql, ' FOR SHARE');

        if ($isSelect && !$hasForUpdate && !$hasForShare) {
            $oldConnection = $this->currentPdo === $this->masterPdo ? 'MASTER' : 'SLAVE';
            $this->currentPdo = $this->getSlaveConnection();
            error_log("[DB] 📖 READ  → SLAVE  | Was: {$oldConnection} | SQL: " . substr($originalSql, 0, 100));
        } else {
            $oldConnection = $this->currentPdo === $this->masterPdo ? 'MASTER' : 'SLAVE';
            $this->currentPdo = $this->masterPdo;
            $type = $isSelect ? 'SELECT FOR UPDATE' : 'WRITE';
            error_log("[DB] ✍️ {$type} → MASTER | Was: {$oldConnection} | SQL: " . substr($originalSql, 0, 100));
        }

        error_log("[DB] 📖 READ  → SLAVE  | Host: " . $this->getCurrentHost() . " | SQL: ...");
    }

    public function getCurrentHost(): string
    {
        try {
            $stmt = $this->currentPdo->query("SELECT inet_server_addr() as host, current_database() as db, version() as ver");
            $result = $stmt->fetch();

            if ($result && isset($result['host'])) {
                $host = $result['host'];
                // Определяем, master это или slave
                if ($host === '172.22.0.2') { // IP вашего master
                    return "MASTER ({$host})";
                } else {
                    return "SLAVE ({$host})";
                }
            }
        } catch (\Exception $e) {
            return "UNKNOWN: " . $e->getMessage();
        }

        return "UNKNOWN";
    }

    /**
     * Получает статистику использования подключений
     */
    public function getStats(): array
    {
        return [
            'master_connected' => $this->masterPdo !== null,
            'slaves_connected' => count($this->slavePdos),
            'current_connection' => $this->currentPdo === $this->masterPdo ? 'master' : 'slave',
            'in_transaction' => $this->inTransaction,
            'is_readonly' => $this->isReadOnly
        ];
    }
}