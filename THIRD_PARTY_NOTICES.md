# OpenUI reference attribution

This native example reproduces the weather dashboard shown in Thesys OpenUI's public demo, with fixture data transcribed from visible frames. It does not embed or execute the upstream renderer or language.

- Reference: https://github.com/thesysdev/openui/raw/main/assets/demo.gif
- Source snapshot inspected: commit `99888a5b15c1ac8d9f6c5c948fb1d905aae9e9b3`
- Corresponding example page: https://www.openui.com/openui-vs-json
- Page/source components: `docs/app/openui-vs-json/page.tsx`, `docs/app/demos/constants.ts`, `docs/app/demos/components/CodePanel/CodePanel.css`, `docs/app/demos/components/PreviewPanel/PreviewPanel.tsx` and `.css`.
- The source page submits the Weather dashboard prompt to `/api/playground/stream`, incrementally displays output, renders a preview, and provides copy/expand controls. The exact weather response in the GIF is generated content; a matching static dataset was not found in the inspected main-tree example definitions.

The GIF and small upstream source excerpts are retained in `reference/` solely for inspection/provenance, are not included in the app resources, and are covered by the upstream MIT notice reproduced in `reference/OPENUI-LICENSE`.

Copyright (c) 2011-2024 Thesys Inc. See the full permission and warranty terms in that license file.
