<?php
namespace Core;

class DatabaseManger
{

    public function isUseReplication()
    {
        $config = parse_ini_file(__DIR__ . '/../../.env');
        return filter_var($config['APP_USE_REPLICATION'] ?? 'false', FILTER_VALIDATE_BOOLEAN);
    }


    public function getDatabase()
    {
        if ($this->isUseReplication()) {
            return new \Core\ReplicationDatabase();
        } else {
            return new \Core\Database();
        }
    }
}