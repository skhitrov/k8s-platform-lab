package model

import "time"

type JobStatus string

const (
	JobQueued    JobStatus = "queued"
	JobRunning   JobStatus = "running"
	JobSucceeded JobStatus = "succeeded"
	JobFailed    JobStatus = "failed"
)

type Job struct {
	ID          string     `json:"id"`
	WorkUnits   int64      `json:"work_units"`
	Status      JobStatus  `json:"status"`
	Result      string     `json:"result,omitempty"`
	Attempts    int        `json:"attempts"`
	MaxAttempts int        `json:"max_attempts"`
	LastError   string     `json:"last_error,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
	StartedAt   *time.Time `json:"started_at,omitempty"`
	CompletedAt *time.Time `json:"completed_at,omitempty"`
	LeaseUntil  *time.Time `json:"-"`
	TraceParent string     `json:"-"`
}
