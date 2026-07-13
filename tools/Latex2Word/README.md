# LaTeX → Word 文档转换

## 转换管道

```
export_docx.ps1 (主脚本)
  ├── 1. Pandoc         — LaTeX → 原始 .docx
  ├── 2. Lua 过滤器     — pandoc_docx_fix.lua（引用、算法、公式编号）
  ├── 3. Python 后处理  — postprocess_docx.py（三线表、公式排版、修订标记着色）
  └── 4. 模板           — template.docx（Word 样式参考文档）
```

## 环境依赖

| 工具                             | 最低版本 | 用途                                   |
| -------------------------------- | -------- | -------------------------------------- |
| [Pandoc](https://pandoc.org/)     | 3.x      | LaTeX → DOCX 核心转换                 |
| [Python](https://www.python.org/) | 3.9+     | DOCX 后处理（表格、公式、修订）        |
| template.docx                    | —       | Word 样式模板（仓库自带）              |
| CSL 文件                         | —       | 参考文献格式（可选，默认`ieee.csl`） |

## 快速开始

```powershell
# 在项目根目录执行
powershell -ExecutionPolicy Bypass -File .\export_docx.ps1 <tex文件路径>
```

## 参数说明

| 参数                  | 类型         | 说明                                                                                       |
| --------------------- | ------------ | ------------------------------------------------------------------------------------------ |
| `TexPath`           | `string`   | **必填**，`.tex` 文件路径（支持相对/绝对路径）                                     |
| `-OutputPath`       | `string`   | 输出`.docx` 路径，默认在 `.tex` 同目录下生成同名文件                                   |
| `-TemplatePath`     | `string`   | 自定义模板路径，默认`template.docx`                                                      |
| `-BibliographyPath` | `string[]` | 指定`.bib` 文件，可传多个；不传则自动从 `\bibliography{}` / `\addbibresource{}` 提取 |
| `-CslPath`          | `string`   | CSL 引用样式文件路径                                                                       |
| `-IncludeToc`       | `switch`   | 是否生成目录                                                                               |

## 使用示例

```powershell
# 基础转换（自动识别 .bib，输出到同目录）
powershell -ExecutionPolicy Bypass -File .\export_docx.ps1 .\IEEE_TII\main.tex

# 指定输出路径
powershell -ExecutionPolicy Bypass -File .\export_docx.ps1 .\IEEE_TII\main.tex -OutputPath .\output.docx

# 带目录
powershell -ExecutionPolicy Bypass -File .\export_docx.ps1 .\IEEE_TII\main.tex -IncludeToc

# 完整参数
powershell -ExecutionPolicy Bypass -File .\export_docx.ps1 .\IEEE_TII\main.tex `
  -OutputPath .\IEEE_TII\main_final.docx `
  -IncludeToc `
  -BibliographyPath .\IEEE_TII\ref.bib
```

## 脚本默认行为

- 若不传 `-OutputPath`，在 `.tex` 同目录生成同名 `.docx`
- 默认不生成目录
- 参考文献自动从 `\bibliography{...}` / `\addbibresource{...}` 识别
- 输出文件被 Word 占用时会报错提示关闭