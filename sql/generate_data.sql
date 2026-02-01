\timing on

TRUNCATE TABLE profiles CASCADE;
TRUNCATE TABLE users RESTART IDENTITY CASCADE;

-- 1. Генерация пользователей
INSERT INTO users (password_hash, created_at)
SELECT
    '$2y$10$' || substr(md5(random()::text), 1, 53),
    CURRENT_TIMESTAMP - (random() * interval '3650 days')
FROM generate_series(1, 1000000);

\echo Пользователи созданы. Генерируем профили...

-- 2. Генерация профилей
INSERT INTO profiles (user_id, first_name, second_name, birthdate, city, created_at)
SELECT
    u.id,
    CASE (u.id % 2)
        WHEN 0 THEN (ARRAY['Иван','Петр','Сергей','Алексей','Дмитрий'])[1 + (u.id % 5)]
        ELSE (ARRAY['Анна','Мария','Елена','Ольга','Татьяна'])[1 + (u.id % 5)]
        END,
    CASE (u.id % 2)
        WHEN 0 THEN (ARRAY['Иванов','Петров','Сидоров','Смирнов','Кузнецов'])[1 + (u.id % 5)]
        ELSE (ARRAY['Иванова','Петрова','Сидорова','Смирнова','Кузнецова'])[1 + (u.id % 5)]
        END,
    DATE '1980-01-01' + ((u.id % 10000) * interval '1 day'),
    (ARRAY['Москва','СПб','Казань','Новосибирск','Екатеринбург'])[1 + (u.id % 5)],
    u.created_at + interval '1 day'
FROM users u;

\timing off

SELECT 'Готово! Записей:' as info, COUNT(*) as count FROM users;