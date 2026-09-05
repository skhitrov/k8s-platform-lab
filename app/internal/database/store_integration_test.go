package database

import (
	"context"
	"errors"
	"net/url"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/skhitrov/k8s-platform-lab/app/internal/model"
)

func TestConcurrentClaimIsExclusive(t *testing.T) {
	store, pool := integrationStore(t)
	ctx := context.Background()
	created, err := store.CreateJob(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	_ = pool

	var wg sync.WaitGroup
	claimed := make(chan string, 16)
	for i := 0; i < 16; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			job, claimErr := store.ClaimJob(ctx, time.Minute)
			if claimErr == nil {
				claimed <- job.ID
			} else if !errors.Is(claimErr, ErrNotFound) {
				t.Errorf("claim failed: %v", claimErr)
			}
		}()
	}
	wg.Wait()
	close(claimed)
	var ids []string
	for id := range claimed {
		ids = append(ids, id)
	}
	if len(ids) != 1 || ids[0] != created.ID {
		t.Fatalf("claimed IDs = %v, want exactly [%s]", ids, created.ID)
	}
}

func integrationStore(t *testing.T) (*Store, *pgxpool.Pool) {
	t.Helper()
	databaseURL := os.Getenv("TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	parsed, err := url.Parse(databaseURL)
	if err != nil || parsed.Path != "/taskflow_test" {
		t.Fatal("integration tests require the dedicated taskflow_test database")
	}
	ctx := context.Background()
	pool, err := Open(ctx, databaseURL, 10, 1)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	if err := Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, "TRUNCATE jobs"); err != nil {
		t.Fatal(err)
	}
	return NewStore(pool), pool
}

func TestExpiredLeaseFencesStaleWorker(t *testing.T) {
	store, pool := integrationStore(t)
	ctx := context.Background()
	if _, err := store.CreateJob(ctx, 10); err != nil {
		t.Fatal(err)
	}
	first, err := store.ClaimJob(ctx, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `UPDATE jobs SET lease_until = NOW() - INTERVAL '1 second' WHERE id = $1`, first.ID); err != nil {
		t.Fatal(err)
	}
	second, err := store.ClaimJob(ctx, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if second.ID != first.ID || second.Attempts != 2 {
		t.Fatalf("reclaimed job = %+v", second)
	}
	if err := store.CompleteJob(ctx, first, "stale"); !errors.Is(err, ErrLeaseLost) {
		t.Fatalf("stale completion: %v", err)
	}
	if err := store.FailJob(ctx, first, errors.New("stale failure")); !errors.Is(err, ErrLeaseLost) {
		t.Fatalf("stale failure: %v", err)
	}
	if err := store.CompleteJob(ctx, second, "current"); err != nil {
		t.Fatal(err)
	}
	if err := store.CompleteJob(ctx, second, "duplicate"); !errors.Is(err, ErrLeaseLost) {
		t.Fatalf("duplicate completion: %v", err)
	}
	got, err := store.GetJob(ctx, first.ID)
	if err != nil || got.Status != model.JobSucceeded || got.Result != "current" {
		t.Fatalf("persisted job = %+v, err=%v", got, err)
	}
}

func TestRetriesAreBounded(t *testing.T) {
	store, _ := integrationStore(t)
	ctx := context.Background()
	created, err := store.CreateJob(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	for attempt := 1; attempt <= 3; attempt++ {
		job, err := store.ClaimJob(ctx, time.Minute)
		if err != nil || job.Attempts != attempt {
			t.Fatalf("attempt %d: %+v, %v", attempt, job, err)
		}
		if err := store.FailJob(ctx, job, errors.New("injected failure")); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := store.ClaimJob(ctx, time.Minute); !errors.Is(err, ErrNotFound) {
		t.Fatalf("claim after exhaustion: %v", err)
	}
	got, err := store.GetJob(ctx, created.ID)
	if err != nil || got.Status != model.JobFailed || got.CompletedAt == nil {
		t.Fatalf("exhausted job = %+v, err=%v", got, err)
	}
}

func TestCrashOnFinalAttemptBecomesFailed(t *testing.T) {
	store, pool := integrationStore(t)
	ctx := context.Background()
	created, err := store.CreateJob(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `UPDATE jobs SET max_attempts = 1 WHERE id = $1`, created.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := store.ClaimJob(ctx, time.Minute); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `UPDATE jobs SET lease_until = NOW() - INTERVAL '1 second' WHERE id = $1`, created.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := store.ClaimJob(ctx, time.Minute); !errors.Is(err, ErrNotFound) {
		t.Fatalf("claim: %v", err)
	}
	got, err := store.GetJob(ctx, created.ID)
	if err != nil || got.Status != model.JobFailed || got.CompletedAt == nil {
		t.Fatalf("crashed job = %+v, err=%v", got, err)
	}
}

func TestQueuedWorkSurvivesConnectionReset(t *testing.T) {
	store, pool := integrationStore(t)
	ctx := context.Background()
	created, err := store.CreateJob(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	pool.Reset()
	job, err := store.ClaimJob(ctx, time.Minute)
	if err != nil || job.ID != created.ID {
		t.Fatalf("reconnect claim: %+v, %v", job, err)
	}
	if err := store.CompleteJob(ctx, job, "restored"); err != nil {
		t.Fatal(err)
	}
}

func TestMigrationsCanRunAgain(t *testing.T) {
	_, pool := integrationStore(t)
	if err := Migrate(context.Background(), pool); err != nil {
		t.Fatal(err)
	}
	var count int
	if err := pool.QueryRow(context.Background(), `SELECT count(*) FROM schema_migrations`).Scan(&count); err != nil || count != 2 {
		t.Fatalf("migration count = %d, err=%v", count, err)
	}
}
