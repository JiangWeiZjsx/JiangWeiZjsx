from __future__ import annotations

import copy
import re
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


NS = {
    "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    "m": "http://schemas.openxmlformats.org/officeDocument/2006/math",
}

XML_SPACE = "{http://www.w3.org/XML/1998/namespace}space"
START_MARKER = "CODXADDSTART"
END_MARKER = "CODXADDEND"
ALGORITHM_START_MARKER = "CODXALGSTART"
ALGORITHM_END_MARKER = "CODXALGEND"
SYMBOL_MATH_CHARS = set(" ★☆✓✔✗✘✕✖×")
ALGORITHM_TITLE_RE = re.compile(r"^Algorithm\s+\d+([.:]|\s)")

for prefix, uri in NS.items():
    ET.register_namespace(prefix, uri)


def qn(prefix: str, tag: str) -> str:
    return f"{{{NS[prefix]}}}{tag}"


def ensure_child(parent: ET.Element, tag: str) -> ET.Element:
    child = parent.find(tag)
    if child is None:
        child = ET.Element(tag)
        parent.append(child)
    return child


def paragraph_style(paragraph: ET.Element) -> str | None:
    p_pr = paragraph.find("w:pPr", NS)
    if p_pr is None:
        return None
    style = p_pr.find("w:pStyle", NS)
    if style is None:
        return None
    return style.attrib.get(qn("w", "val"))


def set_paragraph_style(paragraph: ET.Element, style: str) -> None:
    p_pr = ensure_child(paragraph, qn("w", "pPr"))
    p_style = p_pr.find("w:pStyle", NS)
    if p_style is None:
        p_style = ET.SubElement(p_pr, qn("w", "pStyle"))
    p_style.attrib[qn("w", "val")] = style


def paragraph_text(paragraph: ET.Element) -> str:
    parts: list[str] = []
    for text_node in paragraph.findall(".//w:t", NS):
        parts.append(text_node.text or "")
    for math_text in paragraph.findall(".//m:t", NS):
        parts.append(math_text.text or "")
    return "".join(parts).strip()


def make_run(text: str) -> ET.Element:
    run = ET.Element(qn("w", "r"))
    text_node = ET.SubElement(run, qn("w", "t"))
    text_node.attrib[XML_SPACE] = "preserve"
    text_node.text = text
    return run


def make_symbol_run(text: str) -> ET.Element:
    run = make_run(text)
    r_pr = ensure_child(run, qn("w", "rPr"))
    r_fonts = r_pr.find("w:rFonts", NS)
    if r_fonts is None:
        r_fonts = ET.SubElement(r_pr, qn("w", "rFonts"))

    # Use a symbol-capable font so Word renders these markers reliably.
    for attr in ("ascii", "hAnsi", "eastAsia", "cs"):
        r_fonts.attrib[qn("w", attr)] = "Segoe UI Symbol"

    return run


def run_text(run: ET.Element) -> str:
    return "".join(text_node.text or "" for text_node in run.findall(".//w:t", NS))


def apply_red_to_word_run(run: ET.Element) -> None:
    r_pr = ensure_child(run, qn("w", "rPr"))
    color = r_pr.find("w:color", NS)
    if color is None:
        color = ET.SubElement(r_pr, qn("w", "color"))
    color.attrib[qn("w", "val")] = "FF0000"


def apply_red_to_math(math_element: ET.Element) -> None:
    for text_node in math_element.findall(".//m:t", NS):
        text_node.text = text_node.text

    for math_run in math_element.findall(".//m:r", NS):
        math_r_pr = math_run.find("m:rPr", NS)
        if math_r_pr is None:
            math_r_pr = ET.Element(qn("m", "rPr"))
            math_run.insert(0, math_r_pr)

        ctrl_pr = math_r_pr.find("w:rPr", NS)
        if ctrl_pr is None:
            ctrl_pr = ET.SubElement(math_r_pr, qn("w", "rPr"))

        color = ctrl_pr.find("w:color", NS)
        if color is None:
            color = ET.SubElement(ctrl_pr, qn("w", "color"))
        color.attrib[qn("w", "val")] = "FF0000"


