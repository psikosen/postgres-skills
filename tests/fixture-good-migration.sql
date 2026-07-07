-- linter fixture: clean additive migration, zero findings expected
ALTER TABLE users ADD COLUMN IF NOT EXISTS nickname text;
UPDATE users SET nickname = user_name WHERE nickname IS NULL;
