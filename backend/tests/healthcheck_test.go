package tests

import (
	"context"
	"database/sql"
	"testing"

	"github.com/heroiclabs/nakama-common/runtime"
	"github.com/stretchr/testify/require"

	"bryanvalc.com/go-project/healthcheck"
)

type testLogger struct{}

func (testLogger) Debug(string, ...interface{}) {}
func (testLogger) Info(string, ...interface{})  {}
func (testLogger) Warn(string, ...interface{})  {}
func (testLogger) Error(string, ...interface{}) {}
func (logger testLogger) WithField(string, interface{}) runtime.Logger {
	return logger
}
func (logger testLogger) WithFields(map[string]interface{}) runtime.Logger {
	return logger
}
func (testLogger) Fields() map[string]interface{} {
	return nil
}

func TestHealthcheckReturnsSuccessJSON(t *testing.T) {
	response, err := healthcheck.RpcHealthcheck(
		context.Background(),
		testLogger{},
		(*sql.DB)(nil),
		nil,
		"",
	)

	require.NoError(t, err)
	require.JSONEq(t, `{"success":true}`, response)
}
