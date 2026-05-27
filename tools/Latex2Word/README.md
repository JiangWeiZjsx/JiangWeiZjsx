目前仅适配 Windows 环境，且word为通用模板，不适配特定的论文模板（仅作交流使用，不适合投稿）。

# 安装环境
Pandoc, pandoc-crossref

## 所需辅助文件

- export_docx.ps1
- pandoc_docx_fix.lua
- postprocess_docx.py
- template.docx


# 使用方法
```bash
powershell -ExecutionPolicy Bypass -File .\export_docx.ps1 .\docs\manuscripts\Root_Cause_Analysis.tex
```