def math_text(math_element: ET.Element) -> str:
    parts: list[str] = []
    for text_node in math_element.findall(".//m:t", NS):
        parts.append(text_node.text or "")
    return "".join(parts)


def is_symbol_only_math(math_element: ET.Element) -> bool:
    text = math_text(math_element)
    return bool(text.strip()) and all(char in SYMBOL_MATH_CHARS for char in text)


def replace_symbol_only_math(paragraph: ET.Element) -> None:
    children = list(paragraph)
    for index, child in enumerate(children):
        if child.tag != qn("m", "oMath"):
            continue
        if not is_symbol_only_math(child):
            continue

        paragraph.remove(child)
        paragraph.insert(index, make_symbol_run(math_text(child)))


def prepend_caption_prefix(paragraph: ET.Element, prefix: str) -> None:
    p_pr = paragraph.find("w:pPr", NS)
    insert_at = 1 if p_pr is not None else 0
    paragraph.insert(insert_at, make_run(prefix))


def set_paragraph_alignment(paragraph: ET.Element, align: str) -> None:
    p_pr = ensure_child(paragraph, qn("w", "pPr"))
    jc = p_pr.find("w:jc", NS)
    if jc is None:
        jc = ET.SubElement(p_pr, qn("w", "jc"))
    jc.attrib[qn("w", "val")] = align


def center_document_title(body: ET.Element) -> None:
    for child in body:
        if child.tag != qn("w", "p"):
            continue
        if not paragraph_text(child):
            continue
        set_paragraph_alignment(child, "center")
        return


def clear_paragraph_indentation(paragraph: ET.Element) -> None:
    p_pr = ensure_child(paragraph, qn("w", "pPr"))
    ind = p_pr.find("w:ind", NS)
    if ind is None:
        ind = ET.SubElement(p_pr, qn("w", "ind"))

    for attr in ("left", "right", "firstLine", "firstLineChars", "hanging", "hangingChars"):
        ind.attrib[qn("w", attr)] = "0"


def normalize_table_paragraph(paragraph: ET.Element) -> None:
    set_paragraph_alignment(paragraph, "left")
    clear_paragraph_indentation(paragraph)


def make_styled_paragraph(text: str, style: str) -> ET.Element:
    paragraph = ET.Element(qn("w", "p"))
    p_pr = ET.SubElement(paragraph, qn("w", "pPr"))
    p_style = ET.SubElement(p_pr, qn("w", "pStyle"))
    p_style.attrib[qn("w", "val")] = style
    paragraph.append(make_run(text))
    return paragraph


def color_added_segments(paragraph: ET.Element) -> None:
    in_added = False
    for child in list(paragraph):
        if child.tag == qn("w", "r"):
            text = run_text(child)
            if text == START_MARKER:
                paragraph.remove(child)
                in_added = True
                continue
            if text == END_MARKER:
                paragraph.remove(child)
                in_added = False
                continue
            if in_added:
                apply_red_to_word_run(child)
        elif child.tag == qn("w", "hyperlink"):
            if in_added:
                for run in child.findall(".//w:r", NS):
                    apply_red_to_word_run(run)
        elif child.tag == qn("m", "oMath"):
            if in_added:
                apply_red_to_math(child)


def clear_tc_borders(tc_pr: ET.Element) -> None:
    for child in list(tc_pr):
        if child.tag == qn("w", "tcBorders"):
            tc_pr.remove(child)


def add_border(tc_pr: ET.Element, edge: str, size: str) -> None:
    tc_borders = ensure_child(tc_pr, qn("w", "tcBorders"))
    border = ET.SubElement(tc_borders, qn("w", edge))
    border.attrib[qn("w", "val")] = "single"
    border.attrib[qn("w", "sz")] = size
    border.attrib[qn("w", "space")] = "0"
    border.attrib[qn("w", "color")] = "000000"


def set_border_box(parent: ET.Element, border_tag: str, size: str) -> None:
    borders = parent.find(border_tag, NS)
    if borders is None:
        borders = ET.SubElement(parent, qn("w", border_tag.split(":")[1]))
    else:
        for child in list(borders):
            borders.remove(child)

    for edge in ("top", "left", "bottom", "right"):
        border = ET.SubElement(borders, qn("w", edge))
        border.attrib[qn("w", "val")] = "single"
        border.attrib[qn("w", "sz")] = size
        border.attrib[qn("w", "space")] = "0"
        border.attrib[qn("w", "color")] = "000000"


