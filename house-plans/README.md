# House Plans

Living documentation of the house layout, traced from the original 1 ft-grid
paper drawing (`floorplan_reference.jpg`).

## Files

| File | Role |
|------|------|
| `Main-floor.dxf` | **Source of truth.** Edit in QCAD (Community) or via ezdxf. |
| `Main-floor-traced.svg` | Export artifact for styling (Affinity) / HA dashboards. Regenerated from the DXF, not hand-edited. |
| `Main-floor.afpub` | Affinity Publisher styling document. |
| `floorplan_reference.jpg` | Photo of the original paper drawing (provenance). |

## Conventions

- **DXF**: 1 drawing unit = 1 foot, y-up, origin at the SW exterior corner.
  Plan footprint is 43 × 33 ft.
- **SVG**: 1 ft = 10 mm, y-down, origin at the NW exterior corner.
- Walls are drawn as centerlines; lineweights carry the visual thickness
  (0.5 mm exterior, 0.35 mm interior).
- Layers: `WALLS-EXTERIOR`, `WALLS-INTERIOR`, `OPENINGS`, `STAIRS`, `PORCH`,
  `FIXTURES`, `CABINETS`, `DIMENSIONS`. Building systems get their own layers
  as they're mapped (`ELECTRICAL`, `PLUMBING`, `HVAC`).
