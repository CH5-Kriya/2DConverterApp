#include "relief_numerics.h"

#include <algorithm>
#include <cstdio>
#include <vector>

// Forstmann's simplifier keeps its state in namespace-level globals, so it is
// included exactly once, here, and never exposed beyond this file.
#include "vendor/Simplify.h"

size_t relief_decimate(const double *vertices, const int32_t *faces,
                       size_t vertex_count, size_t face_count,
                       size_t target_faces, double aggressiveness,
                       double *out_vertices, int32_t *out_faces,
                       size_t *out_vertex_count) {
    Simplify::vertices.clear();
    Simplify::triangles.clear();
    Simplify::vertices.resize(vertex_count);
    Simplify::triangles.resize(face_count);

    for (size_t i = 0; i < vertex_count; ++i)
        Simplify::vertices[i].p = vec3f(vertices[i * 3 + 0], vertices[i * 3 + 1],
                                        vertices[i * 3 + 2]);
    for (size_t i = 0; i < face_count; ++i) {
        Simplify::triangles[i].v[0] = faces[i * 3 + 0];
        Simplify::triangles[i].v[1] = faces[i * 3 + 1];
        Simplify::triangles[i].v[2] = faces[i * 3 + 2];
    }

    Simplify::simplify_mesh(static_cast<int>(target_faces), aggressiveness, false);

    // The simplifier leaves deleted vertices in place; compact them.
    std::vector<int32_t> remap(Simplify::vertices.size(), -1);
    size_t nv = 0;
    for (size_t i = 0; i < Simplify::triangles.size(); ++i)
        for (int k = 0; k < 3; ++k) {
            const int v = Simplify::triangles[i].v[k];
            if (remap[v] < 0) {
                remap[v] = static_cast<int32_t>(nv);
                out_vertices[nv * 3 + 0] = Simplify::vertices[v].p.x;
                out_vertices[nv * 3 + 1] = Simplify::vertices[v].p.y;
                out_vertices[nv * 3 + 2] = Simplify::vertices[v].p.z;
                ++nv;
            }
        }
    for (size_t i = 0; i < Simplify::triangles.size(); ++i)
        for (int k = 0; k < 3; ++k)
            out_faces[i * 3 + k] = remap[Simplify::triangles[i].v[k]];

    *out_vertex_count = nv;
    return Simplify::triangles.size();
}
