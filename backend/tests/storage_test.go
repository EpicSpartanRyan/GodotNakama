package tests

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	arkserde "github.com/mlange-42/ark-serde"
	"github.com/mlange-42/ark/ecs"
	"github.com/stretchr/testify/require"
)

func TestS3StorageRoundTripPreservesWorld(t *testing.T) {
	world := ecs.NewWorld()
	mapper := ecs.NewMap2[Position, Velocity](world)
	mapper.NewEntity(
		&Position{X: 12.5, Y: -4},
		&Velocity{DX: 0.25, DY: 2},
	)

	var mu sync.Mutex
	var storedObject []byte
	var requests []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		requests = append(requests, r.Method+" "+r.URL.Path)
		mu.Unlock()

		switch {
		case r.Method == http.MethodHead && r.URL.Path == "/test-bucket":
			w.WriteHeader(http.StatusOK)
		case r.Method == http.MethodPut && r.URL.Path == "/test-bucket/world_state.json.gz":
			body, err := io.ReadAll(r.Body)
			if err != nil {
				t.Errorf("read uploaded object: %v", err)
				http.Error(w, "could not read object", http.StatusInternalServerError)
				return
			}
			mu.Lock()
			storedObject = body
			mu.Unlock()
			w.WriteHeader(http.StatusOK)
		case r.Method == http.MethodGet && r.URL.Path == "/test-bucket/world_state.json.gz":
			mu.Lock()
			body := bytes.Clone(storedObject)
			mu.Unlock()
			if len(body) == 0 {
				http.Error(w, "object not found", http.StatusNotFound)
				return
			}
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write(body)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(server.Close)

	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx,
		config.WithRegion("us-east-1"),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider("test-access-key", "test-secret-key", "")),
	)
	require.NoError(t, err)

	client := s3.NewFromConfig(cfg, func(options *s3.Options) {
		options.BaseEndpoint = aws.String(server.URL)
		options.UsePathStyle = true
	})

	_, err = client.HeadBucket(ctx, &s3.HeadBucketInput{Bucket: aws.String("test-bucket")})
	require.NoError(t, err)

	data, err := arkserde.Serialize(world, arkserde.Opts.Compress())
	require.NoError(t, err)
	require.NotEmpty(t, data)
	_, err = client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String("test-bucket"),
		Key:    aws.String("world_state.json.gz"),
		Body:   bytes.NewReader(data),
	})
	require.NoError(t, err)

	output, err := client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String("test-bucket"),
		Key:    aws.String("world_state.json.gz"),
	})
	require.NoError(t, err)
	defer output.Body.Close()

	downloaded, err := io.ReadAll(output.Body)
	require.NoError(t, err)
	require.Equal(t, data, downloaded)

	restored := ecs.NewWorld()
	ecs.ComponentID[Position](restored)
	ecs.ComponentID[Velocity](restored)
	require.NoError(t, arkserde.Deserialize(downloaded, restored, arkserde.Opts.Compress()))

	query := ecs.NewFilter2[Position, Velocity](restored).Query()
	require.True(t, query.Next())
	position, velocity := query.Get()
	require.Equal(t, Position{X: 12.5, Y: -4}, *position)
	require.Equal(t, Velocity{DX: 0.25, DY: 2}, *velocity)
	require.False(t, query.Next())

	mu.Lock()
	defer mu.Unlock()
	require.Equal(t, []string{
		"HEAD /test-bucket",
		"PUT /test-bucket/world_state.json.gz",
		"GET /test-bucket/world_state.json.gz",
	}, requests)
}
