# MacPower 视觉探索

日期：2026-09-23。工具：内置 Image Gen。所有画面都标有“示例数据”。用户已选择**方案 1 · Power Path**，并要求支持深色、浅色和跟随系统。

编号依据三张生成图片在本次对话中的实际展示顺序，生成后才确定。以下三个文件对应同一次视觉探索；后续选择应使用此映射。

| 展示编号 | 文件 | 内部方向标识 |
|---|---|---|
| 1 | [concept-01.png](../design/concept-01.png) | Power Path |
| 2 | [concept-02.png](../design/concept-02.png) | Power Ledger |
| 3 | [concept-03.png](../design/concept-03.png) | Daily Battery |

概念 1 以能量流向组织功率；概念 2 以对齐读数与曲线比较组织信息；概念 3 以电池状态和当前充放电组织日常查看。三者共享指标契约，代表不同信息层级与视觉方向，不是同一产品的三个页面。

## 参考与生成记录

生成时附带了已查看的 [ChargeWatch 浅色界面](https://github.com/TY-teo/ChargeWatching/blob/main/picture/charge-limit-redesign-light.png)，仅作为原生电源工具的领域参考。没有照搬其充电控制功能和卡片网格。

完整提示词见 [image-prompts.md](image-prompts.md)。图片已复制到项目 design 目录；原始生成文件保留在 Codex 默认输出位置。

设计图中的曲线、估计时间和取整读数用于展示，不代表当前实时设备读数。像素尺寸由生成工具输出，真实应用按交互规格中的逻辑点尺寸实现。

## 交付边界

选定方案 1 后，补充了 [深色参考稿](../design/concept-01-dark.png) 与 `prototype/` 可交互原型，覆盖实时、趋势、健康、设置、指标说明和七种供电/数据状态。浅深色采用同一布局和指标含义。

[外观规格](appearance.md) 定义三态主题、保存和系统同步；[设计验收](../design-qa.md) 留存实际页面与参考图的对照。当前原型运行于本地预览，所有数值和曲线为示例，尚未接入原生采集，也没有可安装的 .app。