def apply_three_line_style(table: ET.Element) -> None:
    rows = table.findall("w:tr", NS)
    if not rows:
        return

    for row in rows:
        for cell in row.findall("w:tc", NS):
            tc_pr = ensure_child(cell, qn("w", "tcPr"))
            clear_tc_borders(tc_pr)

    first_row = rows[0]
    last_row = rows[-1]

    for cell in first_row.findall("w:tc", NS):
        tc_pr = ensure_child(cell, qn("w", "tcPr"))
        add_border(tc_pr, "top", "8")
        add_border(tc_pr, "bottom", "4")

    for cell in last_row.findall("w:tc", NS):
        tc_pr = ensure_child(cell, qn("w", "tcPr"))
        add_border(tc_pr, "bottom", "8")


def center_table(table: ET.Element) -> None:
    tbl_pr = ensure_child(table, qn("w", "tblPr"))
    jc = tbl_pr.find("w:jc", NS)
    if jc is None:
        jc = ET.SubElement(tbl_pr, qn("w", "jc"))
    jc.attrib[qn("w", "val")] = "center"


def is_algorithm_title(text: str) -> bool:
    return bool(ALGORITHM_TITLE_RE.match(text.strip()))


def get_usable_page_width(body: ET.Element) -> int:
    sect_pr = body.find("w:sectPr", NS)
    if sect_pr is None:
        return 9026

    page_size = sect_pr.find("w:pgSz", NS)
    page_margin = sect_pr.find("w:pgMar", NS)
    if page_size is None or page_margin is None:
        return 9026

    try:
        page_width = int(page_size.attrib.get(qn("w", "w"), "11906"))
        left = int(page_margin.attrib.get(qn("w", "left"), "1440"))
        right = int(page_margin.attrib.get(qn("w", "right"), "1440"))
    except ValueError:
        return 9026

    usable = page_width - left - right
    return usable if usable > 0 else 9026


def cell_has_math(cell: ET.Element) -> bool:
    return cell.find(".//m:oMath", NS) is not None or cell.find(".//m:oMathPara", NS) is not None


def set_cell_width(cell: ET.Element, width: int) -> None:
    tc_pr = ensure_child(cell, qn("w", "tcPr"))
    tc_w = tc_pr.find("w:tcW", NS)
    if tc_w is None:
        tc_w = ET.SubElement(tc_pr, qn("w", "tcW"))
    tc_w.attrib[qn("w", "w")] = str(width)
    tc_w.attrib[qn("w", "type")] = "dxa"


def set_table_width(table: ET.Element, width: int) -> None:
    tbl_pr = ensure_child(table, qn("w", "tblPr"))

    tbl_w = tbl_pr.find("w:tblW", NS)
    if tbl_w is None:
        tbl_w = ET.SubElement(tbl_pr, qn("w", "tblW"))
    tbl_w.attrib[qn("w", "w")] = str(width)
    tbl_w.attrib[qn("w", "type")] = "dxa"

    tbl_layout = tbl_pr.find("w:tblLayout", NS)
    if tbl_layout is None:
        tbl_layout = ET.SubElement(tbl_pr, qn("w", "tblLayout"))
    tbl_layout.attrib[qn("w", "type")] = "fixed"


def replace_table_grid(table: ET.Element, widths: list[int]) -> None:
    existing_grid = table.find("w:tblGrid", NS)
    if existing_grid is not None:
        table.remove(existing_grid)

    tbl_grid = ET.Element(qn("w", "tblGrid"))
    for width in widths:
        grid_col = ET.SubElement(tbl_grid, qn("w", "gridCol"))
        grid_col.attrib[qn("w", "w")] = str(width)

    insert_at = 0
    if table.find("w:tblPr", NS) is not None:
        insert_at = 1
    table.insert(insert_at, tbl_grid)


