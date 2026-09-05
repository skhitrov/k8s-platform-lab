package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/skhitrov/k8s-platform-lab/app/internal/api"
	"github.com/skhitrov/k8s-platform-lab/app/internal/config"
	"github.com/skhitrov/k8s-platform-lab/app/internal/database"
	"github.com/skhitrov/k8s-platform-lab/app/internal/observability"
	"github.com/skhitrov/k8s-platform-lab/app/internal/worker"
)

var (
	version = "dev"
	commit  = "unknown"
	date    = "unknown"
)

func main() {
	if err := run(); err != nil {
		slog.Error("taskflow stopped", "error", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	logger := observability.NewLogger(cfg.LogLevel)
	slog.SetDefault(logger)

	if len(os.Args) < 2 {
		return errors.New("usage: taskflow <api|worker|migrate|version>")
	}
	if os.Args[1] == "version" {
		fmt.Printf("taskflow version=%s commit=%s built=%s\n", version, commit, date)
		return nil
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	shutdownTelemetry, err := observability.ConfigureTracing(ctx, cfg, version)
	if err != nil {
		return fmt.Errorf("configure tracing: %w", err)
	}
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
		defer cancel()
		if shutdownErr := shutdownTelemetry(shutdownCtx); shutdownErr != nil {
			logger.Error("telemetry shutdown failed", "error", shutdownErr)
		}
	}()

	pool, err := database.Open(ctx, cfg.DatabaseURL, cfg.DatabaseMaxConns, cfg.DatabaseMinConns)
	if err != nil {
		return fmt.Errorf("connect to database: %w", err)
	}
	defer pool.Close()
	store := database.NewStore(pool)

	switch os.Args[1] {
	case "api":
		return api.Run(ctx, cfg, store, logger, api.BuildInfo{
			Version: version,
			Commit:  commit,
			Date:    date,
		})
	case "worker":
		return worker.Run(ctx, cfg, store, logger)
	case "migrate":
		return database.Migrate(ctx, pool)
	default:
		return fmt.Errorf("unknown subcommand %q; expected api, worker, migrate, or version", os.Args[1])
	}
}
