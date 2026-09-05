package config

import (
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	DatabaseURL         string
	DatabaseMaxConns    int32
	DatabaseMinConns    int32
	HTTPAddr            string
	LogLevel            string
	WorkerPollInterval  time.Duration
	WorkerLeaseDuration time.Duration
	ShutdownTimeout     time.Duration
	OTLPEndpoint        string
	OTLPInsecure        bool
	FaultErrorPercent   int
	FaultLatency        time.Duration
	ReadinessTimeout    time.Duration
	MaximumWorkUnits    int64
}

func Load() (Config, error) {
	cfg := Config{
		DatabaseURL:       databaseURL(),
		HTTPAddr:          valueOrDefault("HTTP_ADDR", ":8080"),
		LogLevel:          strings.ToLower(valueOrDefault("LOG_LEVEL", "info")),
		OTLPEndpoint:      os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT"),
		DatabaseMaxConns:  5,
		DatabaseMinConns:  1,
		FaultErrorPercent: 0,
		MaximumWorkUnits:  1_000_000,
	}

	var err error
	if cfg.DatabaseMaxConns, err = int32Value("DATABASE_MAX_CONNS", cfg.DatabaseMaxConns, 1, 500); err != nil {
		return Config{}, err
	}
	if cfg.DatabaseMinConns, err = int32Value("DATABASE_MIN_CONNS", cfg.DatabaseMinConns, 0, cfg.DatabaseMaxConns); err != nil {
		return Config{}, err
	}
	if cfg.WorkerPollInterval, err = durationValue("WORKER_POLL_INTERVAL", 500*time.Millisecond); err != nil {
		return Config{}, err
	}
	if cfg.WorkerLeaseDuration, err = durationValue("WORKER_LEASE_DURATION", 30*time.Second); err != nil {
		return Config{}, err
	}
	if cfg.ShutdownTimeout, err = durationValue("SHUTDOWN_TIMEOUT", 10*time.Second); err != nil {
		return Config{}, err
	}
	if cfg.ReadinessTimeout, err = durationValue("READINESS_TIMEOUT", 2*time.Second); err != nil {
		return Config{}, err
	}
	if cfg.OTLPInsecure, err = boolValue("OTEL_EXPORTER_OTLP_INSECURE", true); err != nil {
		return Config{}, err
	}
	if cfg.FaultErrorPercent, err = intValue("FAULT_ERROR_PERCENT", 0, 0, 100); err != nil {
		return Config{}, err
	}
	faultLatencyMS, err := intValue("FAULT_LATENCY_MS", 0, 0, 60_000)
	if err != nil {
		return Config{}, err
	}
	cfg.FaultLatency = time.Duration(faultLatencyMS) * time.Millisecond
	if cfg.DatabaseURL == "" && len(os.Args) > 1 && os.Args[1] != "version" {
		return Config{}, fmt.Errorf("DATABASE_URL is required for %s", os.Args[1])
	}
	return cfg, nil
}

func databaseURL() string {
	if value := os.Getenv("DATABASE_URL"); value != "" {
		return value
	}
	host := os.Getenv("DB_HOST")
	password := os.Getenv("DB_PASSWORD")
	if host == "" || password == "" {
		return ""
	}
	port := valueOrDefault("DB_PORT", "5432")
	name := valueOrDefault("DB_NAME", "taskflow")
	user := valueOrDefault("DB_USER", "taskflow")
	connection := &url.URL{
		Scheme: "postgres",
		User:   url.UserPassword(user, password),
		Host:   host + ":" + port,
		Path:   name,
	}
	query := connection.Query()
	query.Set("sslmode", valueOrDefault("DB_SSLMODE", "disable"))
	connection.RawQuery = query.Encode()
	return connection.String()
}

func valueOrDefault(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

func durationValue(name string, fallback time.Duration) (time.Duration, error) {
	raw := os.Getenv(name)
	if raw == "" {
		return fallback, nil
	}
	value, err := time.ParseDuration(raw)
	if err != nil || value <= 0 {
		return 0, fmt.Errorf("%s must be a positive duration, got %q", name, raw)
	}
	return value, nil
}

func intValue(name string, fallback, minimum, maximum int) (int, error) {
	raw := os.Getenv(name)
	if raw == "" {
		return fallback, nil
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value < minimum || value > maximum {
		return 0, fmt.Errorf("%s must be an integer from %d to %d, got %q", name, minimum, maximum, raw)
	}
	return value, nil
}

func int32Value(name string, fallback, minimum, maximum int32) (int32, error) {
	value, err := intValue(name, int(fallback), int(minimum), int(maximum))
	return int32(value), err
}

func boolValue(name string, fallback bool) (bool, error) {
	raw := os.Getenv(name)
	if raw == "" {
		return fallback, nil
	}
	value, err := strconv.ParseBool(raw)
	if err != nil {
		return false, fmt.Errorf("%s must be true or false, got %q", name, raw)
	}
	return value, nil
}