def table_column_widths(table: ET.Element, usable_width: int) -> list[int]:
    rows = table.findall("w:tr", NS)
    if not rows:
        return []

    cell_rows = [row.findall("w:tc", NS) for row in rows]
    column_count = max(len(cells) for cells in cell_rows)
    if column_count <= 0:
        return []

    weights = [4.0] * column_count
    math_columns = [False] * column_count

    for row_index, cells in enumerate(cell_rows):
        for column_index, cell in enumerate(cells):
            text = paragraph_text(cell).replace(" ", "")
            units = float(max(len(text), 1))
            if row_index == 0:
                units *= 1.25
            if cell_has_math(cell):
                units += 2.0
                math_columns[column_index] = True
            if column_index == 0:
                units = max(units, 6.5)
            weights[column_index] = max(weights[column_index], units)

    min_widths = []
    for has_math in math_columns:
        min_widths.append(1500 if has_math else 1200)

    min_total = sum(min_widths)
    if min_total >= usable_width:
        scaled = [max(720, round(width * usable_width / min_total)) for width in min_widths]
        diff = usable_width - sum(scaled)
        scaled[-1] += diff
        return scaled

    remaining = usable_width - min_total
    weight_total = sum(weights)
    widths = []
    used = 0
    for index, weight in enumerate(weights):
        extra = round(remaining * weight / weight_total) if weight_total else 0
        width = min_widths[index] + extra
        widths.append(width)
        used += width

    widths[-1] += usable_width - used
    return widths


def fit_table_to_page(table: ET.Element, usable_width: int) -> None:
    rows = table.findall("w:tr", NS)
    if not rows:
        return

    column_count = max(len(row.findall("w:tc", NS)) for row in rows)
    if column_count <= 1:
        return
    if len(rows) == 1 and column_count == 3:
        return

    widths = table_column_widths(table, usable_width)
    if not widths:
        return

    set_table_width(table, usable_width)
    replace_table_grid(table, widths)

    for row in rows:
        cells = row.findall("w:tc", NS)
        for index, cell in enumerate(cells):
            if index < len(widths):
                set_cell_width(cell, widths[index])


def make_algorithm_table(paragraphs: list[ET.Element], usable_width: int) -> ET.Element:
    table = ET.Element(qn("w", "tbl"))

    tbl_pr = ET.SubElement(table, qn("w", "tblPr"))
    tbl_w = ET.SubElement(tbl_pr, qn("w", "tblW"))
    tbl_w.attrib[qn("w", "w")] = str(usable_width)
    tbl_w.attrib[qn("w", "type")] = "dxa"

    tbl_layout = ET.SubElement(tbl_pr, qn("w", "tblLayout"))
    tbl_layout.attrib[qn("w", "type")] = "fixed"
    set_border_box(tbl_pr, "w:tblBorders", "8")

    tbl_grid = ET.SubElement(table, qn("w", "tblGrid"))
    grid_col = ET.SubElement(tbl_grid, qn("w", "gridCol"))
    grid_col.attrib[qn("w", "w")] = str(usable_width)

    row = ET.SubElement(table, qn("w", "tr"))
    cell = ET.SubElement(row, qn("w", "tc"))
    tc_pr = ET.SubElement(cell, qn("w", "tcPr"))
    tc_w = ET.SubElement(tc_pr, qn("w", "tcW"))
    tc_w.attrib[qn("w", "w")] = str(usable_width)
    tc_w.attrib[qn("w", "type")] = "dxa"
    v_align = ET.SubElement(tc_pr, qn("w", "vAlign"))
    v_align.attrib[qn("w", "val")] = "top"
    set_border_box(tc_pr, "w:tcBorders", "8")

    if not paragraphs:
        cell.append(make_empty_paragraph())
    else:
        for paragraph in paragraphs:
            cell.append(copy.deepcopy(paragraph))

    center_table(table)
    return table


def make_algorithm_caption(paragraph: ET.Element) -> ET.Element:
    caption = copy.deepcopy(paragraph)
    set_paragraph_style(caption, "TableCaption")
    set_paragraph_alignment(caption, "center")
    return caption


