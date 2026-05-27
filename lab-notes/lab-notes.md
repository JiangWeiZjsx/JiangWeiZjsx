# 研究笔记 (Research Notes)

- 📚 **[componets](./componets/)**：相关辅助配置文件
- 📝 **[lab-docker](./lab-code.md)**：docker 配置教程
- 🧪 **[OpenFoam](./OpenFoam/)**：OpenFOAM 相关实验与笔记

# 研究工具

- 绘图软件
    - **Affinity**：适合绘制流程图、框架图及其他矢量图形，可导出 `eps` 或 `png` 格式。

- 文献管理
    - **Zotero**：免费开源文献管理软件，支持插件扩展。
    - 常用插件：
        - *Better BibTeX for Zotero*：导出 `BibTeX` 格式。
        - *Translate for Zotero*：文献标题与摘要翻译。
        - *Ethereal Style*：补充期刊信息展示。
        - *GB/T 7714 参考文献样式*：见 `./lab-paper/zotero/`。

- 图片管理
    - **Eagle**：用于收集和整理实验结果图、流程图等素材，便于后续复用。

- 代码开发
    - **VS Code**：通用代码编辑器，支持多数常见编程语言。
    - **Docker**：用于统一开发与运行环境。

- 论文写作
    - **LaTeX**：用于学术排版与版本管理。
    - **Word**：用于协作初稿与审阅场景。

# 研究工作流

## 本地配置

- **编程环境管理**
    - Ubuntu 作为编译与运行环境，Windows 作为开发与管理端：
    ```mermaid
            graph LR
                    A["VS Code (Windows)"] -->|SFTP| B["Ubuntu 服务器"]
                    B -->|Docker| C["运行代码"]
                    C -->|Results| D["结果分析"]
    ```

    - Windows 作为主要开发机器（无服务器）：
    ```mermaid
            graph LR
                    A["VS Code (Windows)"] -->|Docker| C["本地运行 (Docker/Windows)"]
                    C -->|Results| D["结果分析"]
    ```

    > 除了 `Docker`，也可使用 `Conda` 或本地安装依赖。若希望提升环境一致性与可迁移性，推荐优先使用 `Docker`。

- **笔记与论文管理**
    - 笔记：使用 `Markdown`，配合 `Obsidian` 管理；不足是文献引用插入相对繁琐。
    - 论文：建议使用 `LaTeX` 作为正式稿件格式。

## 协作配置

- 论文协作写作
    - PDF 路线：LaTeX 草稿 → PDF（或 `.tex`）→ 反馈 → 修订 → LaTeX 正式版。
    - Word 路线：Word 草稿 → PDF（或 `.docx`）→ 反馈 → 修订 → 转为 LaTeX 正式版。

- 演示报告
    - 根据场景选择 PDF 或 PPT 版本。

- **协作建议**
    - **图片**：优先使用 `eps` 或 `png`。尺寸建议按 A4 页面控制，图中文字大小与正文保持一致。
    - **文献**：使用可导出 `bib` 的工具（如 Zotero），便于统一管理。
    - **代码**：使用 `Docker` 管理环境，便于迁移、复现与开源。
    - **非正式汇报**：组会、讨论等场景使用 PDF 展示即可。
    - **论文交付**：建议同时提供 `tex` 源文件与 PDF；如有需要可附 Word 版本。

