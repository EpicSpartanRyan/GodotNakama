package main

import (
	"context"
	"database/sql"

	"github.com/heroiclabs/nakama-common/runtime"

	"bryanvalc.com/go-project/tests"
)

func InitModule(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, initializer runtime.Initializer) error {
	if err := initializer.RegisterRpc("healthcheck", tests.RpcHealthcheck); err != nil {
		return err
	}

	logger.Info("Nakama module initialized")
	return nil
}