def convert_algorithm_blocks(body: ET.Element, usable_width: int) -> None:
    while True:
        children = list(body)
        start_index = None
        end_index = None

        for index, child in enumerate(children):
            if child.tag == qn("w", "p") and paragraph_text(child) == ALGORITHM_START_MARKER:
                start_index = index
                break

        if start_index is None:
            return

        for index in range(start_index + 1, len(children)):
            child = children[index]
            if child.tag == qn("w", "p") and paragraph_text(child) == ALGORITHM_END_MARKER:
                end_index = index
                break

        if end_index is None:
            return

        algorithm_paragraphs: list[ET.Element] = []
        for child in children[start_index + 1:end_index]:
            if child.tag == qn("w", "p"):
                text = paragraph_text(child)
                if algorithm_paragraphs or is_algorithm_title(text):
                    algorithm_paragraphs.append(child)

        if not algorithm_paragraphs:
            for remove_index in range(end_index, start_index - 1, -1):
                body.remove(children[remove_index])
            continue

        title_paragraph = algorithm_paragraphs[0]
        body_paragraphs = algorithm_paragraphs[1:]
        algorithm_caption = make_algorithm_caption(title_paragraph)
        algorithm_table = make_algorithm_table(body_paragraphs, usable_width)
        for remove_index in range(end_index, start_index - 1, -1):
            body.remove(children[remove_index])
        body.insert(start_index, algorithm_caption)
        body.insert(start_index + 1, algorithm_table)


def set_cell_paragraph_text(cell: ET.Element, text: str) -> None:
    for child in list(cell):
        if child.tag != qn("w", "tcPr"):
            cell.remove(child)

    paragraph = ET.Element(qn("w", "p"))
    p_pr = ET.SubElement(paragraph, qn("w", "pPr"))
    p_style = ET.SubElement(p_pr, qn("w", "pStyle"))
    p_style.attrib[qn("w", "val")] = "Compact"
    paragraph.append(make_run(text))
    normalize_table_paragraph(paragraph)
    cell.append(paragraph)


def fix_literature_table_headers(table: ET.Element) -> None:
    rows = table.findall("w:tr", NS)
    if not rows:
        return

    first_row = rows[0]
    cells = first_row.findall("w:tc", NS)
    if len(cells) != 5:
        return

    current_text = [paragraph_text(cell) for cell in cells]
    if current_text[0] != "Author":
        return
    if any(text for text in current_text[1:]):
        return

    headers = ["Author", "Data-driven", "Explainable", "Dynamics", "Root Cause"]
    for cell, header in zip(cells, headers):
        set_cell_paragraph_text(cell, header)


def normalize_table_text(table: ET.Element) -> None:
    for row in table.findall("w:tr", NS):
        for cell in row.findall("w:tc", NS):
            tc_pr = ensure_child(cell, qn("w", "tcPr"))
            v_align = tc_pr.find("w:vAlign", NS)
            if v_align is None:
                v_align = ET.SubElement(tc_pr, qn("w", "vAlign"))
            v_align.attrib[qn("w", "val")] = "top"

            for paragraph in cell.findall("w:p", NS):
                normalize_table_paragraph(paragraph)


def make_empty_paragraph() -> ET.Element:
    return ET.Element(qn("w", "p"))


def make_number_paragraph(number: int) -> ET.Element:
    paragraph = ET.Element(qn("w", "p"))
    p_pr = ET.SubElement(paragraph, qn("w", "pPr"))
    jc = ET.SubElement(p_pr, qn("w", "jc"))
    jc.attrib[qn("w", "val")] = "right"
    paragraph.append(make_run(f"({number})"))
    return paragraph


def make_cell(width: int, paragraph: ET.Element | None = None) -> ET.Element:
    cell = ET.Element(qn("w", "tc"))
    tc_pr = ET.SubElement(cell, qn("w", "tcPr"))
    tc_w = ET.SubElement(tc_pr, qn("w", "tcW"))
    tc_w.attrib[qn("w", "w")] = str(width)
    tc_w.attrib[qn("w", "type")] = "dxa"
    v_align = ET.SubElement(tc_pr, qn("w", "vAlign"))
    v_align.attrib[qn("w", "val")] = "center"

    tc_borders = ET.SubElement(tc_pr, qn("w", "tcBorders"))
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        border = ET.SubElement(tc_borders, qn("w", edge))
        border.attrib[qn("w", "val")] = "nil"

    cell.append(paragraph if paragraph is not None else make_empty_paragraph())
    return cell


