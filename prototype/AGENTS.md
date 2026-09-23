# Prototype Instructions

## MacPower design decisions

- 用户已选择方案 1，视觉目标为 `../design/concept-01.png` 与深色版本 `../design/concept-01-dark.png`，保留电源分向整机与电池的布局。
- 外观必须提供“跟随系统 / 浅色 / 深色”，默认跟随系统；手动主题保存且不被系统变化覆盖。
- 此目录仅是中文交互原型，所有读数标为示例，不声称连接了设备或控制了 macOS。

Run the local server yourself and open the preview in the browser available to this environment. Do not give the user server-start instructions when you can run it.

Before making substantial visual changes, use the Product Design plugin's `get-context` skill when the visual source is unclear or no longer matches the current goal. When the user gives durable prototype-specific design feedback, preferences, or decisions, record them in `AGENTS.md`.

When implementing from a selected generated mock, treat that image as the source of truth for layout, component anatomy, density, spacing, color, typography, visible content, and hierarchy.

Build app UI in `src/`. Keep `.openai/hosting.json`, `worker/index.js`, `scripts/prepare-sites-build.mjs`, and `tests/sites-worker.test.mjs` intact so the same local prototype can be handed to Sites. Before a Sites handoff, run `npm run build` and `npm run test:sites`; the build must leave `dist/client/index.html`, `dist/server/index.js`, and `dist/.openai/hosting.json`.
