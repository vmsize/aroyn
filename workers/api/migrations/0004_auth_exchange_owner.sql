-- Scope credential revocation and the users foreign-key cascade by account.
CREATE INDEX IF NOT EXISTS idx_auth_exchanges_user_id ON auth_exchanges(user_id);
