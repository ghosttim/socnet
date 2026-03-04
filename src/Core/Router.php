<?php

namespace Core;

use Core\DatabaseManger;

class Router
{
    private array $routes = [];
    private DbInterface $db;

    public function __construct(DbInterface $db)
    {
        $this->db = $db;
    }

    public function loadRoutes(array $routes): void
    {
        $this->routes = $routes;
    }

    public function dispatch(string $method, string $uri): void
    {
        $path = parse_url($uri, PHP_URL_PATH);
        $queryString = parse_url($uri, PHP_URL_QUERY) ?? '';

        // Парсим query параметры в $_GET
        parse_str($queryString, $_GET);

        foreach ($this->routes as $route) {
            [$routeMethod, $routePath, $handler] = $route;

            if (strtoupper($routeMethod) !== strtoupper($method)) {
                continue;
            }

            // Проверяем совпадение с параметром {id}
            if (str_contains($routePath, '{id}')) {
                $pattern = str_replace('{id}', '(\d+)', $routePath);
                if (preg_match("#^{$pattern}$#", $path, $matches)) {
                    $this->handle($handler, $matches[1]);
                    return;
                }
            }

            // Проверяем точное совпадение
            if ($routePath === $path) {
                $this->handle($handler);
                return;
            }
        }

        http_response_code(404);
        echo json_encode(['error' => 'Not Found']);
    }

    private function handle(array $handler, mixed $param = null): void
    {
        [$className, $methodName] = $handler;

        // Создаем репозиторий
        $repository = new $className($this->db);

        // Вызываем метод
        if ($param !== null) {
            $repository->$methodName($param);
        } else {
            $repository->$methodName();
        }
    }
}