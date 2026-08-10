# Custom Blocks

Use a namespaced `AgentBlockKind` such as `company.calendar.event` and carry portable data in a
`CustomBlock` JSON payload. Register an `AgentBlockRenderer` in a scene-local registry. Unknown kinds
use the generic renderer and remain visible; Core and UIKit never require changes for a new tool.
