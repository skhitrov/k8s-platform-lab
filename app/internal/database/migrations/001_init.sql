CREATE TABLE IF NOT EXISTS jobs (
    id UUID PRIMARY KEY,
    work_units BIGINT NOT NULL CHECK (work_units > 0),
    status TEXT NOT NULL CHECK (status IN ('queued', 'running', 'succeeded', 'failed')),
    result TEXT NOT NULL DEFAULT '',
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 3 CHECK (max_attempts > 0),
    lease_until TIMESTAMPTZ,
    last_error TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS jobs_claim_idx
    ON jobs (status, created_at)
    WHERE status IN ('queued', 'running');

