package observability

import (
	"context"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.30.0"

	"github.com/skhitrov/k8s-platform-lab/app/internal/config"
)

func ConfigureTracing(ctx context.Context, cfg config.Config, version string) (func(context.Context) error, error) {
	if cfg.OTLPEndpoint == "" {
		return func(context.Context) error { return nil }, nil
	}
	options := []otlptracegrpc.Option{otlptracegrpc.WithEndpoint(cfg.OTLPEndpoint)}
	if cfg.OTLPInsecure {
		options = append(options, otlptracegrpc.WithInsecure())
	}
	exporter, err := otlptracegrpc.New(ctx, options...)
	if err != nil {
		return nil, err
	}
	res, err := resource.Merge(resource.Default(), resource.NewSchemaless(
		semconv.ServiceName("taskflow"),
		semconv.ServiceVersion(version),
	))
	if err != nil {
		return nil, err
	}
	provider := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(provider)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{}, propagation.Baggage{},
	))
	return provider.Shutdown, nil
}
