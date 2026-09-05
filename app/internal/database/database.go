package database

import (
	"context"
	"crypto/sha256"
	"embed"
	"errors"
	"fmt"
	"sort"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed migrations/*.sql
var migrationFiles embed.FS

func Open(ctx context.Context, databaseURL string, maxConns, minConns int32) (*pgxpool.Pool, error) {
	poolConfig, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse DATABASE_URL: %w", err)
	}
	poolConfig.MaxConns = maxConns
	poolConfig.MinConns = minConns
	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		return nil, err
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, err
	}
	return pool, nil
}

func Migrate(ctx context.Context, pool *pgxpool.Pool) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(context.WithoutCancel(ctx)) }()
	// Serialize simultaneous migration Jobs, including during local Helm upgrades.
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(74219001)`); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		version TEXT PRIMARY KEY, checksum TEXT NOT NULL, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	)`); err != nil {
		return err
	}
	entries, err := migrationFiles.ReadDir("migrations")
	if err != nil {
		return err
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Name() < entries[j].Name() })
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		migration, err := migrationFiles.ReadFile("migrations/" + entry.Name())
		if err != nil {
			return err
		}
		checksum := fmt.Sprintf("%x", sha256.Sum256(migration))
		var appliedChecksum string
		err = tx.QueryRow(ctx, `SELECT checksum FROM schema_migrations WHERE version = $1`, entry.Name()).Scan(&appliedChecksum)
		if err == nil {
			if appliedChecksum != checksum {
				return fmt.Errorf("migration %s changed after being applied; add a new migration instead", entry.Name())
			}
			continue
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
		if _, err := tx.Exec(ctx, string(migration)); err != nil {
			return fmt.Errorf("apply migration %s: %w", entry.Name(), err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO schema_migrations(version, checksum) VALUES ($1, $2)`, entry.Name(), checksum); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}
