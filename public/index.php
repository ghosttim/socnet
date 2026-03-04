<?php

require_once __DIR__ . '/../vendor/autoload.php';

use Core\DatabaseManger;
use Core\Router;

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

$routes = require_once __DIR__ . '/../routes.php';

$db = (new DatabaseManger())->getDatabase();
$router = new Router($db);

$router->loadRoutes($routes);

try {
    $router->dispatch($_SERVER['REQUEST_METHOD'], $_SERVER['REQUEST_URI']);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Server error: ' . $e->getMessage()]);
}