package tests

import (
	"bytes"
	"context"
	"io"
	"net"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	arkserde "github.com/mlange-42/ark-serde"
	"github.com/mlange-42/ark/ecs"
	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"
)

func TestRustFSStorageRoundTripPreservesWorld(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	rustfs, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: testcontainers.ContainerRequest{
			Image:        "rustfs/rustfs:1.0.1",
			ExposedPorts: []string{"9000/tcp"},
			Env: map[string]string{
				"RUSTFS_ACCESS_KEY": "admin",
				"RUSTFS_SECRET_KEY": "password123",
				"RUSTFS_ADDRESS":    ":9000",
			},
			Cmd:        []string{"/data"},
			WaitingFor: wait.ForHTTP("/health").WithPort("9000/tcp").WithStartupTimeout(90 * time.Second),
		},
		Started: true,
	})
	require.NoError(t, err)
	t.Cleanup(func() {
		terminateCtx, terminateCancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer terminateCancel()
		require.NoError(t, rustfs.Terminate(terminateCtx))
	})

	host, err := rustfs.Host(ctx)
	require.NoError(t, err)
	port, err := rustfs.MappedPort(ctx, "9000/tcp")
	require.NoError(t, err)
	endpoint := "http://" + net.JoinHostPort(host, port.Port())

	cfg, err := config.LoadDefaultConfig(ctx,
		config.WithRegion("us-east-1"),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider("admin", "password123", "")),
	)
	require.NoError(t, err)

	client := s3.NewFromConfig(cfg, func(options *s3.Options) {
		options.BaseEndpoint = aws.String(endpoint)
		options.UsePathStyle = true
	})

	bucket := "nakama-world-states-test"
	_, err = client.CreateBucket(ctx, &s3.CreateBucketInput{Bucket: aws.String(bucket)})
	require.NoError(t, err)
	_, err = client.HeadBucket(ctx, &s3.HeadBucketInput{Bucket: aws.String(bucket)})
	require.NoError(t, err)

	world := ecs.NewWorld()
	mapper := ecs.NewMap2[Position, Velocity](world)
	mapper.NewEntity(
		&Position{X: 12.5, Y: -4},
		&Velocity{DX: 0.25, DY: 2},
	)

	data, err := arkserde.Serialize(world, arkserde.Opts.Compress())
	require.NoError(t, err)
	require.NotEmpty(t, data)

	objectName := "world_state.json.gz"
	_, err = client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(objectName),
		Body:   bytes.NewReader(data),
	})
	require.NoError(t, err)

	output, err := client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(objectName),
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

	t.Logf("Stored and restored world state through RustFS at %s/%s/%s", endpoint, bucket, objectName)
}
