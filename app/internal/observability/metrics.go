package observability

import (
	"github.com/prometheus/client_golang/prometheus"
)

type Metrics struct {
	Registry            *prometheus.Registry
	HTTPRequests        *prometheus.CounterVec
	HTTPRequestDuration *prometheus.HistogramVec
	JobsSubmitted       prometheus.Counter
	JobsProcessed       *prometheus.CounterVec
	JobDuration         prometheus.Histogram
	QueueDepth          prometheus.Gauge
	QueueOldestAge      prometheus.Gauge
}

func NewMetrics() *Metrics {
	m := &Metrics{
		Registry: prometheus.NewRegistry(),
		HTTPRequests: prometheus.NewCounterVec(prometheus.CounterOpts{
			Namespace: "taskflow",
			Subsystem: "http",
			Name:      "requests_total",
			Help:      "Total HTTP requests handled by route, method, and status class.",
		}, []string{"route", "method", "status_class"}),
		HTTPRequestDuration: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Namespace: "taskflow",
			Subsystem: "http",
			Name:      "request_duration_seconds",
			Help:      "HTTP request duration by route and method.",
			Buckets:   prometheus.DefBuckets,
		}, []string{"route", "method"}),
		JobsSubmitted: prometheus.NewCounter(prometheus.CounterOpts{
			Namespace: "taskflow",
			Name:      "jobs_submitted_total",
			Help:      "Total jobs accepted by the API.",
		}),
		JobsProcessed: prometheus.NewCounterVec(prometheus.CounterOpts{
			Namespace: "taskflow",
			Name:      "jobs_processed_total",
			Help:      "Total jobs processed by outcome.",
		}, []string{"outcome"}),
		JobDuration: prometheus.NewHistogram(prometheus.HistogramOpts{
			Namespace: "taskflow",
			Name:      "job_duration_seconds",
			Help:      "Time spent doing synthetic job work.",
			Buckets:   []float64{0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5},
		}),
		QueueDepth: prometheus.NewGauge(prometheus.GaugeOpts{
			Namespace: "taskflow",
			Name:      "queue_depth",
			Help:      "Number of queued jobs last observed by a worker.",
		}),
		QueueOldestAge: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "taskflow_queue_oldest_age_seconds",
			Help: "Age of the oldest queued job last observed by a worker.",
		}),
	}
	m.Registry.MustRegister(
		prometheus.NewGoCollector(),
		prometheus.NewProcessCollector(prometheus.ProcessCollectorOpts{}),
		m.HTTPRequests,
		m.HTTPRequestDuration,
		m.JobsSubmitted,
		m.JobsProcessed,
		m.JobDuration,
		m.QueueDepth,
		m.QueueOldestAge,
	)
	return m
}

func (m *Metrics) RegisterStore(store any) {
	if source, ok := store.(interface{ RegisterMetrics(prometheus.Registerer) }); ok {
		source.RegisterMetrics(m.Registry)
	}
}
