// MSL for the three passes, compiled at runtime (the Command Line Tools have
// no offline Metal compiler). Ported from the Rive version's WGSL, itself a
// port of ascii-sharks renderer.ts (MIT).
//
//   wake_main     cols x rows, rg16Float   wake energy (r) and eat heat (g); runs once per sim step
//   cells_main    cols x rows, rgba8       which shark part or fish fills each cell
//   compose_main  full resolution          grid, wake dots, heat, fish, sharks, glyphs
//
// Buffer layout: see FrameLayout in FramePacker.swift.

enum Shaders {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

constant int NODES = 20;
constant int STRIDE = 29;
constant float MAXV = 1.6;
constant float PI = 3.14159265;

constant int FLAG_BODY = 1;
constant int FLAG_EDGE = 2;
constant int FLAG_FIN = 3;
constant int FLAG_RIDGE = 4;
constant int FLAG_EYE = 5;
constant int FLAG_MARK = 6;
constant int FLAG_FISH = 7;

struct VOut {
    float4 clip [[position]];
};

vertex VOut vs_main(uint vi [[vertex_id]]) {
    float x = float((vi << 1) & 2u);
    float y = float(vi & 2u);
    VOut o;
    o.clip = float4(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
    return o;
}

// ---------------------------------------------------------------- wake

// renderer.ts stamp(): a soft disc in cells, squashed for the tall cells.
static float stamp(float2 cell, float2 at, float radius, float amount) {
    float2 dc = cell - at;
    if (fabs(dc.x) > radius || fabs(dc.y) > radius) { return 0.0; }
    float d = length(float2(dc.x, dc.y * 1.4));
    if (d > radius + 0.5) { return 0.0; }
    return amount * (1.0 - d / (radius + 1.0));
}

fragment float4 wake_main(VOut in [[stage_in]],
                          constant float4* hd [[buffer(0)]],
                          constant float4* sh [[buffer(1)]],
                          constant float4* ev [[buffer(2)]],
                          constant int& withEvents [[buffer(3)]],
                          texture2d<float, access::read> prev [[texture(0)]],
                          texture2d<float, access::read> fish [[texture(1)]]) {
    if (hd[3].w > 0.5) { return float4(0.0); }
    float2 grid = hd[0].zw;
    float2 cwh = hd[1].xy;
    float dt = hd[1].w;
    uint2 c = uint2(in.clip.xy);
    float2 cell = float2(c);

    // Blur + decay so wakes spread like ripples and fade.
    float2 here = prev.read(c).rg;
    float e0 = here.r;
    float l = e0, r = e0, t = e0, b = e0;
    if (c.x > 0) { l = prev.read(c - uint2(1, 0)).r; }
    if (cell.x < grid.x - 1.0) { r = prev.read(c + uint2(1, 0)).r; }
    if (c.y > 0) { t = prev.read(c - uint2(0, 1)).r; }
    if (cell.y < grid.y - 1.0) { b = prev.read(c + uint2(0, 1)).r; }
    float e = (e0 * 4.0 + l + r + t + b) * 0.125 * exp(-dt * 1.5);
    float heat = here.g * exp(-dt * 2.2);

    // Every live fish stirs its cell; panicking fish more (summed on the CPU).
    e = min(MAXV, e + fish.read(c).b * 0.25);

    // The tail sweeps the most water.
    int sharkCount = int(hd[3].x);
    for (int i = 0; i < sharkCount; i++) {
        int base = i * STRIDE;
        float speed = sh[base + 1].z;
        for (int k = NODES - 6; k < NODES; k++) {
            float2 n = sh[base + 8 + k].xy;
            if (n.x < 0.0 || n.y < 0.0) { continue; }
            float2 nc = floor(n / cwh);
            if (nc.x == cell.x && nc.y == cell.y) {
                e = min(MAXV, e + 0.05 + speed * 0.0012);
            }
        }
    }

    // Eats flash red and ripple; clicks splash. Only the first pass of a frame.
    if (withEvents != 0) {
        int eventCount = int(hd[3].y);
        for (int k = 0; k < eventCount; k++) {
            float4 v = ev[k];
            float2 at = floor(v.xy / cwh);
            if (v.z < 0.5) {
                heat = min(MAXV, heat + stamp(cell, at, 2.0, 1.0));
                e = min(MAXV, e + stamp(cell, at, 3.0, 0.9));
            } else {
                e = min(MAXV, e + stamp(cell, at, 6.0, 1.4));
            }
        }
    }

    if (hd[3].z > 0.5) {
        e = min(MAXV, e + stamp(cell, floor(hd[4].xy / cwh), 1.0, 0.08));
    }
    return float4(e, heat, 0.0, 0.0);
}

// ---------------------------------------------------------------- cells

// math.ts hash3: integer hash -> [0, 1)
static float hash3(int x, int y, int z) {
    uint h = (uint(x) * 374761393u) ^ (uint(y) * 668265263u) ^ (uint(z) * 1442695041u);
    h = (h ^ (h >> 13u)) * 1274126177u;
    h = h ^ (h >> 16u);
    return float(h) / 4294967296.0;
}

static float ipow(float x, float p) { return pow(max(x, 1e-6), p); }

static float classicHW(float s) {
    if (s < 0.13) { return 0.09 * ipow(sin((s / 0.13) * PI * 0.5), 0.95); }
    if (s < 0.3) { return 0.09 + 0.016 * smoothstep(0.13, 0.3, s); }
    if (s < 0.84) { return 0.019 + 0.087 * ipow(1.0 - (s - 0.3) / 0.54, 1.25); }
    float k = (s - 0.84) / 0.16;
    return 0.019 * (1.0 - k) + 0.012 * sin(k * PI);
}

// Top-down half-width at s (0 snout .. 1 tail) as a fraction of length.
// Kinds: 0 classic, 1 hammerhead, 2 tiger, 3 zebra, 4 greathammer, 5 mako, 6 thresher, 7 nurse.
static float halfWidth(int kind, float s) {
    switch (kind) {
        case 1: {
            if (s < 0.06) { return 0.045; }
            if (s < 0.3) { return 0.045 + 0.061 * smoothstep(0.06, 0.3, s); }
            return classicHW(s) * 0.92;
        }
        case 2: {
            if (s < 0.13) { return 0.1 * ipow(sin((s / 0.13) * PI * 0.5), 0.45); }
            if (s < 0.3) { return 0.1 + 0.014 * smoothstep(0.13, 0.3, s); }
            if (s < 0.84) { return 0.019 + 0.095 * ipow(1.0 - (s - 0.3) / 0.54, 1.2); }
            float k = (s - 0.84) / 0.16;
            return 0.019 * (1.0 - k) + 0.012 * sin(k * PI);
        }
        case 3: {
            if (s < 0.1) { return 0.075 * ipow(sin((s / 0.1) * PI * 0.5), 0.7); }
            if (s < 0.28) { return 0.075 + 0.025 * smoothstep(0.1, 0.28, s); }
            if (s < 0.55) { return 0.022 + 0.078 * ipow(1.0 - (s - 0.28) / 0.27, 1.1); }
            float k = (s - 0.55) / 0.45;
            return 0.022 * (1.0 - k * k) + 0.012 * sin(k * PI);
        }
        case 4: {
            if (s < 0.05) { return 0.04; }
            if (s < 0.3) { return 0.04 + 0.07 * smoothstep(0.05, 0.3, s); }
            return classicHW(s) * 0.95;
        }
        case 5: {
            if (s < 0.17) { return 0.088 * ipow(sin((s / 0.17) * PI * 0.5), 1.5); }
            if (s < 0.32) { return 0.088 + 0.012 * smoothstep(0.17, 0.32, s); }
            if (s < 0.86) { return 0.014 + 0.086 * ipow(1.0 - (s - 0.32) / 0.54, 1.45); }
            float k = (s - 0.86) / 0.14;
            return 0.014 * (1.0 - k) + 0.01 * sin(k * PI);
        }
        case 6: {
            if (s < 0.08) { return 0.07 * ipow(sin((s / 0.08) * PI * 0.5), 0.75); }
            if (s < 0.2) { return 0.07 + 0.02 * smoothstep(0.08, 0.2, s); }
            if (s < 0.48) { return 0.012 + 0.078 * ipow(1.0 - (s - 0.2) / 0.28, 1.3); }
            float k = (s - 0.48) / 0.52;
            return 0.012 * (1.0 - k) + 0.006 * sin(k * PI * 0.9) + 0.002;
        }
        case 7: {
            if (s < 0.08) { return 0.085 * ipow(sin((s / 0.08) * PI * 0.5), 0.4); }
            if (s < 0.3) { return 0.085 + 0.02 * smoothstep(0.08, 0.3, s); }
            if (s < 0.72) { return 0.022 + 0.083 * ipow(1.0 - (s - 0.3) / 0.42, 1.1); }
            float k = (s - 0.72) / 0.28;
            return 0.022 * (1.0 - k * k) + 0.014 * sin(k * PI);
        }
        default: { return classicHW(s); }
    }
}

static bool inTriangle(float2 p, float2 a, float2 b, float2 c) {
    float d1 = (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y);
    float d2 = (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y);
    float d3 = (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y);
    bool neg = d1 < 0.0 || d2 < 0.0 || d3 < 0.0;
    bool pos = d1 > 0.0 || d2 > 0.0 || d3 > 0.0;
    return !(neg && pos);
}

// Tiger bars and zebra-shark spots.
static bool marked(int kind, float s, float v, float L, float across, int id) {
    if (kind == 2) {
        if (s < 0.2 || s > 0.9 || across > 0.85) { return false; }
        float wobble = 0.35 * sin((v / L) * 25.0 + s * 5.0);
        float bar = sin(s * PI * 2.0 * 9.0 + wobble);
        return bar > 0.65 - 0.5 * smoothstep(0.2, 0.42, s) + 0.4 * smoothstep(0.8, 0.9, s);
    }
    if (kind == 3) {
        if (s < 0.07) { return false; }
        float gu = (s * L) / (L * 0.06);
        float gv = v / (L * 0.045);
        float cu = floor(gu);
        float cv = floor(gv);
        float jx = hash3(int(cu), int(cv), id) * 0.5 + 0.25;
        float jy = hash3(int(cu), int(cv), id + 11) * 0.5 + 0.25;
        float dx = gu - cu - jx;
        float dy = gv - cv - jy;
        return dx * dx + dy * dy < 0.08;
    }
    return false;
}

struct Hit {
    bool hit;
    int flag;
    float shade;
    float s;
    float v;
    float dist;
};

// Classify one point against the shark whose record starts at b.
static Hit sampleShark(constant float4* sh, int b, float2 p) {
    float4 P0 = sh[b];
    float4 P1 = sh[b + 1];
    float4 pect = sh[b + 2];
    float4 pelv = sh[b + 3];
    float4 P4 = sh[b + 4];
    float4 P5 = sh[b + 5];
    float4 P6 = sh[b + 6];
    float4 P7 = sh[b + 7];
    float L = P0.x;
    int kind = int(P0.z);
    int id = int(P0.w);
    float arcTotal = max(P1.w, 1.0);

    float best = 1e30;
    float bestS = 0.0;
    float bestSign = 1.0;
    float2 bestN = float2(0.0);
    for (int k = 0; k < NODES - 1; k++) {
        float4 A = sh[b + 8 + k];
        float4 B = sh[b + 9 + k];
        float2 a = A.xy;
        float2 sv = B.xy - a;
        float len2 = dot(sv, sv);
        if (len2 == 0.0) { len2 = 1.0; }
        float t = clamp(dot(p - a, sv) / len2, 0.0, 1.0);
        float2 q = a + sv * t;
        float d2 = dot(p - q, p - q);
        if (d2 < best) {
            best = d2;
            float len = sqrt(len2);
            bestS = (A.z + t * len) / arcTotal;
            bestSign = (sv.x * (p.y - a.y) - sv.y * (p.x - a.x) >= 0.0) ? 1.0 : -1.0;
            bestN = float2(-sv.y / len, sv.x / len) * bestSign;
        }
    }

    Hit h;
    float a = sqrt(best);
    float s = bestS;
    float along = s * L;
    float w = halfWidth(kind, s) * L;
    h.dist = a;
    h.s = s;
    h.v = a * bestSign;
    h.hit = false;
    h.flag = 0;
    h.shade = 0.0;

    // Hammerhead cephalofoil.
    float headSpan = P6.z;
    if (headSpan > 0.0) {
        float sweep = P6.w;
        float depthH = P7.x;
        float notch = P7.y;
        if (along < L * (sweep + depthH + notch)) {
            float span = L * headSpan;
            float r = a / span;
            float front = L * sweep * r * r + L * notch * max(0.0, 1.0 - r / 0.14);
            float depth = L * depthH * (1.0 - 0.2 * r * r * r * r);
            if (r <= 1.0 && along >= front && along <= front + depth) {
                h.hit = true;
                if (r > 0.84) {
                    h.flag = FLAG_EYE;
                    h.shade = 0.0;
                } else {
                    h.flag = FLAG_BODY;
                    h.shade = 0.62 - 0.2 * r + (along < front + L * 0.012 ? 0.1 : 0.0);
                }
                return h;
            }
        }
    }

    if (a <= w) {
        float across = w == 0.0 ? a : a / w;
        // Rounded back lit from the top-left; flanks fall off into shadow.
        float facing = (bestN.x * -0.6 + bestN.y * -0.8) * across;
        float shade = 0.58 - across * across * 0.42 + facing * 0.26;
        int flag = FLAG_BODY;
        float eye0 = P5.z;
        float eye1 = P5.w;
        if (s > P4.z && s < P4.w && across < 0.3) {
            flag = FLAG_RIDGE;
            shade = 1.0;
        } else if (s > P5.x && s < P5.y && across < 0.4) {
            shade = max(shade, 0.82);
        } else if (eye0 >= 0.0 && s > eye0 && s < eye1 && across > 0.6) {
            flag = FLAG_EYE;
            shade = 0.0;
        } else if (s > P6.x && s < P6.y && across > 0.58) {
            // Five gill slits.
            if (int(floor(((s - P6.x) / (P6.y - P6.x)) * 5.0)) % 2 == 0) { shade = shade * 0.45; }
        } else if (s < 0.05) {
            shade = max(shade, 0.7);
        } else if (kind == 3 && s > 0.08 && s < 0.55 && (across < 0.1 || fabs(across - 0.6) < 0.08)) {
            shade = max(shade, 0.8);
        } else if (marked(kind, s, a * bestSign, L, across, id)) {
            flag = FLAG_MARK;
        }
        h.hit = true;
        h.flag = flag;
        h.shade = shade;
        return h;
    }

    float tip = bestSign > 0.0 ? P1.y : P1.x;
    float2 pt = float2(along, a);
    bool inPect = inTriangle(pt, float2(L * pect.x, 0.0), float2(L * pect.y, 0.0), float2(L * pect.z, tip));
    bool notchCut = P4.y > 0.5 && inTriangle(pt, float2(L * pect.y, 0.0),
        float2(L * (pect.y + (pect.z - pect.y) * 0.33), tip * 0.55), float2(L * pect.z, tip));
    if (inPect && !notchCut) {
        h.hit = true;
        h.flag = marked(kind, s, a * bestSign, L, 0.0, id) ? FLAG_MARK : FLAG_FIN;
        h.shade = 0.38 + 0.22 * (1.0 - clamp(a / tip, 0.0, 1.0));
        return h;
    }
    float caudal = P4.x;
    if (inTriangle(pt, float2(L * pelv.x, 0.0), float2(L * pelv.y, 0.0), float2(L * pelv.z, L * pelv.w)) ||
        (caudal > 0.0 && inTriangle(pt, float2(L * 0.86, 0.0), float2(L * 0.95, 0.0), float2(L, L * caudal)))) {
        h.hit = true;
        h.flag = FLAG_FIN;
        h.shade = 0.36;
        return h;
    }
    return h;
}

// Writes r = (flag + 8 * kind) / 255, g = shade, b = body-anchored glyph key / 255, a = depth.
fragment float4 cells_main(VOut in [[stage_in]],
                           constant float4* hd [[buffer(0)]],
                           constant float4* sh [[buffer(1)]],
                           texture2d<float, access::read> fish [[texture(1)]]) {
    float2 cwh = hd[1].xy;
    float time = hd[1].z;
    uint2 cu = uint2(in.clip.xy);
    float2 cellF = float2(cu);
    int c = int(cu.x);
    int r = int(cu.y);
    float2 origin = cellF * cwh;

    int flag = 0;
    int kindOut = 0;
    float shadeOut = 0.0;
    float keyOut = 0.0;
    float depthOut = 0.0;

    int sharkCount = int(hd[3].x);
    for (int i = 0; i < sharkCount; i++) {
        int b = i * STRIDE;
        float4 bb = sh[b + 28];
        if (origin.x + cwh.x < bb.x || origin.x > bb.z || origin.y + cwh.y < bb.y || origin.y > bb.w) { continue; }
        float L = sh[b].x;
        float skipBeyond = L * 0.36 + length(cwh);
        Hit center = sampleShark(sh, b, origin + cwh * 0.5);
        if (!center.hit && center.dist > skipBeyond) { continue; }
        int hits = center.hit ? 1 : 0;
        if (sampleShark(sh, b, origin + cwh * float2(0.25, 0.3)).hit) { hits++; }
        if (sampleShark(sh, b, origin + cwh * float2(0.75, 0.3)).hit) { hits++; }
        if (sampleShark(sh, b, origin + cwh * float2(0.25, 0.72)).hit) { hits++; }
        if (sampleShark(sh, b, origin + cwh * float2(0.75, 0.72)).hit) { hits++; }
        if (hits == 0) { continue; }
        float coverage = float(hits) / 5.0;

        int id = int(sh[b].w);
        // Body-anchored key so each glyph rides along with the skin.
        keyOut = floor(hash3(int(round(center.s * 52.0)), int(round(center.v / (cwh.x * 0.9))), id) * 256.0);
        depthOut = sh[b].y;
        kindOut = int(sh[b].z);
        if (center.hit && coverage >= 0.6) {
            flag = center.flag;
            float flicker = (hash3(c, r, int(floor(time * 6.0))) - 0.5) * 0.06;
            shadeOut = clamp(center.shade + flicker, 0.0, 1.0);
        } else {
            flag = FLAG_EDGE;
            shadeOut = coverage;
        }
    }

    // Fish: one per cell, never on a shark. The CPU already picked which.
    if (flag == 0) {
        float4 f = fish.read(cu);
        if (f.r > 0.5) {
            flag = FLAG_FISH;
            shadeOut = clamp(f.g, 0.0, 1.0);
        }
    }
    return float4(float(flag + 8 * kindOut) / 255.0, shadeOut, keyOut / 255.0, depthOut);
}

// ---------------------------------------------------------------- compose
// Glyph atlas order: 0 :  1 ;  2 t  3 %  4 S  5 X  6 8  7 #  8 @  9 .  10 '  11 ,  12 `  13 o  14 -  15 *  16 ·

constant int G_EYE = 13;
constant int G_DASH = 14;
constant int G_STAR = 15;
constant int G_MIDDOT = 16;

static uint hashU(uint x) {
    uint h = x * 374761393u + 668265263u;
    h = (h ^ (h >> 13u)) * 1274126177u;
    return h ^ (h >> 16u);
}

static float hash2(uint a, uint b) {
    uint h = (a * 374761393u) ^ (b * 668265263u) ^ (7u * 1442695041u);
    h = (h ^ (h >> 13u)) * 1274126177u;
    h = h ^ (h >> 16u);
    return float(h) / 4294967296.0;
}

static int finGlyph(uint i) {
    switch (i) { case 0u: return 3; case 1u: return 1; case 2u: return 2; case 3u: return 4; default: return 0; }
}
static int ridgeGlyph(uint i) {
    switch (i) { case 0u: return 8; case 1u: return 6; default: return 3; }
}
static int markGlyph(uint i) {
    switch (i) { case 0u: return 7; case 1u: return 3; default: return 8; }
}

static float3 accent(uint i) {
    switch (i) {
        case 0u: return float3(224.0, 137.0, 44.0) / 255.0;
        case 1u: return float3(224.0, 58.0, 50.0) / 255.0;
        case 2u: return float3(180.0, 74.0, 224.0) / 255.0;
        case 3u: return float3(51.0, 200.0, 204.0) / 255.0;
        case 4u: return float3(60.0, 181.0, 74.0) / 255.0;
        case 5u: return float3(49.0, 80.0, 232.0) / 255.0;
        default: return float3(217.0, 193.0, 74.0) / 255.0;
    }
}

// Skin tint per species (r, g, b multipliers).
static float3 tint(int kind) {
    switch (kind) {
        case 1: return float3(0.96, 0.98, 0.9);
        case 2: return float3(1.02, 0.95, 0.84);
        case 3: return float3(1.08, 0.97, 0.74);
        case 4: return float3(0.86, 0.93, 1.02);
        case 5: return float3(0.78, 0.9, 1.2);
        case 6: return float3(1.0, 0.9, 1.08);
        case 7: return float3(1.1, 0.96, 0.76);
        default: return float3(0.92, 0.97, 1.05);
    }
}

// Glyph coverage at a device-pixel offset inside the cell. The atlas was
// built with whole-pixel slots (GlyphAtlas rounds cell * scale), so index it
// by the rounded slot: at fractional scales the cell is a fraction wider.
static float glyph(texture2d<float, access::read> atlas, int g, float2 lp, float2 slot) {
    float2 a = round(slot);
    float2 q = min(floor(lp), a - 1.0);
    uint2 p = uint2(uint(float(g) * a.x + q.x), uint(q.y));
    return atlas.read(p).r;
}

fragment float4 compose_main(VOut in [[stage_in]],
                             constant float4* hd [[buffer(0)]],
                             texture2d<float, access::read> cells [[texture(0)]],
                             texture2d<float, access::read> wake [[texture(1)]],
                             texture2d<float, access::read> atlas [[texture(2)]]) {
    float2 grid = hd[0].zw;
    float2 cwh = hd[1].xy;
    float time = hd[1].z;
    float res = hd[2].z;
    float4 theme = hd[5];
    float3 wakeColor = hd[6].rgb;
    float accentRate = theme.z;
    float2 px = in.clip.xy;                          // device pixels (centres)
    float2 pt = px / res;                            // points
    float2 cellF = min(floor(pt / cwh), grid - float2(1.0));
    float2 slot = cwh * res;                         // cell size in device pixels
    float2 lp = px - cellF * slot;                   // device pixels inside the cell
    float2 lpt = pt - cellF * cwh;                   // points inside the cell
    uint2 cu = uint2(cellF);

    float3 col = float3(0.0);

    // Grid: one device pixel, white at 5.5%.
    if (theme.w > 0.5 && (floor(px.x) == round(cellF.x * slot.x) || floor(px.y) == round(cellF.y * slot.y))) {
        col = float3(0.055);
    }

    float4 ci = cells.read(cu);
    int packed = int(round(ci.r * 255.0));
    int flag = packed % 8;
    int kind = packed / 8;
    float shade = ci.g;
    uint K = hashU(uint(round(ci.b * 255.0)));
    float depth = ci.a;

    float2 w = wake.read(cu).rg;
    float e = w.r;
    float heat = w.g;

    // Wake dots: squares low-right in empty cells.
    if (flag == 0 && e > 0.45) {
        float level = clamp(floor((e - 0.45) * 5.0), 0.0, 5.0);
        float size = max(2.0, round(cwh.x * 0.19)) + 1.0;
        float2 d0 = round(cellF * cwh + cwh * float2(0.66, 0.64) - float2(size * 0.5)) - cellF * cwh;
        if (lpt.x >= d0.x && lpt.x < d0.x + size && lpt.y >= d0.y && lpt.y < d0.y + size) {
            col = mix(col, wakeColor, (level + 1.0) / 6.0);
        }
    }

    // Heat: where a fish was just eaten.
    if (heat >= 0.08) {
        int g = heat > 0.6 ? G_STAR : G_MIDDOT;
        float3 hc = float3(220.0, 40.0, 40.0) / 255.0;
        float ha = min(1.0, heat * 1.6);
        if (heat > 0.5) {
            hc = float3(255.0, 120.0, 60.0) / 255.0;
            ha = min(1.0, heat);
        }
        col = mix(col, hc, glyph(atlas, g, lp, slot) * ha);
    }

    // Fish: a dash, brighter when near, turning or panicking.
    if (flag == FLAG_FISH) {
        int bucket = clamp(int(floor(shade * 5.0)), 0, 4);
        float a = 0.28;
        switch (bucket) { case 1: a = 0.42; break; case 2: a = 0.58; break; case 3: a = 0.74; break; case 4: a = 0.9; break; default: break; }
        col = mix(col, float3(230.0, 238.0, 255.0) / 255.0, glyph(atlas, G_DASH, lp, slot) * a);
    }

    if (flag >= 1 && flag <= 6) {
        float3 tn = tint(kind);
        float dim = 0.7 + 0.3 * depth;
        // Colours re-roll on a staggered clock so the hide shimmers.
        uint tick = uint(floor(time * 2.4 + float(K % 997u) / 97.0));
        float roll = hash2(K, tick);

        if (flag == FLAG_EDGE) {
            // Soft silhouette edge: no block, just a light glyph.
            int g = shade >= 0.5 ? int((K >> 8u) % 2u) : 9 + int((K >> 8u) % 4u);
            float lv = (70.0 + shade * 80.0) * dim;
            float3 gc = float3(lv * tn.x, lv * tn.y, min(255.0, lv * tn.z + 6.0)) / 255.0;
            if (roll < 0.07 * accentRate) { gc = accent(K % 7u); }
            col = mix(col, gc, glyph(atlas, g, lp, slot));
        } else {
            float level = 0.0;
            int g = 0;
            if (flag == FLAG_RIDGE) {
                level = 226.0;
                g = ridgeGlyph((K >> 8u) % 3u);
            } else if (flag == FLAG_EYE) {
                level = 12.0;
                g = G_EYE;
            } else if (flag == FLAG_MARK) {
                level = 24.0 + shade * 22.0;
                g = markGlyph((K >> 8u) % 3u);
            } else if (flag == FLAG_FIN) {
                level = 40.0 + shade * 120.0;
                g = finGlyph((K >> 8u) % 5u);
            } else {
                level = 46.0 + shade * 160.0;
                int jitter = int((K >> 4u) % 3u) - 1;
                g = clamp(int(floor((1.0 - shade) * 8.99)) + jitter, 0, 8);
            }
            level = level * dim;
            // Block, inset one point from the top-left grid lines.
            if (lpt.x >= 1.0 && lpt.y >= 1.0) {
                col = min(float3(255.0), float3(level * tn.x, level * tn.y, level * tn.z + 4.0)) / 255.0;
            }
            float3 gc = float3(0.0);
            if (flag == FLAG_EYE) {
                gc = float3(154.0, 160.0, 173.0) / 255.0;
            } else if (flag == FLAG_MARK) {
                gc = float3(70.0 * tn.x, 70.0 * tn.y, 70.0 * tn.z) / 255.0;
            } else if (roll < 0.09 * accentRate) {
                gc = accent(K % 7u);
            } else if (roll < 0.13 * accentRate) {
                gc = float3(1.0);
            } else if (shade > 0.55) {
                gc = float3(14.0, 15.0, 19.0) / 255.0;
            } else {
                gc = float3(27.0, 29.0, 36.0) / 255.0;
            }
            col = mix(col, gc, glyph(atlas, g, lp, slot));
        }
    }

    col *= theme.y;
    if (theme.x > 0.5) {
        // Light: invert lightness, keep hue.
        float y = dot(col, float3(0.2126, 0.7152, 0.0722));
        col = clamp(col + (1.0 - 2.0 * y), 0.0, 1.0);
    }
    return float4(col, 1.0);
}
"""#
}
