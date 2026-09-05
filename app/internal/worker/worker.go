package worker

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"

	"github.com/skhitrov/k8s-platform-lab/app/internal/config"
	"github.com/skhitrov/k8s-platform-lab/app/internal/database"
	"github.com/skhitrov/k8s-platform-lab/app/internal/model"
	"github.com/skhitrov/k8s-platform-lab/app/internal/observability"
)

type JobStore interface {
	Ping(context.Context) error
	ClaimJob(context.Context, time.Duration) (model.Job, error)
	CompleteJob(context.Context, model.Job, string) error
	FailJob(context.Context, model.Job, error) error
	QueueStats(context.Context) (int64, float64, error)
}

func Run(ctx context.Context, cfg config.Config, store JobStore, logger *slog.Logger) error {
	metrics := observability.NewMetrics()
	metrics.RegisterStore(store)
	metricsServer := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           workerHandler(store, metrics),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       5 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       30 * time.Second,
	}
	serverErrors := make(chan error, 1)
	go func() {
		logger.Info("worker metrics listening", "address", cfg.HTTPAddr)
		if err := metricsServer.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
			serverErrors <- err
		}
	}()
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
		defer cancel()
		if err := metricsServer.Shutdown(shutdownCtx); err != nil {
			logger.Error("worker metrics shutdown failed", "error", err)
		}
	}()
	logger.Info("worker started", "poll_interval", cfg.WorkerPollInterval, "lease_duration", cfg.WorkerLeaseDuration)
	for {
		select {
		case err := <-serverErrors:
			return fmt.Errorf("serve worker metrics: %w", err)
		default:
		}
		if err := ctx.Err(); err != nil {
			logger.Info("worker stopped")
			return nil
		}
		depth, oldest, err := store.QueueStats(ctx)
		if err == nil {
			metrics.QueueDepth.Set(float64(depth))
			metrics.QueueOldestAge.Set(oldest)
		}
		job, err := store.ClaimJob(ctx, cfg.WorkerLeaseDuration)
		if errors.Is(err, database.ErrNotFound) {
			if !wait(ctx, cfg.WorkerPollInterval) {
				return nil
			}
			continue
		}
		if err != nil {
			logger.Warn("claim job failed", "error", err)
			if !wait(ctx, cfg.WorkerPollInterval) {
				return nil
			}
			continue
		}

		started := time.Now()
		parent := otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier{"traceparent": job.TraceParent})
		jobCtx, span := otel.Tracer("taskflow/worker").Start(parent, "jobs.process",
			trace.WithSpanKind(trace.SpanKindConsumer),
			trace.WithAttributes(attribute.String("job.id", job.ID), attribute.Int("job.attempt", job.Attempts)))
		result, workErr := PerformWork(jobCtx, job.ID, job.WorkUnits)
		metrics.JobDuration.Observe(time.Since(started).Seconds())
		if workErr != nil {
			metrics.JobsProcessed.WithLabelValues("failed").Inc()
			span.RecordError(workErr)
			span.SetStatus(codes.Error, workErr.Error())
			failureCtx, cancel := context.WithTimeout(context.WithoutCancel(jobCtx), cfg.ShutdownTimeout)
			if failErr := store.FailJob(failureCtx, job, workErr); failErr != nil {
				logger.Error("record job failure failed", "job_id", job.ID, "error", failErr)
			}
			cancel()
			span.End()
			if errors.Is(workErr, context.Canceled) {
				return nil
			}
			continue
		}
		if err := store.CompleteJob(jobCtx, job, result); err != nil {
			logger.Error("complete job failed", "job_id", job.ID, "error", err)
			span.RecordError(err)
			span.SetStatus(codes.Error, err.Error())
			span.End()
			continue
		}
		metrics.JobsProcessed.WithLabelValues("succeeded").Inc()
		logger.Info("job completed", "job_id", job.ID, "trace_id", span.SpanContext().TraceID().String(), "work_units", job.WorkUnits, "attempt", job.Attempts, "duration_ms", time.Since(started).Milliseconds())
		span.End()
	}
}

func workerHandler(store JobStore, metrics *observability.Metrics) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health/live", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("{\"status\":\"alive\"}\n"))
	})
	mux.HandleFunc("GET /health/ready", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := store.Ping(ctx); err != nil {
			http.Error(w, "database unavailable", http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("{\"status\":\"ready\"}\n"))
	})
	mux.Handle("GET /metrics", promhttp.HandlerFor(metrics.Registry, promhttp.HandlerOpts{}))
	return mux
}

func PerformWork(ctx context.Context, id string, workUnits int64) (string, error) {
	if workUnits < 1 {
		return "", fmt.Errorf("work units must be positive")
	}
	digest := sha256.Sum256([]byte(id + ":" + strconv.FormatInt(workUnits, 10)))
	for i := int64(0); i < workUnits; i++ {
		if i%4096 == 0 {
			select {
			case <-ctx.Done():
				return "", ctx.Err()
			default:
			}
		}
		digest = sha256.Sum256(digest[:])
	}
	return hex.EncodeToString(digest[:]), nil
}

func wait(ctx context.Context, duration time.Duration) bool {
	timer := time.NewTimer(duration)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}
