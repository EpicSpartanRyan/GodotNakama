package tests

import (
	"bytes"
	"context"
	"io"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/heroiclabs/nakama-common/runtime"
	arkserde "github.com/mlange-42/ark-serde"
	"github.com/mlange-42/ark/ecs"
)

func getEnv(key, fallback string) string {
	if val, ok := os.LookupEnv(key); ok && val != "" {
		return val
	}
	return fallback
}

// RunStorageTest prueba la serialización con Ark Serde y el almacenamiento en RustFS vía AWS SDK v2
func RunStorageTest(ctx context.Context, logger runtime.Logger, world *ecs.World) error {
	endpoint := getEnv("RUSTFS_ENDPOINT", "rustfs:9000")
	if !bytes.HasPrefix([]byte(endpoint), []byte("http://")) && !bytes.HasPrefix([]byte(endpoint), []byte("https://")) {
		useSSL := getEnv("RUSTFS_USE_SSL", "false") == "true"
		if useSSL {
			endpoint = "https://" + endpoint
		} else {
			endpoint = "http://" + endpoint
		}
	}

	accessKeyID := getEnv("RUSTFS_ACCESS_KEY", "admin")
	secretAccessKey := getEnv("RUSTFS_SECRET_KEY", "password123")
	bucketName := getEnv("RUSTFS_BUCKET", "nakama-world-states")
	region := getEnv("RUSTFS_REGION", "us-east-1")

	cfg, err := config.LoadDefaultConfig(ctx,
		config.WithRegion(region),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(accessKeyID, secretAccessKey, "")),
	)
	if err != nil {
		logger.Error("Failed to load AWS SDK config: %v", err)
		return err
	}

	s3Client := s3.NewFromConfig(cfg, func(o *s3.Options) {
		o.BaseEndpoint = aws.String(endpoint)
		o.UsePathStyle = true
	})

	logger.Info("AWS S3 Client connected to RustFS endpoint: %s", endpoint)

	_, err = s3Client.HeadBucket(ctx, &s3.HeadBucketInput{
		Bucket: aws.String(bucketName),
	})
	if err != nil {
		logger.Info("RustFS bucket '%s' not found or inaccessible, creating bucket...", bucketName)
		_, err = s3Client.CreateBucket(ctx, &s3.CreateBucketInput{
			Bucket: aws.String(bucketName),
		})
		if err != nil {
			logger.Error("Failed to create RustFS bucket '%s': %v", bucketName, err)
			return err
		}
		logger.Info("Successfully created RustFS bucket '%s'", bucketName)
	} else {
		logger.Info("RustFS bucket '%s' already exists", bucketName)
	}

	logger.Info("Testing Ark Serde compressed GZIP serialization & RustFS storage via AWS SDK v2...")

	jsonData, err := arkserde.Serialize(world, arkserde.Opts.Compress())
	if err != nil {
		logger.Error("Ark Serde compressed serialization failed: %v", err)
		return err
	}

	objectName := "world_state.json.gz"
	contentType := "application/gzip"

	_, err = s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(bucketName),
		Key:         aws.String(objectName),
		Body:        bytes.NewReader(jsonData),
		ContentType: aws.String(contentType),
	})
	if err != nil {
		logger.Error("Failed to upload compressed world state to RustFS: %v", err)
		return err
	}

	logger.Info("Compressed world state successfully uploaded to RustFS bucket '%s' as '%s' (Size: %d bytes)",
		bucketName, objectName, len(jsonData))

	getOutput, err := s3Client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(bucketName),
		Key:    aws.String(objectName),
	})
	if err != nil {
		logger.Error("Failed to retrieve world state from RustFS: %v", err)
		return err
	}
	defer getOutput.Body.Close()

	downloadedData, err := io.ReadAll(getOutput.Body)
	if err != nil {
		logger.Error("Failed to read downloaded RustFS object bytes: %v", err)
		return err
	}

	logger.Info("Successfully retrieved %d bytes from RustFS object stream", len(downloadedData))

	world2 := ecs.NewWorld()
	_ = ecs.ComponentID[Position](world2)
	_ = ecs.ComponentID[Velocity](world2)

	err = arkserde.Deserialize(downloadedData, world2, arkserde.Opts.Compress())
	if err != nil {
		logger.Error("Ark Serde compressed deserialization from RustFS stream failed: %v", err)
		return err
	}

	logger.Info("Ark Serde compressed deserialization successful from RustFS stream into world2!")

	filter2 := ecs.NewFilter2[Position, Velocity](world2)
	count := 0
	query2 := filter2.Query()
	for query2.Next() {
		count++
	}
	logger.Info("Verified deserialized compressed world entities count: %d", count)

	return nil
}
