DROP TRIGGER IF EXISTS update_user_storage_updated_at ON user_storage;
DROP TRIGGER IF EXISTS update_notes_updated_at ON notes;
DROP TRIGGER IF EXISTS update_categories_updated_at ON categories;
DROP TRIGGER IF EXISTS update_users_updated_at ON users;

DROP FUNCTION IF EXISTS update_updated_at_column();

DROP TABLE IF EXISTS system_configs;
DROP TABLE IF EXISTS user_storage;
DROP TABLE IF EXISTS note_visits;
DROP TABLE IF EXISTS share_links;
DROP TABLE IF EXISTS attachments;
DROP TABLE IF EXISTS note_tags;
DROP TABLE IF EXISTS notes;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS users;
    