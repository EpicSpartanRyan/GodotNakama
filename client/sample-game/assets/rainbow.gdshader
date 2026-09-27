shader_type canvas_item;

// Función clásica para convertir de HSV a RGB en shaders
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
    // Centrar las coordenadas UV (de 0.0 a 1.0 -> -0.5 a 0.5)
    vec2 centered_uv = UV - 0.5;

    // Calcular el ángulo y la distancia (radio) desde el centro
    float angle = atan(centered_uv.y, centered_uv.x);
    float radius = length(centered_uv);

    // Animación del color base (Hue) usando el ángulo y la variable TIME integrada
    // 6.28318 es 2 * PI (TAU) para normalizar el ángulo
    float hue = (angle / 6.28318) + (TIME * 0.5);

    // Generar el color: Tono cambiante, Saturación máxima, Brillo que se desvanece en los bordes
    vec3 color = hsv2rgb(vec3(hue, 1.0, 1.0 - (radius * 1.5)));

    // Recortar la forma para que sea un círculo perfecto
    float alpha = step(radius, 0.5); 

    COLOR = vec4(color, alpha);
}