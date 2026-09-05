package api

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/skhitrov/k8s-platform-lab/app/internal/config"
	"github.com/skhitrov/k8s-platform-lab/app/internal/database"
	"github.com/skhitrov/k8s-platform-lab/app/internal/model"
)

type fakeStore struct {
	pingErr   error
	createErr error
	getErr    error
	job       model.Job
}

func (f *fakeStore) Ping(context.Context) error { return f.pingErr }

func (f *fakeStore) CreateJob(_ context.Context, workUnits int64) (model.Job, error) {
	if f.createErr != nil {
		return model.Job{}, f.createErr
	}
	job := f.job
	job.WorkUnits = workUnits
	return job, nil
}

func (f *fakeStore) GetJob(context.Context, string) (model.Job, error) {
	return f.job, f.getErr
}

func testServer(store JobStore) *Server {
	cfg := config.Config{
		MaximumWorkUnits: 1_000_000,
		ReadinessTimeout: time.Second,
	}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	return NewServer(cfg, store, logger, BuildInfo{Version: "test", Commit: "abc123", Date: "today"})
}

func TestCreateAndGetJob(t *testing.T) {
	store := &fakeStore{job: model.Job{ID: "1f895250-80de-426a-8958-fbb8110c0087", Status: model.JobQueued}}
	handler := testServer(store).Handler()

	request := httptest.NewRequest(http.MethodPost, "/v1/jobs", bytes.NewBufferString(`{"work_units":4096}`))
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusAccepted {
		t.Fatalf("POST status = %d, want %d; body=%s", response.Code, http.StatusAccepted, response.Body.String())
	}
	if got := response.Header().Get("Location"); got != "/v1/jobs/"+store.job.ID {
		t.Fatalf("Location = %q", got)
	}

	request = httptest.NewRequest(http.MethodGet, "/v1/jobs/"+store.job.ID, nil)
	response = httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("GET status = %d, want %d", response.Code, http.StatusOK)
	}
}

func TestCreateJobValidation(t *testing.T) {
	handler := testServer(&fakeStore{}).Handler()
	tests := []struct {
		name string
		body string
	}{
		{name: "missing", body: `{}`},
		{name: "negative", body: `{"work_units":-1}`},
		{name: "too large", body: `{"work_units":1000001}`},
		{name: "unknown field", body: `{"work_units":1,"surprise":true}`},
		{name: "invalid json", body: `{`},
		{name: "multiple objects", body: `{"work_units":1}{"work_units":2}`},
		{name: "trailing garbage", body: `{"work_units":1}oops`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodPost, "/v1/jobs", strings.NewReader(tt.body))
			response := httptest.NewRecorder()
			handler.ServeHTTP(response, request)
			if response.Code < 400 || response.Code >= 500 {
				t.Fatalf("status = %d, want a 4xx", response.Code)
			}
		})
	}
}

func TestReadiness(t *testing.T) {
	store := &fakeStore{}
	handler := testServer(store).Handler()
	request := httptest.NewRequest(http.MethodGet, "/health/ready", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("healthy status = %d", response.Code)
	}

	store.pingErr = errors.New("database down")
	response = httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("unhealthy status = %d", response.Code)
	}
}

func TestMissingJob(t *testing.T) {
	store := &fakeStore{getErr: database.ErrNotFound}
	request := httptest.NewRequest(http.MethodGet, "/v1/jobs/1f895250-80de-426a-8958-fbb8110c0087", nil)
	response := httptest.NewRecorder()
	testServer(store).Handler().ServeHTTP(response, request)
	if response.Code != http.StatusNotFound {
		t.Fatalf("status = %d", response.Code)
	}
}

func TestInvalidJobIDIsClientError(t *testing.T) {
	response := httptest.NewRecorder()
	testServer(&fakeStore{}).Handler().ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/v1/jobs/not-a-uuid", nil))
	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", response.Code)
	}
}

func TestRequestCorrelationAndBoundedRoutes(t *testing.T) {
	server := testServer(&fakeStore{})
	for _, path := range []string{"/missing-one", "/missing-two"} {
		request := httptest.NewRequest(http.MethodGet, path, nil)
		request.Header.Set("X-Request-ID", "incident-001")
		response := httptest.NewRecorder()
		server.Handler().ServeHTTP(response, request)
		if response.Header().Get("X-Request-ID") != "incident-001" {
			t.Fatal("request correlation was lost")
		}
		if routeLabel(request) != "unmatched" {
			t.Fatal("unknown paths must not create arbitrary metric labels")
		}
	}
	request := httptest.NewRequest(http.MethodGet, "/health/live", nil)
	request.Header.Set("X-Request-ID", strings.Repeat("x", 129))
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)
	if got := response.Header().Get("X-Request-ID"); len(got) != 36 {
		t.Fatalf("invalid request ID was not replaced: %q", got)
	}
}
