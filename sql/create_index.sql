CREATE INDEX idx_profiles_covering ON profiles 
    (first_name varchar_pattern_ops, second_name varchar_pattern_ops)
    INCLUDE (birthdate, biography, city, user_id);