def make_equation_table(equation_paragraph: ET.Element, number: int) -> ET.Element:
    table = ET.Element(qn("w", "tbl"))

    tbl_pr = ET.SubElement(table, qn("w", "tblPr"))
    tbl_w = ET.SubElement(tbl_pr, qn("w", "tblW"))
    tbl_w.attrib[qn("w", "w")] = "0"
    tbl_w.attrib[qn("w", "type")] = "auto"

    tbl_borders = ET.SubElement(tbl_pr, qn("w", "tblBorders"))
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        border = ET.SubElement(tbl_borders, qn("w", edge))
        border.attrib[qn("w", "val")] = "nil"

    tbl_layout = ET.SubElement(tbl_pr, qn("w", "tblLayout"))
    tbl_layout.attrib[qn("w", "type")] = "fixed"

    tbl_grid = ET.SubElement(table, qn("w", "tblGrid"))
    for width in (900, 6460, 2000):
        grid_col = ET.SubElement(tbl_grid, qn("w", "gridCol"))
        grid_col.attrib[qn("w", "w")] = str(width)

    row = ET.SubElement(table, qn("w", "tr"))
    row.append(make_cell(900))
    row.append(make_cell(6460, copy.deepcopy(equation_paragraph)))
    row.append(make_cell(2000, make_number_paragraph(number)))
    return table


def postprocess_document_xml(document_xml: bytes) -> bytes:
    root = ET.fromstring(document_xml)
    body = root.find("w:body", NS)
    if body is None:
        return document_xml

    usable_width = get_usable_page_width(body)
    center_document_title(body)

    for paragraph in root.findall(".//w:p", NS):
        replace_symbol_only_math(paragraph)
        color_added_segments(paragraph)

    figure_number = 0
    for paragraph in root.findall(".//w:p", NS):
        style = paragraph_style(paragraph)
        if style in {"CaptionedFigure", "ImageCaption", "TableCaption"}:
            set_paragraph_alignment(paragraph, "center")
        if style == "ImageCaption":
            figure_number += 1
            prepend_caption_prefix(paragraph, f"Figure {figure_number}. ")

    for table in body.findall("w:tbl", NS):
        center_table(table)
        fix_literature_table_headers(table)
        normalize_table_text(table)
        fit_table_to_page(table, usable_width)
        apply_three_line_style(table)

    convert_algorithm_blocks(body, usable_width)

    equation_number = 0
    children = list(body)
    for index, child in enumerate(children):
        if child.tag != qn("w", "p"):
            continue
        if child.find("m:oMathPara", NS) is None:
            continue

        equation_number += 1
        body.remove(child)
        body.insert(index, make_equation_table(child, equation_number))

    body_children = list(body)
    bibliography_index: int | None = None
    for index, child in enumerate(body_children):
        if child.tag != qn("w", "p"):
            continue
        if paragraph_text(child).startswith("[1] "):
            bibliography_index = index
            break

    if bibliography_index is not None:
        previous_text = ""
        if bibliography_index > 0 and body_children[bibliography_index - 1].tag == qn("w", "p"):
            previous_text = paragraph_text(body_children[bibliography_index - 1])
        if previous_text != "References":
            body.insert(bibliography_index, make_styled_paragraph("References", "Heading1"))

    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def postprocess_docx(docx_path: Path) -> None:
    temp_path = docx_path.with_suffix(docx_path.suffix + ".tmp")

    with zipfile.ZipFile(docx_path, "r") as source_zip:
        with zipfile.ZipFile(temp_path, "w", compression=zipfile.ZIP_DEFLATED) as target_zip:
            for item in source_zip.infolist():
                data = source_zip.read(item.filename)
                if item.filename == "word/document.xml":
                    data = postprocess_document_xml(data)
                target_zip.writestr(item, data)

    temp_path.replace(docx_path)


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python postprocess_docx.py <docx-path>", file=sys.stderr)
        return 2

    docx_path = Path(sys.argv[1]).resolve()
    if not docx_path.exists():
        print(f"File not found: {docx_path}", file=sys.stderr)
        return 1

    postprocess_docx(docx_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
