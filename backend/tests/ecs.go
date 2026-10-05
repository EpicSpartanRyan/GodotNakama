package tests

import (
	"math/rand/v2"

	"github.com/heroiclabs/nakama-common/runtime"
	"github.com/mlange-42/ark/ecs"
)

// Componentes
type Position struct {
	X, Y float64
}

type Velocity struct {
	DX, DY float64
}

// RunEcsTest ejecuta la simulación con Ark ECS y retorna el mundo generado
func RunEcsTest(logger runtime.Logger) *ecs.World {
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

	logger.Info("Ark ECS simulation test completed successfully")
	return world
}
