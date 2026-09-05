package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"github.com/google/uuid"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel/trace"

	"github.com/skhitrov/k8s-platform-lab/app/internal/config"
	"github.com/skhitrov/k8s-platform-lab/app/internal/database"
	"github.com/skhitrov/k8s-platform-lab/app/internal/model"
	"github.com/skhitrov/k8s-platform-lab/app/internal/observability"
)

type JobStore interface {
	Ping(context.Context) error
	CreateJob(context.Context, int64) (model.Job, error)
	GetJob(context.Context, string) (model.Job, error)
}

type BuildInfo struct {
	Version string `json:"version"`
	Commit  string `json:"commit"`
	Date    string `json:"built_at"`
}

type Server struct {
	cfg       config.Config
	store     JobStore
	logger    *slog.Logger
	metrics   *observability.Metrics
	buildInfo BuildInfo
	faultSeq  atomic.Uint64
	ready     atomic.Bool
}

func NewServer(cfg config.Config, store JobStore, logger *slog.Logger, buildInfo BuildInfo) *Server {
	server := &Server{
		cfg:       cfg,
		store:     store,
		logger:    logger,
		metrics:   observability.NewMetrics(),
		buildInfo: buildInfo,
	}
	server.ready.Store(true)
	server.metrics.RegisterStore(store)
	return server
}

func Run(ctx context.Context, cfg config.Config, store JobStore, logger *slog.Logger, buildInfo BuildInfo) error {
	server := NewServer(cfg, store, logger, buildInfo)
	httpServer := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           server.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errorChannel := make(chan error, 1)
	go func() {
		logger.Info("api listening", "address", cfg.HTTPAddr, "version", buildInfo.Version)
		if err := httpServer.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
			errorChannel <- err
		}
	}()

	select {
	case <-ctx.Done():
		server.ready.Store(false)
		shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
		defer cancel()
		return httpServer.Shutdown(shutdownCtx)
	case err := <-errorChannel:
		return err
	}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health/live", s.live)
	mux.HandleFunc("GET /health/ready", s.readiness)
	mux.HandleFunc("GET /version", s.version)
	mux.Handle("GET /metrics", promhttp.HandlerFor(s.metrics.Registry, promhttp.HandlerOpts{}))
	mux.HandleFunc("POST /v1/jobs", s.createJob)
	mux.HandleFunc("GET /v1/jobs/{id}", s.getJob)

	return otelhttp.NewHandler(s.accessLogAndMetrics(mux), "taskflow-http")
}

func (s *Server) live(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "alive"})
}

func (s *Server) readiness(w http.ResponseWriter, r *http.Request) {
	if !s.ready.Load() {
		writeError(w, http.StatusServiceUnavailable, "server is shutting down")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), s.cfg.ReadinessTimeout)
	defer cancel()
	if err := s.store.Ping(ctx); err != nil {
		s.logger.Warn("readiness database check failed", "error", err)
		writeError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (s *Server) version(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.buildInfo)
}

func (s *Server) createJob(w http.ResponseWriter, r *http.Request) {
	if s.shouldInjectError() {
		writeError(w, http.StatusInternalServerError, "injected canary failure")
		return
	}
	if s.cfg.FaultLatency > 0 {
		timer := time.NewTimer(s.cfg.FaultLatency)
		defer timer.Stop()
		select {
		case <-timer.C:
		case <-r.Context().Done():
			return
		}
	}
	var request struct {
		WorkUnits int64 `json:"work_units"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&request); err != nil {
		writeError(w, http.StatusBadRequest, "body must be one JSON object containing work_units")
		return
	}
	if err := decoder.Decode(new(any)); !errors.Is(err, io.EOF) {
		writeError(w, http.StatusBadRequest, "body must contain exactly one JSON object")
		return
	}
	if request.WorkUnits < 1 || request.WorkUnits > s.cfg.MaximumWorkUnits {
		writeError(w, http.StatusUnprocessableEntity, fmt.Sprintf("work_units must be from 1 to %d", s.cfg.MaximumWorkUnits))
		return
	}
	job, err := s.store.CreateJob(r.Context(), request.WorkUnits)
	if err != nil {
		s.logger.Error("create job failed", "error", err)
		writeError(w, http.StatusInternalServerError, "could not create job")
		return
	}
	s.metrics.JobsSubmitted.Inc()
	w.Header().Set("Location", "/v1/jobs/"+job.ID)
	writeJSON(w, http.StatusAccepted, job)
}

func (s *Server) getJob(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if _, err := uuid.Parse(id); err != nil {
		writeError(w, http.StatusBadRequest, "job id must be a UUID")
		return
	}
	job, err := s.store.GetJob(r.Context(), id)
	if errors.Is(err, database.ErrNotFound) {
		writeError(w, http.StatusNotFound, "job not found")
		return
	}
	if err != nil {
		s.logger.Error("get job failed", "job_id", id, "error", err)
		writeError(w, http.StatusInternalServerError, "could not get job")
		return
	}
	writeJSON(w, http.StatusOK, job)
}

func (s *Server) shouldInjectError() bool {
	if s.cfg.FaultErrorPercent == 0 {
		return false
	}
	sequence := s.faultSeq.Add(1)
	return int(sequence%100) < s.cfg.FaultErrorPercent
}

func (s *Server) accessLogAndMetrics(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		requestID := r.Header.Get("X-Request-ID")
		if requestID == "" || len(requestID) > 128 || strings.IndexFunc(requestID, func(c rune) bool {
			return !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.')
		}) != -1 {
			requestID = uuid.NewString()
		}
		w.Header().Set("X-Request-ID", requestID)
		spanContext := trace.SpanContextFromContext(r.Context())
		if spanContext.IsValid() {
			w.Header().Set("X-Trace-ID", spanContext.TraceID().String())
		}
		recorder := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(recorder, r)
		route := routeLabel(r)
		statusClass := strconv.Itoa(recorder.status/100) + "xx"
		s.metrics.HTTPRequests.WithLabelValues(route, r.Method, statusClass).Inc()
		observer := s.metrics.HTTPRequestDuration.WithLabelValues(route, r.Method)
		if exemplar, ok := observer.(prometheus.ExemplarObserver); ok && spanContext.IsSampled() {
			exemplar.ObserveWithExemplar(time.Since(start).Seconds(), prometheus.Labels{"trace_id": spanContext.TraceID().String()})
		} else {
			observer.Observe(time.Since(start).Seconds())
		}
		s.logger.Info("http request",
			"method", r.Method,
			"path", r.URL.Path,
			"route", route,
			"request_id", requestID,
			"status", recorder.status,
			"duration_ms", time.Since(start).Milliseconds(),
			"trace_id", spanContext.TraceID().String(),
		)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

func routeLabel(r *http.Request) string {
	if strings.HasPrefix(r.URL.Path, "/v1/jobs/") {
		return "/v1/jobs/{id}"
	}
	switch r.URL.Path {
	case "/v1/jobs", "/health/live", "/health/ready", "/metrics", "/version":
		return r.URL.Path
	default:
		return "unmatched"
	}
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
