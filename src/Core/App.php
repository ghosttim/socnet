<?php
declare(strict_types=1);

namespace Core;

class App
{
    private Router $router;
    private DbInterface $database;

    public function __construct()
    {
        // Загружаем конфигурацию
        $this->loadEnvironment();

        // Инициализируем компоненты
        $this->initDatabase();
        $this->initRouter();
    }

    /**
     * Загружаем environment
     * @return void
     */
    private function loadEnvironment(): void
    {
        $envFile = __DIR__ . '/../.env';

        if (file_exists($envFile)) {
            $lines = file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

            foreach ($lines as $line) {
                if (str_starts_with(trim($line), '#')) {
                    continue;
                }

                [$name, $value] = explode('=', $line, 2);
                $name = trim($name);
                $value = trim($value, " \t\n\r\0\x0B\"'");

                putenv("{$name}={$value}");
                $_ENV[$name] = $value;
            }
        }
    }

    /**
     * Инициализация DB
     * @return void
     */
    private function initDatabase(): void
    {
        $dbManager = new \Core\DatabaseManger();
        $this->database = $dbManager->getDatabase();
    }

    /**
     * Инициализация роутеров
     * @return void
     */
    private function initRouter(): void
    {
        $this->router = new Router($this->database);
    }

}