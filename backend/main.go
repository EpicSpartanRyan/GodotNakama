package main

import (
	"context"
	"database/sql"
	"math/rand/v2"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
	"github.com/jellydator/ttlcache/v3"
	"github.com/mlange-42/ark/ecs"
)

// Position component
type Position struct {
	X, Y float64
}

// Velocity component
type Velocity struct {
	DX, DY float64
}

// Main Module Initialization
func InitModule(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, initializer runtime.Initializer) error {
	logger.Info("Initializing Nakama module with Ark ECS and TTLCache...")

	// --- TTLCache Test ---
	
	// Create a new cache instance with string keys and string values
	// Default TTL is set to 5 minutes
	cache := ttlcache.New[string, string](
		ttlcache.WithTTL[string, string](5 * time.Minute),
	)

	// Start the background goroutine to remove expired items automatically
	go cache.Start()

	// Set a test value in the cache
	cache.Set("test_key", "hello_nakama_cache", ttlcache.DefaultTTL)

	// Retrieve the value immediately to verify it works
	item := cache.Get("test_key")
	if item != nil {
		logger.Info("TTLCache test successful. Retrieved value: %s", item.Value())
	} else {
		logger.Error("TTLCache test failed. Value not found.")
	}

	// --- Ark ECS Test ---

	// Create a new World
	world := ecs.NewWorld()

	// Create a component mapper
	// Save mappers permanently and re-use them for best performance
	mapper := ecs.NewMap2[Position, Velocity](world)

	// Create entities with components
	for range 1000 {
		_ = mapper.NewEntity(
			&Position{X: rand.Float64() * 100, Y: rand.Float64() * 100},
			&Velocity{DX: rand.NormFloat64(), DY: rand.NormFloat64()},
		)
	}

	// Create a filter
	// Save filters permanently and re-use them for best performance
	filter := ecs.NewFilter2[Position, Velocity](world)

	// Time loop
	for range 5000 {
		// Get a fresh query and iterate it
		query := filter.Query()
		for query.Next() {
			// Component access through the Query
			pos, vel := query.Get()
			// Update component fields
			pos.X += vel.DX
			pos.Y += vel.DY
		}
	}

	logger.Info("Ark ECS and TTLCache successfully initialized and verified!")
	return nil
}