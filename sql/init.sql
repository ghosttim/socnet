-- Создаем таблицу пользователей
CREATE TABLE IF NOT EXISTS users (
                                     id SERIAL PRIMARY KEY,
                                     password_hash VARCHAR(255) NOT NULL,
                                     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Создаем таблицу профилей
CREATE TABLE IF NOT EXISTS profiles (
                                        id SERIAL PRIMARY KEY,
                                        user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
                                        first_name VARCHAR(100) NOT NULL,
                                        second_name VARCHAR(100) NOT NULL,
                                        birthdate DATE NOT NULL,
                                        biography TEXT,
                                        city VARCHAR(100),
                                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);