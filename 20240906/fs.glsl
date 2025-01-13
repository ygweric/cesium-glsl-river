uniform sampler2D heightMap;
uniform float heightScale;
uniform float maxElevation;
uniform float minElevation;
uniform sampler2D iChannel0;
uniform float iTime;

uniform float coast2water_fadedepth;
uniform float large_waveheight; // change to adjust the "heavy" waves
uniform float large_wavesize;  // factor to adjust the large wave size
uniform float small_waveheight;  // change to adjust the small random waves
uniform float small_wavesize;  b // factor to ajust the small wave size
uniform float water_softlight_fact;  // range [1..200] (should be << smaller than glossy-fact)
uniform float water_glossylight_fact; // range [1..200]
uniform float particle_amount;
uniform float WATER_LEVEL; // Water level (range: 0.0 - 2.0)
vec3 watercolor = vec3(0.0, 0.60, 0.66); // 'transparent' low-water color (RGB)
vec3 watercolor2 = vec3(0.0,0.0,0.5); // deep-water color (RGB, should be darker than the low-water color)
vec3 water_specularcolor = vec3(1.3, 1.3, 0.9);    // specular Color (RGB) of the water-highlights
vec3 light;

// calculate random value
float hash(float n) {
return fract(sin(n) * 43758.5453123);
}

// 2d noise function
float noise1(in vec2 x) {
vec2 p = floor(x);
vec2 f = smoothstep(0.0, 1.0, fract(x));
float n = p.x + p.y * 57.0;
return mix(mix(hash(n + 0.0), hash(n + 1.0), f.x), mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y);
}

float noise(vec2 p) {
return textureLod(iChannel0, p * vec2(1. / 256.), 0.0).x;
}

float height_map(vec2 p) {
float f = texture(heightMap,p).r;
return clamp(f, 0., 10.);
}

const mat2 m = mat2(0.72, -1.60, 1.60, 0.72);

float water_map(vec2 p, float height) {
vec2 p2 = p * large_wavesize;
vec2 shift1 = 0.001 * vec2(iTime * 160.0 * 2.0, iTime * 120.0 * 2.0);
vec2 shift2 = 0.001 * vec2(iTime * 190.0 * 2.0, -iTime * 130.0 * 2.0);

// coarse crossing 'ocean' waves...
float f = 0.6000 * noise(p);
f += 0.2500 * noise(p * m);
f += 0.1666 * noise(p * m * m);
float wave = sin(p2.x * 0.622 + p2.y * 0.622 + shift2.x * 4.269) * large_waveheight * f * height * height;

p *= small_wavesize;
f = 0.;
float amp = 1.0, s = .5;
for(int i = 0; i < 9; i++) {
    p = m * p * .947;
    f -= amp * abs(sin((noise(p + shift1 * s) - .5) * 2.));
    amp = amp * .59;
    s *= -1.329;
}

return wave + f * small_waveheight;
}

float nautic(vec2 p) {
p *= 18.;
float f = 0.;
float amp = 1.0, s = .5;
for(int i = 0; i < 3; i++) {
    p = m * p * 1.2;
    f += amp * abs(smoothstep(0., 1., noise(p + iTime * s)) - .5);
    amp = amp * .5;
    s *= -1.227;
}
return pow(1. - f, 5.);
}

float particles(vec2 p) {
p *= 200.;
float f = 0.;
float amp = 1.0, s = 1.5;
for(int i = 0; i < 3; i++) {
    p = m * p * 1.2;
    f += amp * noise(p + iTime * s);
    amp = amp * .5;
    s *= -1.227;
}
return pow(f * .35, 7.) * particle_amount;
}

float test_shadow(vec2 xy, float height) {
vec3 r0 = vec3(xy, height);
vec3 rd = normalize(light - r0);

float hit = 1.0;
float t = 0.001;
for(int j = 1; j < 25; j++) {
    vec3 p = r0 + t * rd;
    float h = height_map(p.xy);
    float height_diff = p.z - h;
    if(height_diff < 0.0) {
        return 0.0;
    }
    t += 0.01 + height_diff * .02;
    hit = min(hit, 2. * height_diff / t); // soft shaddow   
}
return hit;
}


in vec2 v_st;

void main(){
light = vec3(-0., .0, 2.8); // position of the sun
vec2 uv = v_st;

float deepwater_fadedepth = 0.5 + coast2water_fadedepth;

float height = height_map(uv);
vec3 col;

float waveheight = clamp(WATER_LEVEL * 3. - 1.5, 0., 1.);
float level = WATER_LEVEL + .2 * water_map(uv * 15. + vec2(iTime * .1), waveheight);
if(height <= level) {
    vec2 dif = vec2(.0, .01);
    vec2 pos = uv * 15. + vec2(iTime * .01);
    float h1 = water_map(pos - dif, waveheight);
    float h2 = water_map(pos + dif, waveheight);
    float h3 = water_map(pos - dif.yx, waveheight);
    float h4 = water_map(pos + dif.yx, waveheight);
    vec3 normwater = normalize(vec3(h3 - h4, h1 - h2, .125)); // norm-vector of the 'bumpy' water-plane
    uv += normwater.xy * .002 * (level - height);

    col = vec3(1.0);

    float coastfade = clamp((level - height) / coast2water_fadedepth, 0., 1.);
    float coastfade2 = clamp((level - height) / deepwater_fadedepth, 0., 1.);
    float intensity = col.r * .2126 + col.g * .7152 + col.b * .0722;
    watercolor = mix(watercolor * intensity, watercolor2, smoothstep(0., 1., coastfade2));

    vec3 r0 = vec3(uv, WATER_LEVEL);
    vec3 rd = normalize(light - r0); // ray-direction to the light from water-position
    float grad = dot(normwater, rd); // dot-product of norm-vector and light-direction
    float specular = pow(grad, water_softlight_fact);  // used for soft highlights                          
    float specular2 = pow(grad, water_glossylight_fact); // used for glossy highlights
    float gradpos = dot(vec3(0., 0., 1.), rd);
    float specular1 = smoothstep(0., 1., pow(gradpos, 5.));  // used for diffusity (some darker corona around light's specular reflections...)                          
    float watershade = test_shadow(uv, level);
    watercolor *= 2.2 + watershade;
    watercolor += (.2 + .8 * watershade) * ((grad - 1.0) * .5 + specular) * .25;
    watercolor /= (1. + specular1 * 1.25);
    watercolor += watershade * specular2 * water_specularcolor;
    watercolor += watershade * coastfade * (1. - coastfade2) * (vec3(.5, .6, .7) * nautic(uv) + vec3(1., 1., 1.) * particles(uv));

    col = mix(col, watercolor, coastfade);

    float alpha = clamp(coastfade,0.1,0.6);
    out_FragColor = vec4(col,1.0);
    return;
}
}