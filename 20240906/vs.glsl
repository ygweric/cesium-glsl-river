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
uniform float small_wavesize;   // factor to ajust the small wave size
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


    in vec4 position;
in vec2 st;
out vec2 v_st;

const float PI = 3.141592653589793;
const float earthRadius = 6378137.0; // WGS84 椭球体的平均半径
const float angularVelocity = 180.0 / PI;

const float RADII_X = 6378137.0;
const float RADII_Y = 6378137.0;
const float RADII_Z = 6356752.314245;

vec3 worldToGeographic(vec3 worldPosition) {
    // 步骤1: 世界坐标到ECEF坐标
    vec3 ecef = worldPosition;  // 假设世界坐标已经是ECEF

    // 步骤2: ECEF到地理坐标
    float l = length(ecef.xy);
    float e2 = 1.0 - (RADII_Z * RADII_Z) / (RADII_X * RADII_X);
    float u = atan(ecef.z * RADII_X / (l * RADII_Z));
    float lat = atan((ecef.z + e2 * RADII_Z * pow(sin(u), 3.0)) / 
                    (l - e2 * RADII_X * pow(cos(u), 3.0)));
    float lon = atan(ecef.y, ecef.x);
    float N = RADII_X / sqrt(1.0 - e2 * sin(lat) * sin(lat));
    float alt = l / cos(lat) - N;

    // 将弧度转换为度
    lat = degrees(lat);
    lon = degrees(lon);

    return vec3(lon, lat, alt);
}

vec3 geo2cartesian(vec3 geo){
    float cosLat=cos(geo.y);
    float snX=cosLat*cos(geo.x);
    float snY=cosLat*sin(geo.x);
    float snZ=sin(geo.y);
    vec3 sn=normalize(vec3(snX,snY,snZ));
    vec3 radiiSquared=vec3(40680631.59076899*1000000.,40680631.59076899*1000000.,40408299.98466144*1000000.);
    vec3 sk=radiiSquared*sn;
    float gamma=sqrt(dot(sn,sk));
    sk=sk/gamma;
    sn=sn*geo.z;
    return sk+sn;
}

vec3 deg2cartesian(vec3 deg) {
    vec2 radGeo=radians(deg.xy);
    vec3 geo=vec3(radGeo.xy,deg.z);
    return geo2cartesian(geo);
}

void main() {
    float normalizedHeight = 0.0;

    vec2 uv = st;
    float deepwater_fadedepth = 0.5 + coast2water_fadedepth;

    float height = height_map(uv);
    vec3 col;

    float waveheight = clamp(WATER_LEVEL * 3. - 1.5, 0., 1.);
    float level = WATER_LEVEL + .2 * water_map(uv * 15. + vec2(iTime * .1), waveheight);

    if(height <= level) {
        normalizedHeight = level;
    }else{
        normalizedHeight = height; // 减少边缘拉伸的割裂感
    }

    float heightOffset = (maxElevation - minElevation) * normalizedHeight;
    
    // 将顶点位置从模型空间转换到世界空间
    vec4 worldPosition = czm_model * position;
    
    // 将世界坐标转换为经纬度和高度
    vec3 llh = worldToGeographic(worldPosition.xyz);
    
    // 将调整后的经纬度和高度转换回笛卡尔坐标
    vec3 adjustedCartesian = deg2cartesian(vec3(llh.xy,minElevation+heightOffset));
    
    gl_Position = czm_projection * czm_view * vec4(adjustedCartesian,1.0);
    v_st = st;
}