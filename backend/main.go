package main

import (
	"context"
	"database/sql"
	"math/rand/v2"
	"os"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
	"github.com/jellydator/ttlcache/v3"
	"github.com/mlange-42/ark-serde"
	"github.com/mlange-42/ark/ecs"
	"github.com/samber/do/v2"
)

// Position component
type Position struct {
	X, Y float64
}

// Velocity component
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

// Main Module Initialization
func InitModule(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, initializer runtime.Initializer) error {
	logger.Info("Initializing Nakama module with Ark ECS, TTLCache, Ark Serde and do...")

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

	// Create entities with components
	for range 1000 {
		_ = mapper.NewEntity(
			&Position{X: rand.Float64() * 100, Y: rand.Float64() * 100},
			&Velocity{DX: rand.NormFloat64(), DY: rand.NormFloat64()},
		)
	}

	filter := ecs.NewFilter2[Position, Velocity](world)

	// Time loop
	for range 5000 {
		query := filter.Query()
		for query.Next() {
			pos, vel := query.Get()
			pos.X += vel.DX
			pos.Y += vel.DY
		}
	}

	// --- Ark Serde Test (with GZIP Compression) ---
	logger.Info("Testing Ark Serde compressed GZIP file serialization & deserialization...")

	// 1. Serializar el mundo aplicando la opción de compresión GZIP
	jsonData, err := arkserde.Serialize(world, arkserde.Opts.Compress())
	if err != nil {
		logger.Error("Ark Serde compressed serialization failed: %v", err)
	} else {
		// 2. Guardar el archivo comprimido en /tmp con extensión .json.gz
		filePath := "/tmp/world_state.json.gz"
		err = os.WriteFile(filePath, jsonData, 0644)
		if err != nil {
			logger.Error("Failed to write compressed world state file: %v", err)
		} else {
			logger.Info("Compressed world state successfully saved to %s (Size: %d bytes)", filePath, len(jsonData))
		}

		// 3. Leer el archivo comprimido recién guardado
		fileData, err := os.ReadFile(filePath)
		if err != nil {
			logger.Error("Failed to read compressed world state file: %v", err)
		} else {
			// 4. Crear un nuevo mundo limpio para la deserialización
			world2 := ecs.NewWorld()

			// Registrar componentes obligatorios antes de deserializar
			_ = ecs.ComponentID[Position](world2)
			_ = ecs.ComponentID[Velocity](world2)

			// 5. Deserializar usando también la opción de compresión GZIP
			err = arkserde.Deserialize(fileData, world2, arkserde.Opts.Compress())
			if err != nil {
				logger.Error("Ark Serde compressed deserialization from file failed: %v", err)
			} else {
				logger.Info("Ark Serde compressed deserialization successful into world2!")

				// 6. Verificar el funcionamiento del mundo deserializado
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

	logger.Info("All modules (Ark ECS, Ark Serde, TTLCache, do) successfully initialized and verified!")
	return nil
}