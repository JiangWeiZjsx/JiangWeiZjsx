
# 论文写作

* **Latex** 实现论文格式编写，众多期刊均提供 Latex 和 Word 格式模板。
* **Pandoc** 实现格式转换，支持 Latex 导出为 docx 等格式，便于他人审阅修改。（注意：格式转换可能存在兼容性问题）
* **Markdown** 适用于日常笔记记录，语法简洁，原生支持图片、公式和代码块。Github 等平台均支持 Markdown，便于笔记分享。


# Latex

## 通用排版

* 目录
```latex
% 目录（自动生成）
\clearpage
\renewcommand{\contentsname}{目录} % 修改目录标题为“目录”
\setcounter{tocdepth}{3} % 目录深度：1=节，2=小节
\phantomsection % 使 hyperref 定位正确
\tableofcontents
```
* 代码显示
```latex
\usepackage{listings} % 支持代码块插入

\lstset{
    language=Python,          % 默认语言
    basicstyle=\footnotesize\ttfamily, % 代码字体和大小
    numbers=left,             % 在左侧显示行号
    numberstyle=\tiny\color{codenumbergray}, % 行号样式
    frame=single,             % 给代码块添加边框
    framesep=4pt,             % 边框和代码的距离
    tabsize=4,                % Tab 键占用的空格数
    showstringspaces=false,
    commentstyle=\color{codegray}\ttfamily, % 注释颜色（不使用斜体以避免中文斜体缺失）
    keywordstyle=\color{blue}\bfseries, % 关键词颜色和加粗
    stringstyle=\color{orange},
    breaklines=true,
    captionpos=b,             % 标题位置在底部
    rulecolor=\color{black},
}

\begin{lstlisting}[caption={代码示意}, language=Python, label=lst:grangerFunc]
    # 代码内容
\end{lstlisting}
```
> 注意：代码样式会对全文的行号样式进行修改，导致代码框的行号出现数字错乱的现象。

> 注意：很少在论文中使用，适用笔记。笔记使用 Markdown 语法会更好。

## 兼容中文
使用中文需要使用 xelate 编译器，传统 pdflatex 无法编译。因此，个开头需要声明 ```ctexart```。适用于笔记、国内论文格式等场景。

```latex
\documentclass[12pt,a4paper,quiet]{ctexart}
\setlength{\marginparwidth}{2cm} % 确保待办事项和类似包的页边距足够宽

% 常规A4文章的排版格式
\usepackage[
    a4paper,
    top=2.54cm,
    bottom=2.54cm,
    left=3.17cm,
    right=2.54cm,
    headheight=0.8cm,
    headsep=0.4cm,
]{geometry}
```
## Latex 制作PPT

> 注意: Latex只能导出```pdf```格式，非```pptx```格式。


# Pandoc
将 Latex 文件转为所需文件，以下以 tex -> word 为例。

```shell
pandoc file_name.tex --citeproc --bibliography=ref.bib --csl=Ref/reference.csl
--metadata=link-citations:true --reference-doc=Ref/reference.docx -o out.docx
```

> `cls`, `docx` 文件见 `pandoc/Ref` 文件夹。`bib` 文件为文献，可用 `zotero` 等其他文件管理工具直接导出。

