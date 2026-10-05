package tests

import (
	"github.com/heroiclabs/nakama-common/runtime"
	"github.com/samber/do/v2"
)

type Wheel struct{}
type Engine struct{}

type Car struct {
	Engine *Engine
	Wheels []*Wheel
}

func (c *Car) Start(logger runtime.Logger) {
	logger.Info("Car started: vroooom")
}

// RunDiTest prueba el contenedor de inyección de dependencias `do`
func RunDiTest(logger runtime.Logger) {
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
	car.Start(logger)
	logger.Info("Dependency Injection (do) test completed successfully")
}
