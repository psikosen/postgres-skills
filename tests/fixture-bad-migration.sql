-- test migration with several hazards
DELETE FROM users;
UPDATE launches SET status = 'active';
CREATE INDEX CONCURRENTLY idx_x ON users (email);
ALTER TABLE users ADD COLUMN nickname text NOT NULL;
ALTER TABLE t ADD CONSTRAINT chk CHECK (kind IN ('a','b'));
