package tests

import (
	"strconv"
	"testing"

	"github.com/samber/do/v2"
	"github.com/stretchr/testify/require"
)

type testWheel struct {
	id int
}
type testEngine struct{}

type testCar struct {
	engine *testEngine
	wheels []*testWheel
}

func TestDependencyInjectionBuildsCar(t *testing.T) {
	injector := do.New()
	for i := 1; i <= 4; i++ {
		do.ProvideNamedValue(injector, wheelName(i), &testWheel{id: i})
	}
	do.Provide(injector, func(i do.Injector) (*testEngine, error) {
		return &testEngine{}, nil
	})
	do.Provide(injector, func(i do.Injector) (*testCar, error) {
		engine, err := do.Invoke[*testEngine](i)
		if err != nil {
			return nil, err
		}

		wheels := make([]*testWheel, 0, 4)
		for n := 1; n <= 4; n++ {
			wheel, err := do.InvokeNamed[*testWheel](i, wheelName(n))
			if err != nil {
				return nil, err
			}
			wheels = append(wheels, wheel)
		}

		return &testCar{engine: engine, wheels: wheels}, nil
	})

	car, err := do.Invoke[*testCar](injector)
	require.NoError(t, err)
	require.NotNil(t, car)
	require.NotNil(t, car.engine)
	require.Len(t, car.wheels, 4)
	for i, wheel := range car.wheels {
		require.NotNil(t, wheel)
		require.Equal(t, i+1, wheel.id)
	}
}

func wheelName(number int) string {
	return "wheel-" + strconv.Itoa(number)
}
