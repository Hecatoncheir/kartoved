#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uTextureSize;
uniform float uPixelRatio;
uniform vec2 uCenter;
uniform vec2 uHalfSize;
uniform sampler2D uBackdrop;

out vec4 fragColor;

vec4 backdrop(vec2 pixel) {
  vec2 uv = clamp(pixel, vec2(0.5), uTextureSize - 0.5) / uTextureSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uBackdrop, uv);
}

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  vec2 p = pixel / uPixelRatio - uCenter;
  float radius = min(12.0, min(uHalfSize.x, uHalfSize.y));
  vec2 q = abs(p) - (uHalfSize - radius);
  vec2 corner = max(q, vec2(0.0));
  float distanceToEdge = length(corner) + min(max(q.x, q.y), 0.0) - radius;
  float side = smoothstep(-2.0, 2.0, q.x - q.y);
  vec2 normal = length(corner) > 0.001 ? normalize(corner)
      : normalize(vec2(side, 1.0 - side));
  normal *= sign(p);

  // Выпуклая кромка растягивает изображение по нормали к контуру.
  float bevelWidth = min(20.0, 0.8 * min(uHalfSize.x, uHalfSize.y));
  float bevel = 1.0 - smoothstep(0.0, bevelWidth, -distanceToEdge);
  vec2 sampleAt = pixel - normal * (0.85 * bevelWidth * bevel * uPixelRatio);
  vec2 tap = vec2(uPixelRatio, 0.0);
  vec4 glass = 0.40 * backdrop(sampleAt)
      + 0.15 * (backdrop(sampleAt + tap.xy) + backdrop(sampleAt - tap.xy)
              + backdrop(sampleAt + tap.yx) + backdrop(sampleAt - tap.yx));

  float rim = 1.0 - smoothstep(0.0, 3.5, abs(distanceToEdge));
  float light = dot(normal, vec2(-0.6, -0.8));
  float highlight = rim * max(0.43 * light, -0.16 * light);
  glass.rgb = mix(glass.rgb, vec3(1.0, 0.92, 0.72) * glass.a, highlight);
  fragColor = glass;
}
