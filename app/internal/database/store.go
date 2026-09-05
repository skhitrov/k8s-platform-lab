package database

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/prometheus/client_golang/prometheus"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"

	"github.com/skhitrov/k8s-platform-lab/app/internal/model"
)

var ErrNotFound = errors.New("job not found")
var ErrLeaseLost = errors.New("job lease is no longer owned by this attempt")

type Store struct {
	pool *pgxpool.Pool
}

func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{pool: pool}
}

func (s *Store) Ping(ctx context.Context) error {
	var ready bool
	if err := s.pool.QueryRow(ctx, `SELECT to_regclass('public.jobs') IS NOT NULL`).Scan(&ready); err != nil {
		return err
	}
	if !ready {
		return errors.New("database schema has not been migrated")
	}
	return nil
}

func (s *Store) CreateJob(ctx context.Context, workUnits int64) (model.Job, error) {
	ctx, span := otel.Tracer("taskflow/database").Start(ctx, "jobs.insert")
	defer span.End()
	carrier := propagation.MapCarrier{}
	otel.GetTextMapPropagator().Inject(ctx, carrier)
	job := model.Job{
		ID:          uuid.NewString(),
		WorkUnits:   workUnits,
		Status:      model.JobQueued,
		MaxAttempts: 3,
		TraceParent: carrier.Get("traceparent"),
	}
	row := s.pool.QueryRow(ctx, `
		INSERT INTO jobs (id, work_units, status, max_attempts, trace_parent)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING attempts, created_at, updated_at`,
		job.ID, job.WorkUnits, job.Status, job.MaxAttempts, job.TraceParent,
	)
	if err := row.Scan(&job.Attempts, &job.CreatedAt, &job.UpdatedAt); err != nil {
		return model.Job{}, err
	}
	return job, nil
}

func (s *Store) GetJob(ctx context.Context, id string) (model.Job, error) {
	job := model.Job{ID: id}
	err := s.pool.QueryRow(ctx, `
		SELECT work_units, status, result, attempts, max_attempts, last_error,
		       created_at, updated_at, started_at, completed_at, lease_until
		FROM jobs WHERE id = $1`, id).Scan(
		&job.WorkUnits, &job.Status, &job.Result, &job.Attempts, &job.MaxAttempts,
		&job.LastError, &job.CreatedAt, &job.UpdatedAt, &job.StartedAt,
		&job.CompletedAt, &job.LeaseUntil,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return model.Job{}, ErrNotFound
	}
	return job, err
}

func (s *Store) ClaimJob(ctx context.Context, leaseDuration time.Duration) (model.Job, error) {
	// A crash on the final attempt must reach a terminal state after lease expiry.
	if _, err := s.pool.Exec(ctx, `
		UPDATE jobs SET status = 'failed', lease_until = NULL,
		    completed_at = NOW(), updated_at = NOW(), last_error = 'final attempt lease expired'
		WHERE status = 'running' AND lease_until < NOW() AND attempts >= max_attempts`); err != nil {
		return model.Job{}, err
	}
	job := model.Job{}
	leaseSeconds := int64(leaseDuration.Seconds())
	if leaseSeconds < 1 {
		leaseSeconds = 1
	}
	err := s.pool.QueryRow(ctx, `
		WITH candidate AS (
			SELECT id
			FROM jobs
			WHERE attempts < max_attempts
			  AND (status = 'queued' OR (status = 'running' AND lease_until < NOW()))
			ORDER BY created_at
			FOR UPDATE SKIP LOCKED
			LIMIT 1
		)
		UPDATE jobs AS j
		SET status = 'running',
		    attempts = j.attempts + 1,
		    lease_until = NOW() + make_interval(secs => $1),
		    started_at = COALESCE(j.started_at, NOW()),
		    updated_at = NOW(),
		    last_error = ''
		FROM candidate
		WHERE j.id = candidate.id
		RETURNING j.id, j.work_units, j.status, j.result, j.attempts,
		          j.max_attempts, j.last_error, j.created_at, j.updated_at,
		          j.started_at, j.completed_at, j.lease_until, j.trace_parent`, leaseSeconds).Scan(
		&job.ID, &job.WorkUnits, &job.Status, &job.Result, &job.Attempts,
		&job.MaxAttempts, &job.LastError, &job.CreatedAt, &job.UpdatedAt,
		&job.StartedAt, &job.CompletedAt, &job.LeaseUntil, &job.TraceParent,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return model.Job{}, ErrNotFound
	}
	return job, err
}

func (s *Store) CompleteJob(ctx context.Context, job model.Job, result string) error {
	commandTag, err := s.pool.Exec(ctx, `
		UPDATE jobs
		SET status = 'succeeded', result = $2, lease_until = NULL,
		    completed_at = NOW(), updated_at = NOW(), last_error = ''
		WHERE id = $1 AND status = 'running' AND attempts = $3 AND lease_until > NOW()`, job.ID, result, job.Attempts)
	if err != nil {
		return err
	}
	if commandTag.RowsAffected() != 1 {
		return fmt.Errorf("complete job %s: %w", job.ID, ErrLeaseLost)
	}
	return nil
}

func (s *Store) FailJob(ctx context.Context, job model.Job, cause error) error {
	nextStatus := model.JobQueued
	if job.Attempts >= job.MaxAttempts {
		nextStatus = model.JobFailed
	}
	commandTag, err := s.pool.Exec(ctx, `
		UPDATE jobs
		SET status = $2, last_error = $3, lease_until = NULL,
		    completed_at = CASE WHEN $2 = 'failed' THEN NOW() ELSE NULL END,
		    updated_at = NOW()
		WHERE id = $1 AND status = 'running' AND attempts = $4 AND lease_until > NOW()`, job.ID, nextStatus, cause.Error(), job.Attempts)
	if err != nil {
		return err
	}
	if commandTag.RowsAffected() != 1 {
		return fmt.Errorf("fail job %s: %w", job.ID, ErrLeaseLost)
	}
	return nil
}

func (s *Store) QueueDepth(ctx context.Context) (int64, error) {
	var count int64
	err := s.pool.QueryRow(ctx, `SELECT COUNT(*) FROM jobs WHERE status = 'queued'`).Scan(&count)
	return count, err
}

func (s *Store) QueueStats(ctx context.Context) (int64, float64, error) {
	var depth int64
	var oldest float64
	err := s.pool.QueryRow(ctx, `
		SELECT COUNT(*), COALESCE(EXTRACT(EPOCH FROM NOW() - MIN(created_at)), 0)
		FROM jobs WHERE status = 'queued'`).Scan(&depth, &oldest)
	return depth, oldest, err
}

func (s *Store) RegisterMetrics(registry prometheus.Registerer) {
	registry.MustRegister(
		prometheus.NewGaugeFunc(prometheus.GaugeOpts{Name: "taskflow_db_pool_acquired_connections", Help: "Connections currently acquired from this process pool."}, func() float64 { return float64(s.pool.Stat().AcquiredConns()) }),
		prometheus.NewGaugeFunc(prometheus.GaugeOpts{Name: "taskflow_db_pool_max_connections", Help: "Configured maximum connections in this process pool."}, func() float64 { return float64(s.pool.Stat().MaxConns()) }),
		prometheus.NewCounterFunc(prometheus.CounterOpts{Name: "taskflow_db_pool_acquire_duration_seconds_total", Help: "Cumulative time spent acquiring database connections."}, func() float64 { return s.pool.Stat().AcquireDuration().Seconds() }),
	)
}
