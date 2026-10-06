package tests

import (
	"testing"
	"time"

	"github.com/jellydator/ttlcache/v3"
	"github.com/stretchr/testify/require"
)

func TestCacheStoresAndReturnsValue(t *testing.T) {
	cache := ttlcache.New[string, string](
		ttlcache.WithTTL[string, string](5 * time.Minute),
	)

	cache.Set("test_key", "hello_nakama_cache", ttlcache.DefaultTTL)

	item := cache.Get("test_key")
	require.NotNil(t, item)
	require.Equal(t, "hello_nakama_cache", item.Value())
}
