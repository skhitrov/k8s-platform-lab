package config

import (
	"os"
	"testing"
	"time"
)

func TestLoadDefaultsForVersionCommand(t *testing.T) {
	originalArgs := os.Args
	os.Args = []string{"taskflow", "version"}
	t.Cleanup(func() { os.Args = originalArgs })

	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.HTTPAddr != ":8080" {
		t.Fatalf("HTTPAddr = %q", cfg.HTTPAddr)
	}
	if cfg.WorkerPollInterval != 500*time.Millisecond {
		t.Fatalf("WorkerPollInterval = %s", cfg.WorkerPollInterval)
	}
}

func TestLoadRejectsInvalidFaultRate(t *testing.T) {
	originalArgs := os.Args
	os.Args = []string{"taskflow", "version"}
	t.Cleanup(func() { os.Args = originalArgs })
	t.Setenv("FAULT_ERROR_PERCENT", "101")
	if _, err := Load(); err == nil {
		t.Fatal("expected validation error")
	}
}
