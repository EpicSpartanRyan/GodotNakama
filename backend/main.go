package main

import (
	"context"
	"database/sql"

	"github.com/heroiclabs/nakama-common/runtime"

	"bryanvalc.com/go-project/tests"
)

func InitModule(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, initializer runtime.Initializer) error {
	logger.Info("Initializing Nakama module with modularized tests...")

	// 1. RPC Registration
	if err := initializer.RegisterRpc("healthcheck", tests.RpcHealthcheck); err != nil {
		return err
	}

	// 2. TTLCache Test
	tests.RunCacheTest(logger)

	// 3. Ark ECS Test
	world := tests.RunEcsTest(logger)

	// 4. RustFS Storage Test (Ark Serde + AWS SDK v2)
	if err := tests.RunStorageTest(ctx, logger, world); err != nil {
		return err
	}

	// 5. Dependency Injection Test (do)
	tests.RunDiTest(logger)

	logger.Info("All modular tests executed and verified successfully!")
	return nil
}
