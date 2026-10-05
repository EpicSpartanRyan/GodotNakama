package main

import (
	"bytes"
	"context"
	"database/sql"
	"io"
	"math/rand/v2"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/heroiclabs/nakama-common/runtime"
	"github.com/jellydator/ttlcache/v3"
	arkserde "github.com/mlange-42/ark-serde"
	"github.com/mlange-42/ark/ecs"
	"github.com/samber/do/v2"
)

// Componente Position
type Position struct {
	X, Y float64
}

// Componente Velocity
type Velocity struct {
	DX, DY float64
}

/**
 * Wheel
 */
type Wheel struct{}

/**
 * Engine
 */
type Engine struct{}

/**
 * Car
 */
type Car struct {
	Engine *Engine
	Wheels []*Wheel
}

func (c *Car) Start() {
	println("vroooom")
}

// Función auxiliar para leer variables de entorno con valor por defecto
func getEnv(key, fallback string) string {
	if val, ok := os.LookupEnv(key); ok && val != "" {
		return val
	}
	return fallback
}

// Inicialización del Módulo Principal de Nakama
func InitModule(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, initializer runtime.Initializer) error {
	logger.Info("Initializing Nakama module with Ark ECS, TTLCache, Ark Serde, do and RustFS (AWS SDK v2)...")

	logger.Info("Registering healthcheck RPC")
	err := initializer.RegisterRpc("healthcheck", RpcHealthcheck)
	if err != nil {
		return err
	}

	// --- TTLCache Test ---
	cache := ttlcache.New[string, string](
		ttlcache.WithTTL[string, string](5 * time.Minute),
	)
	go cache.Start()

	cache.Set("test_key", "hello_nakama_cache", ttlcache.DefaultTTL)

	item := cache.Get("test_key")
	if item != nil {
		logger.Info("TTLCache test successful. Retrieved value: %s", item.Value())
	} else {
		logger.Error("TTLCache test failed. Value not found.")
	}

	// --- Ark ECS Test ---
	world := ecs.NewWorld()
	mapper := ecs.NewMap2[Position, Velocity](world)

	// Crear entidades con componentes
	for range 1000 {
		_ = mapper.NewEntity(
			&Position{X: rand.Float64() * 100, Y: rand.Float64() * 100},
			&Velocity{DX: rand.NormFloat64(), DY: rand.NormFloat64()},
		)
	}

	filter := ecs.NewFilter2[Position, Velocity](world)

	// Bucle de simulación
	for range 5000 {
		query := filter.Query()
		for query.Next() {
			pos, vel := query.Get()
			pos.X += vel.DX
			pos.Y += vel.DY
		}
	}

	// --- Configuración e Inicialización de AWS SDK Go v2 para RustFS ---
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

	// Cargar configuración de AWS con endpoint personalizado para RustFS
	cfg, err := config.LoadDefaultConfig(ctx,
		config.WithRegion(region),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(accessKeyID, secretAccessKey, "")),
	)
	if err != nil {
		logger.Error("Failed to load AWS SDK config: %v", err)
		return err
	}

	// Crear el cliente de S3 configurado con Path Style (requerido para RustFS/MinIO)
	s3Client := s3.NewFromConfig(cfg, func(o *s3.Options) {
		o.BaseEndpoint = aws.String(endpoint)
		o.UsePathStyle = true
	})

	logger.Info("AWS S3 Client connected to RustFS endpoint: %s", endpoint)

	// Verificar si el bucket existe, y si no, crearlo
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

	// --- Ark Serde Test (Serialización con GZIP + Guardado en RustFS mediante AWS SDK) ---
	logger.Info("Testing Ark Serde compressed GZIP serialization & RustFS storage via AWS SDK v2...")

	// 1. Serializar el mundo aplicando la opción de compresión GZIP
	jsonData, err := arkserde.Serialize(world, arkserde.Opts.Compress())
	if err != nil {
		logger.Error("Ark Serde compressed serialization failed: %v", err)
	} else {
		objectName := "world_state.json.gz"
		contentType := "application/gzip"

		// 2. Subir directamente el buffer de bytes comprimidos a RustFS usando PutObject
		_, err = s3Client.PutObject(ctx, &s3.PutObjectInput{
			Bucket:      aws.String(bucketName),
			Key:         aws.String(objectName),
			Body:        bytes.NewReader(jsonData),
			ContentType: aws.String(contentType),
		})
		if err != nil {
			logger.Error("Failed to upload compressed world state to RustFS: %v", err)
		} else {
			logger.Info("Compressed world state successfully uploaded to RustFS bucket '%s' as '%s' (Size: %d bytes)",
				bucketName, objectName, len(jsonData))

			// 3. Descargar el archivo directamente desde RustFS para validar la recuperación
			getOutput, err := s3Client.GetObject(ctx, &s3.GetObjectInput{
				Bucket: aws.String(bucketName),
				Key:    aws.String(objectName),
			})
			if err != nil {
				logger.Error("Failed to retrieve world state from RustFS: %v", err)
			} else {
				defer getOutput.Body.Close()

				downloadedData, err := io.ReadAll(getOutput.Body)
				if err != nil {
					logger.Error("Failed to read downloaded RustFS object bytes: %v", err)
				} else {
					logger.Info("Successfully retrieved %d bytes from RustFS object stream", len(downloadedData))

					// 4. Crear un mundo limpio para la deserialización
					world2 := ecs.NewWorld()

					// Registrar componentes obligatorios antes de deserializar
					_ = ecs.ComponentID[Position](world2)
					_ = ecs.ComponentID[Velocity](world2)

					// 5. Deserializar los bytes descargados desde RustFS
					err = arkserde.Deserialize(downloadedData, world2, arkserde.Opts.Compress())
					if err != nil {
						logger.Error("Ark Serde compressed deserialization from RustFS stream failed: %v", err)
					} else {
						logger.Info("Ark Serde compressed deserialization successful from RustFS stream into world2!")

						// 6. Verificar que las entidades se reconstruyeron correctamente
						filter2 := ecs.NewFilter2[Position, Velocity](world2)
						count := 0
						query2 := filter2.Query()
						for query2.Next() {
							count++
						}
						logger.Info("Verified deserialized compressed world entities count: %d", count)
					}
				}
			}
		}
	}

	// --- do (Dependency Injection) Test ---
	injector := do.New()

	do.ProvideNamedValue(injector, "wheel-1", &Wheel{})
	do.ProvideNamedValue(injector, "wheel-2", &Wheel{})
	do.ProvideNamedValue(injector, "wheel-3", &Wheel{})
	do.ProvideNamedValue(injector, "wheel-4", &Wheel{})

	do.Provide(injector, func(i do.Injector) (*Car, error) {
		car := Car{
			Engine: do.MustInvoke[*Engine](i),
			Wheels: []*Wheel{
				do.MustInvokeNamed[*Wheel](i, "wheel-1"),
				do.MustInvokeNamed[*Wheel](i, "wheel-2"),
				do.MustInvokeNamed[*Wheel](i, "wheel-3"),
				do.MustInvokeNamed[*Wheel](i, "wheel-4"),
			},
		}

		return &car, nil
	})

	do.Provide(injector, func(i do.Injector) (*Engine, error) {
		return &Engine{}, nil
	})

	car := do.MustInvoke[*Car](injector)
	car.Start()

	logger.Info("All modules (Ark ECS, Ark Serde, TTLCache, do, RustFS/AWS SDK v2) successfully initialized and verified!")
	return nil
}
