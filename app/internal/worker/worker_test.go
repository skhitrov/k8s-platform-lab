package worker

import (
	"context"
	"testing"
)

func TestPerformWorkIsDeterministic(t *testing.T) {
	first, err := PerformWork(context.Background(), "job-one", 1000)
	if err != nil {
		t.Fatal(err)
	}
	second, err := PerformWork(context.Background(), "job-one", 1000)
	if err != nil {
		t.Fatal(err)
	}
	if first != second {
		t.Fatalf("results differ: %q != %q", first, second)
	}
	if len(first) != 64 {
		t.Fatalf("result length = %d, want 64", len(first))
	}
}

func TestPerformWorkCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := PerformWork(ctx, "job-two", 1_000_000); err == nil {
		t.Fatal("expected cancellation error")
	}
}

func TestPerformWorkRejectsInvalidUnits(t *testing.T) {
	if _, err := PerformWork(context.Background(), "job-three", 0); err == nil {
		t.Fatal("expected validation error")
	}
}
