# Vendored: `Simplify.h`

Sven Forstmann's *Fast-Quadric-Mesh-Simplification*, MIT licensed.
Source: https://github.com/sp4cerat/Fast-Quadric-Mesh-Simplification

This is vendored rather than reimplemented because the reference pipeline
reaches the same algorithm: `trimesh.simplify_quadric_decimation` is, in its own
words, "a thin wrapper around `pip install fast-simplification`", and
`fast-simplification` is a Cython wrapper around this code.

A *different* quadric simplifier would give a different mesh. Quadric error
collapses flat regions hard and leaves detailed ones dense — the back plate and
background cost almost nothing while faces and drapery keep their triangles —
and the exact sequence of edge collapses is what determines where those
triangles land.

Note `fast-simplification` has diverged from upstream since forking, so this is
"the same algorithm", not "provably the same collapses". Stage 6 is therefore
judged on mesh volume (≤ 0.01%) and on watertightness plus body count being
exact, rather than on vertex-for-vertex identity.
