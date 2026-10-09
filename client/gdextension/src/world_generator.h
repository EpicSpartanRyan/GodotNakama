#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

using namespace godot;

class WorldGenerator : public Object
{
    GDCLASS(WorldGenerator, Object);

public:
    WorldGenerator();

protected:
    static void _bind_methods();
};