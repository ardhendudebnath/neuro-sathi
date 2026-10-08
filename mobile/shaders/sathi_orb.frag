// Sathi's living orb: a lit sphere whose surface swirls slowly, faster while
// Sathi listens, with a soft halo. Output is premultiplied alpha.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uListen; // 0 = resting, 1 = listening
uniform vec2 uTilt;    // -1..1, the phone's tilt

out vec4 fragColor;

float hash(vec3 p) {
  p = fract(p * 0.3183099 + 0.1);
  p *= 17.0;
  return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
  vec3 i = floor(x);
  vec3 f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
                 mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
             mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
                 mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
  float a = 0.5;
  float s = 0.0;
  for (int i = 0; i < 5; i++) {
    s += a * noise(p);
    p = p * 2.03 + vec3(1.7, 9.2, 3.1);
    a *= 0.5;
  }
  return s;
}

void main() {
  vec2 uv = (FlutterFragCoord().xy * 2.0 - uSize) / min(uSize.x, uSize.y);
  uv.y = -uv.y;
  float r = 0.74 + 0.025 * sin(uTime * (1.2 + uListen * 3.0)) * (1.0 + uListen * 1.5);
  float d = length(uv);
  float body = 1.0 - smoothstep(r - 0.012, r, d);
  vec3 col = vec3(0.0);
  if (d < r) {
    vec3 n = vec3(uv, sqrt(max(r * r - d * d, 0.0))) / r;
    float t = uTime * (0.18 + uListen * 0.5);
    vec3 p = n * 1.7 + vec3(t, t * 0.7, -t * 0.4);
    float sw = fbm(p + fbm(p * 1.6 + uTime * 0.12) * (1.4 + uListen * 1.2));
    vec3 teal = vec3(0.32, 0.88, 0.78);
    vec3 blue = vec3(0.20, 0.45, 0.95);
    vec3 violet = vec3(0.34, 0.20, 0.70);
    vec3 saffron = vec3(1.0, 0.70, 0.34);
    vec3 base = mix(blue, teal, smoothstep(0.38, 0.72, sw));
    base = mix(base, violet, (1.0 - smoothstep(-0.9, 0.2, n.y)) * 0.75);
    base += saffron * pow(smoothstep(0.6, 0.86, sw), 2.0) * 0.55;
    vec3 light = normalize(vec3(-0.45 - uTilt.x * 0.6, 0.55 + uTilt.y * 0.5, 0.75));
    float diffuse = clamp(dot(n, light), 0.0, 1.0);
    float spec = pow(clamp(dot(reflect(-light, n), vec3(0.0, 0.0, 1.0)), 0.0, 1.0), 36.0);
    float rim = pow(1.0 - n.z, 2.4);
    col = base * (0.42 + 0.7 * diffuse) + spec * 0.85 + rim * vec3(0.55, 0.95, 1.0) * 0.75;
  }
  float halo = exp(-7.0 * max(d - r, 0.0)) * (0.55 + uListen * 0.5) * (1.0 - body);
  vec3 haloColor = mix(vec3(0.32, 0.88, 0.78), vec3(0.45, 0.35, 0.95), 0.5 + 0.5 * sin(uTime * 0.5));
  vec3 rgb = min(col, vec3(1.0)) * body + haloColor * halo;
  fragColor = vec4(rgb, min(body + halo, 1.0));
}
