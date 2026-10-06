package tests

import (
	"testing"

	"github.com/mlange-42/ark/ecs"
	"github.com/stretchr/testify/require"
)

type Position struct {
	X, Y float64
}

type Velocity struct {
	DX, DY float64
}

func TestECSSimulationUpdatesEntityPositions(t *testing.T) {
	world := ecs.NewWorld()
	mapper := ecs.NewMap2[Position, Velocity](world)
	mapper.NewEntity(
		&Position{X: 10, Y: 20},
		&Velocity{DX: 1.5, DY: -2},
	)
	mapper.NewEntity(
		&Position{X: -3, Y: 7},
		&Velocity{DX: 4, DY: 0.5},
	)

	filter := ecs.NewFilter2[Position, Velocity](world)
	query := filter.Query()
	count := 0
	for query.Next() {
		position, velocity := query.Get()
		position.X += velocity.DX
		position.Y += velocity.DY
		count++
	}

	require.Equal(t, 2, count)
	query = filter.Query()
	for query.Next() {
		position, velocity := query.Get()
		require.NotNil(t, position)
		require.NotNil(t, velocity)
		if position.X == 11.5 {
			require.Equal(t, 18.0, position.Y)
		} else {
			require.Equal(t, 1.0, position.X)
			require.Equal(t, 7.5, position.Y)
		}
	}
}
