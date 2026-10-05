package tests

import (
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
	"github.com/jellydator/ttlcache/v3"
)

// RunCacheTest verifica la inicialización y uso de TTLCache
func RunCacheTest(logger runtime.Logger) {
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
}
