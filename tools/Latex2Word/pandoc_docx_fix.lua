local author_lookup = {}
local label_map = {}
local section_counters = {}
local algorithm_entries = {}
local table_entries = {}
local figure_counter = 0
local table_counter = 0
local equation_counter = 0
local algorithm_counter = 0
local algorithm_start_marker = "CODXALGSTART"
local algorithm_end_marker = "CODXALGEND"

local function trim(text)
  if not text then
    return ""
  end
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function file_exists(path)
  local handle = io.open(path, "r")
  if handle then
    handle:close()
    return true
  end
  return false
end

local function read_file(path)
  local handle = io.open(path, "r")
  if not handle then
    return nil
  end
  local content = handle:read("*a")
  handle:close()
  return content
end

local function dirname(path)
  if not path then
    return "."
  end
  return path:match("^(.*)[/\\][^/\\]+$") or "."
end

local function join_path(base, path)
  if not base or base == "" then
    return path
  end
  local last = base:sub(-1)
  if last == "/" or last == "\\" then
    return base .. path
  end
  return base .. "/" .. path
end

local function resolve_path(path, relative_to)
  if not path or path == "" then
    return nil
  end
  if path:match("^%a:[/\\]") or path:match("^[/\\]") then
    return path
  end
  return join_path(dirname(relative_to), path)
end

local function latex_to_text(text)
  if not text or text == "" then
    return ""
  end

  local cleaned = text
  cleaned = cleaned:gsub("\r", " "):gsub("\n", " ")
  cleaned = cleaned:gsub("\\['`%^\"~=%.Hckuvbdrt]%s*%{?([A-Za-z])%}?", "%1")
  cleaned = cleaned:gsub("\\ae", "ae")
  cleaned = cleaned:gsub("\\AE", "AE")
  cleaned = cleaned:gsub("\\oe", "oe")
  cleaned = cleaned:gsub("\\OE", "OE")
  cleaned = cleaned:gsub("\\aa", "aa")
  cleaned = cleaned:gsub("\\AA", "AA")
  cleaned = cleaned:gsub("\\o", "o")
  cleaned = cleaned:gsub("\\O", "O")
  cleaned = cleaned:gsub("\\ss", "ss")
  cleaned = cleaned:gsub("\\&", "&")
  cleaned = cleaned:gsub("\\_", "_")
  cleaned = cleaned:gsub("\\%-", "-")
  cleaned = cleaned:gsub("\\texttt%s*%{([^{}]*)%}", "%1")
  cleaned = cleaned:gsub("\\textit%s*%{([^{}]*)%}", "%1")
  cleaned = cleaned:gsub("\\textbf%s*%{([^{}]*)%}", "%1")
  cleaned = cleaned:gsub("\\emph%s*%{([^{}]*)%}", "%1")
  cleaned = cleaned:gsub("\\uppercase%s*%{([^{}]*)%}", "%1")
  cleaned = cleaned:gsub("\\lowercase%s*%{([^{}]*)%}", "%1")
  cleaned = cleaned:gsub("\\%a+%*?%s*%b{}", function(command)
    return command:match("{(.*)}") or ""
  end)
  cleaned = cleaned:gsub("\\%a+", "")
  cleaned = cleaned:gsub("{", "")
  cleaned = cleaned:gsub("}", "")
  cleaned = cleaned:gsub("%s+", " ")
  return trim(cleaned)
end

local function extract_balanced_value(text, start_index)
  local delimiter = text:sub(start_index, start_index)
  if delimiter == "{" then
    local depth = 0
    local result = {}
    for index = start_index, #text do
      local char = text:sub(index, index)
      if char == "{" then
        depth = depth + 1
        if depth > 1 then
          result[#result + 1] = char
        end
      elseif char == "}" then
        depth = depth - 1
        if depth == 0 then
          return table.concat(result), index
        end
        result[#result + 1] = char
      else
        result[#result + 1] = char
      end
    end
  elseif delimiter == '"' then
    local result = {}
    local escaped = false
    for index = start_index + 1, #text do
      local char = text:sub(index, index)
      if char == '"' and not escaped then
        return table.concat(result), index
      end
      if char == "\\" and not escaped then
        escaped = true
      else
        escaped = false
      end
      result[#result + 1] = char
    end
  end
  return nil, nil
end

local function extract_field(entry_body, field_name)
  local lower = entry_body:lower()
  local pattern = field_name:lower() .. "%s*="
  local start_pos, end_pos = lower:find(pattern)
  if not start_pos then
    return nil
  end
  local index = end_pos + 1
  while index <= #entry_body and entry_body:sub(index, index):match("%s") do
    index = index + 1
  end
  if index > #entry_body then
    return nil
  end
  local value, _ = extract_balanced_value(entry_body, index)
  return value
end

local function parse_bibtex(text)
  local index = 1
  while true do
    local start_pos, _, _, key = text:find("@(%w+)%s*{%s*([^,%s]+)%s*,", index)
    if not start_pos then
      break
    end

    local brace_pos = text:find("{", start_pos, true)
    if not brace_pos then
      break
    end

    local depth = 1
    local cursor = brace_pos + 1
    while cursor <= #text and depth > 0 do
      local char = text:sub(cursor, cursor)
      if char == "{" then
        depth = depth + 1
      elseif char == "}" then
        depth = depth - 1
      end
      cursor = cursor + 1
    end

    local entry = text:sub(brace_pos + 1, cursor - 2)
    local author_field = extract_field(entry, "author")
    if author_field then
      author_lookup[key] = latex_to_text(author_field)
    end

    index = cursor
  end
end

local function load_bibliography(meta)
  local bibliography = meta.bibliography
  if not bibliography then
    return
  end

  local input_file = PANDOC_STATE.input_files[1]
  local paths = {}

  if bibliography.t == "MetaList" then
    for _, item in ipairs(bibliography) do
      paths[#paths + 1] = pandoc.utils.stringify(item)
    end
  else
    paths[#paths + 1] = pandoc.utils.stringify(bibliography)
  end

  for _, path in ipairs(paths) do
    local resolved = resolve_path(path, input_file)
    if resolved and file_exists(resolved) then
      local content = read_file(resolved)
      if content then
        parse_bibtex(content)
      end
    end
  end
end

local function split_authors(author_field)
  local authors = {}
  if not author_field or author_field == "" then
    return authors
  end

  local normalized = " " .. author_field .. " "
  for author in normalized:gmatch(" (.-) [Aa][Nn][Dd] ") do
    authors[#authors + 1] = trim(author)
  end

  if #authors == 0 then
    authors[1] = trim(author_field)
  end
  return authors
end

local function extract_last_name(author)
  local cleaned = latex_to_text(author)
  if cleaned:find(",") then
    return trim(cleaned:match("^([^,]+)"))
  end
  return trim(cleaned:match("([^%s]+)$") or cleaned)
end

local function format_author_in_text(citation_id)
  local authors = split_authors(author_lookup[citation_id] or "")
  if #authors == 0 then
    return citation_id
  elseif #authors == 1 then
    return extract_last_name(authors[1])
  elseif #authors == 2 then
    return extract_last_name(authors[1]) .. " and " .. extract_last_name(authors[2])
  end
  return extract_last_name(authors[1]) .. " et al."
end

local function clone_citation(citation)
  return pandoc.Citation(
    citation.id,
    "NormalCitation",
    citation.prefix,
    citation.suffix,
    citation.note_num,
    citation.hash
  )
end

local function transform_citet(cite)
  if #cite.citations == 0 then
    return nil
  end

  local first = cite.citations[1]
  if first.mode ~= "AuthorInText" then
    return nil
  end

  local author_text = format_author_in_text(first.id)
  local normal_citations = pandoc.List()
  for _, citation in ipairs(cite.citations) do
    normal_citations:insert(clone_citation(citation))
  end

  local result = pandoc.List()
  result:insert(pandoc.Str(author_text))
  result:insert(pandoc.Space())
  result:insert(pandoc.Cite({}, normal_citations))
  return result
end

local function latex_snippet_to_inlines(text)
  local snippet = trim(text or "")
  if snippet == "" then
    return pandoc.List()
  end

  local ok, parsed = pcall(pandoc.read, snippet, "latex")
  if ok and parsed and parsed.blocks and #parsed.blocks > 0 then
    local first = parsed.blocks[1]
    if first.t == "Para" or first.t == "Plain" then
      return first.content
    end
  end

  local fallback = pandoc.List()
  fallback:insert(pandoc.Str(latex_to_text(snippet)))
  return fallback
end

local function append_inlines(target, source)
  for _, inline in ipairs(source) do
    target:insert(inline)
  end
end

local function make_algorithm_paragraph(indent, prefix, text, strong_prefix)
  local inlines = pandoc.List()
  if indent > 0 then
    inlines:insert(pandoc.Str(string.rep(utf8.char(160), indent * 4)))
  end

  if prefix and prefix ~= "" then
    if strong_prefix then
      inlines:insert(pandoc.Strong({ pandoc.Str(prefix) }))
    else
      inlines:insert(pandoc.Str(prefix))
    end
    if text and text ~= "" then
      inlines:insert(pandoc.Space())
    end
  end

  append_inlines(inlines, latex_snippet_to_inlines(text))
  return pandoc.Para(inlines)
end

local function build_algorithm_blocks(entry, number)
  local blocks = pandoc.List()
  local caption_text = "Algorithm " .. number
  if entry.caption and entry.caption ~= "" then
    caption_text = caption_text .. ". " .. entry.caption
  end

  blocks:insert(pandoc.Para({ pandoc.Str(algorithm_start_marker) }))
  blocks:insert(pandoc.Para({ pandoc.Strong({ pandoc.Str(caption_text) }) }))

  for _, line in ipairs(entry.lines or {}) do
    if line.kind == "input" then
      blocks:insert(make_algorithm_paragraph(0, "Input:", line.text, true))
    elseif line.kind == "output" then
      blocks:insert(make_algorithm_paragraph(0, "Output:", line.text, true))
    elseif line.kind == "elseif" then
      blocks:insert(make_algorithm_paragraph(line.indent, "Else if", line.text .. " then", false))
    elseif line.kind == "else" then
      blocks:insert(make_algorithm_paragraph(line.indent, "Else", "", false))
    elseif line.kind == "for" then
      blocks:insert(make_algorithm_paragraph(line.indent, "For", line.text .. " do", false))
    elseif line.kind == "while" then
      blocks:insert(make_algorithm_paragraph(line.indent, "While", line.text .. " do", false))
    elseif line.kind == "if" then
      blocks:insert(make_algorithm_paragraph(line.indent, "If", line.text .. " then", false))
    elseif line.kind == "return" then
      blocks:insert(make_algorithm_paragraph(line.indent, "Return", line.text, false))
    elseif line.kind == "end" then
      blocks:insert(make_algorithm_paragraph(line.indent, line.text, "", false))
    else
      blocks:insert(make_algorithm_paragraph(line.indent, "", line.text, false))
    end
  end

  blocks:insert(pandoc.Para({ pandoc.Str(algorithm_end_marker) }))
  return blocks
end

local function parse_table_blocks()
  local input_file = PANDOC_STATE.input_files[1]
  local source = read_file(input_file)
  if not source then
    return
  end

  local begin_prefix = "\\begin{table"
  local index = 1
  while true do
    local start_pos = source:find(begin_prefix, index, true)
    if not start_pos then
      break
    end

    local after_index = start_pos + #begin_prefix
    local after_table = source:sub(after_index, after_index)
    if after_table ~= "}" and after_table ~= "*" then
      index = start_pos + 1
      goto continue_table
    end

    local is_star = after_table == "*"
    local closing_char_index = is_star and (after_index + 1) or after_index
    if source:sub(closing_char_index, closing_char_index) ~= "}" then
      index = start_pos + 1
      goto continue_table
    end

    local end_token = is_star and "\\end{table*}" or "\\end{table}"
    local end_pos = source:find(end_token, closing_char_index, true)
    if not end_pos then
      break
    end

    local block = source:sub(start_pos, end_pos + #end_token - 1)
    table_entries[#table_entries + 1] = {
      label = trim(block:match("\\label%s*{([^}]+)}") or ""),
      caption = trim(block:match("\\caption%s*{([^}]*)}") or "")
    }

    index = end_pos + #end_token
    ::continue_table::
  end
end

local function parse_algorithm_lines(block)
  local algorithmic_body = block:match("\\begin%s*{algorithmic}%s*%b[]%s*(.-)\\end%s*{algorithmic}")
  if not algorithmic_body then
    algorithmic_body = block:match("\\begin%s*{algorithmic}%s*(.-)\\end%s*{algorithmic}")
  end
  if not algorithmic_body then
    return {}
  end

  local lines = {}
  local indent = 0

  for raw_line in algorithmic_body:gmatch("[^\r\n]+") do
    local line = trim(raw_line:gsub("\\label%s*{[^}]+}", ""))
    if line ~= "" then
      local require_text = line:match("^\\Require%s*(.*)$")
      local ensure_text = line:match("^\\Ensure%s*(.*)$")
      local for_text = line:match("^\\For%s*{(.*)}%s*$")
      local while_text = line:match("^\\While%s*{(.*)}%s*$")
      local if_text = line:match("^\\If%s*{(.*)}%s*$")
      local elseif_text = line:match("^\\ElsIf%s*{(.*)}%s*$") or line:match("^\\ElseIf%s*{(.*)}%s*$")
      local is_else = line:match("^\\Else%s*$")
      local is_end_for = line:match("^\\EndFor%s*$")
      local is_end_while = line:match("^\\EndWhile%s*$")
      local is_end_if = line:match("^\\EndIf%s*$")
      local state_text = line:match("^\\State%s*(.*)$")

      if require_text then
        lines[#lines + 1] = { kind = "input", indent = 0, text = trim(require_text) }
      elseif ensure_text then
        lines[#lines + 1] = { kind = "output", indent = 0, text = trim(ensure_text) }
      elseif for_text then
        lines[#lines + 1] = { kind = "for", indent = indent, text = trim(for_text) }
        indent = indent + 1
      elseif while_text then
        lines[#lines + 1] = { kind = "while", indent = indent, text = trim(while_text) }
        indent = indent + 1
      elseif if_text then
        lines[#lines + 1] = { kind = "if", indent = indent, text = trim(if_text) }
        indent = indent + 1
      elseif elseif_text then
        indent = math.max(indent - 1, 0)
        lines[#lines + 1] = { kind = "elseif", indent = indent, text = trim(elseif_text) }
        indent = indent + 1
      elseif is_else then
        indent = math.max(indent - 1, 0)
        lines[#lines + 1] = { kind = "else", indent = indent, text = "" }
        indent = indent + 1
      elseif is_end_for then
        indent = math.max(indent - 1, 0)
        lines[#lines + 1] = { kind = "end", indent = indent, text = "End for" }
      elseif is_end_while then
        indent = math.max(indent - 1, 0)
        lines[#lines + 1] = { kind = "end", indent = indent, text = "End while" }
      elseif is_end_if then
        indent = math.max(indent - 1, 0)
        lines[#lines + 1] = { kind = "end", indent = indent, text = "End if" }
      elseif state_text then
        local cleaned_state = trim(state_text)
        local return_text = cleaned_state:match("^\\Return%s*(.*)$")
        if return_text then
          lines[#lines + 1] = { kind = "return", indent = indent, text = trim(return_text) }
        elseif cleaned_state ~= "" then
          lines[#lines + 1] = { kind = "state", indent = indent, text = cleaned_state }
        end
      end
    end
  end

  return lines
end

local function parse_algorithm_blocks()
  local input_file = PANDOC_STATE.input_files[1]
  local source = read_file(input_file)
  if not source then
    return
  end

  local begin_prefix = "\\begin{algorithm"
  local index = 1
  while true do
    local start_pos = source:find(begin_prefix, index, true)
    if not start_pos then
      break
    end

    local after_index = start_pos + #begin_prefix
    local after_algorithm = source:sub(after_index, after_index)
    if after_algorithm ~= "}" and after_algorithm ~= "*" then
      index = start_pos + 1
      goto continue
    end

    local is_star = after_algorithm == "*"
    local closing_char_index = is_star and (after_index + 1) or after_index
    if source:sub(closing_char_index, closing_char_index) ~= "}" then
      index = start_pos + 1
      goto continue
    end

    local end_token = is_star and "\\end{algorithm*}" or "\\end{algorithm}"
    local end_pos = source:find(end_token, start_pos, true)
    if not end_pos then
      break
    end

    local block = source:sub(start_pos, end_pos + #end_token - 1)
    local label = block:match("\\label%s*{([^}]+)}")
    local caption = block:match("\\caption%s*{([^}]*)}")
    if label then
      algorithm_entries[#algorithm_entries + 1] = {
        label = trim(label),
        caption = latex_to_text(caption or ""),
        lines = parse_algorithm_lines(block)
      }
    end

    index = end_pos + #end_token
    ::continue::
  end
end

local function prepend_caption(caption, prefix)
  if not caption or not caption.long or #caption.long == 0 then
    return caption
  end

  local first_block = caption.long[1]
  if first_block.t ~= "Plain" and first_block.t ~= "Para" then
    return caption
  end

  local new_inlines = pandoc.List()
  new_inlines:insert(pandoc.Str(prefix))
  for _, inline in ipairs(first_block.content) do
    new_inlines:insert(inline)
  end

  if first_block.t == "Plain" then
    caption.long[1] = pandoc.Plain(new_inlines)
  else
    caption.long[1] = pandoc.Para(new_inlines)
  end
  return caption
end

local function ensure_table_caption(table_block, prefix, fallback_caption)
  if not table_block.caption then
    return table_block
  end

  if table_block.caption.long and #table_block.caption.long > 0 then
    table_block.caption = prepend_caption(table_block.caption, prefix)
    return table_block
  end

  if fallback_caption and fallback_caption ~= "" then
    local new_inlines = pandoc.List()
    new_inlines:insert(pandoc.Str(prefix))
    append_inlines(new_inlines, latex_snippet_to_inlines(fallback_caption))
    table_block.caption.long = pandoc.List()
    table_block.caption.long:insert(pandoc.Plain(new_inlines))
  end

  return table_block
end

local function first_block_index(blocks, block_type)
  for index, block in ipairs(blocks) do
    if block.t == block_type then
      return index, block
    end
  end
  return nil, nil
end

local function clean_equation_math(text)
  local cleaned = text
  cleaned = cleaned:gsub("\\begin%s*{equation%*?}", "")
  cleaned = cleaned:gsub("\\end%s*{equation%*?}", "")
  cleaned = cleaned:gsub("\\label%s*{[^}]+}", "")
  cleaned = cleaned:gsub("^%s+", "")
  cleaned = cleaned:gsub("%s+$", "")
  return cleaned
end

local function register_section(header)
  while #section_counters < header.level do
    section_counters[#section_counters + 1] = 0
  end
  section_counters[header.level] = (section_counters[header.level] or 0) + 1
  for index = header.level + 1, #section_counters do
    section_counters[index] = 0
  end

  local parts = {}
  for index = 1, header.level do
    if section_counters[index] and section_counters[index] > 0 then
      parts[#parts + 1] = tostring(section_counters[index])
    end
  end

  if header.identifier and header.identifier ~= "" then
    label_map[header.identifier] = {
      kind = "section",
      number = table.concat(parts, ".")
    }
  end
  return header
end

local function register_figure(figure)
  figure_counter = figure_counter + 1
  if figure.identifier and figure.identifier ~= "" then
    label_map[figure.identifier] = {
      kind = "figure",
      number = tostring(figure_counter)
    }
  end
  return figure
end

local function register_equation(para)
  for index, inline in ipairs(para.content) do
    if inline.t == "Math" and inline.mathtype == "DisplayMath" then
      local label = inline.text:match("\\label%s*{([^}]+)}")
      if label then
        equation_counter = equation_counter + 1
        label_map[label] = {
          kind = "equation",
          number = equation_counter
        }
        para.content[index] = pandoc.Math("DisplayMath", clean_equation_math(inline.text))
      end
    end
  end
  return para
end

local function register_div(div)
  local table_block_index, table_block = first_block_index(div.content, "Table")
  if table_block_index then
    table_counter = table_counter + 1
    local table_entry = table_entries[table_counter] or {}
    local label = trim(div.identifier or "")
    if label == "" and table_block.identifier and table_block.identifier ~= "" then
      label = trim(table_block.identifier)
    end
    if label == "" and table_entry.label and table_entry.label ~= "" then
      label = table_entry.label
    end

    if label ~= "" then
      label_map[label] = {
        kind = "table",
        number = tostring(table_counter)
      }
      div.identifier = label
    end

    div.content[table_block_index] = ensure_table_caption(
      table_block,
      "Table " .. table_counter .. ": ",
      table_entry.caption
    )
    return div
  end

  local is_algorithm = false
  for _, class_name in ipairs(div.classes) do
    if class_name == "algorithm" or class_name == "algorithm*" then
      is_algorithm = true
      break
    end
  end

  if is_algorithm then
    algorithm_counter = algorithm_counter + 1
    local entry = algorithm_entries[algorithm_counter] or {}
    if entry.label and entry.label ~= "" then
      label_map[entry.label] = {
        kind = "algorithm",
        number = algorithm_counter
      }
    end

    if entry.lines and #entry.lines > 0 then
      return build_algorithm_blocks(entry, algorithm_counter)
    end

    local caption_text = "Algorithm " .. algorithm_counter
    if entry.caption and entry.caption ~= "" then
      caption_text = caption_text .. ". " .. entry.caption
    end

    local new_content = pandoc.List()
    new_content:insert(pandoc.Para({ pandoc.Str(algorithm_start_marker) }))
    new_content:insert(pandoc.Para({ pandoc.Strong({ pandoc.Str(caption_text) }) }))
    for _, block in ipairs(div.content) do
      new_content:insert(block)
    end
    new_content:insert(pandoc.Para({ pandoc.Str(algorithm_end_marker) }))
    return new_content
  end

  return div
end

local function split_labels(reference)
  local labels = {}
  if not reference then
    return labels
  end
  for label in reference:gmatch("([^,%s]+)") do
    labels[#labels + 1] = label
  end
  return labels
end

local function build_simple_inlines(parts)
  local inlines = pandoc.List()
  for _, part in ipairs(parts) do
    if part == " " then
      inlines:insert(pandoc.Space())
    elseif part ~= "" then
      inlines:insert(pandoc.Str(part))
    end
  end
  return inlines
end

local function reference_name(kind, count, uppercase)
  local names = {
    section = { singular = "section", plural = "sections" },
    figure = { singular = "figure", plural = "figures" },
    table = { singular = "table", plural = "tables" },
    algorithm = { singular = "algorithm", plural = "algorithms" },
    equation = { singular = "equation", plural = "equations" }
  }

  local entry = names[kind]
  if not entry then
    return nil
  end

  local value = count == 1 and entry.singular or entry.plural
  if uppercase then
    return value:gsub("^%l", string.upper)
  end
  return value
end

local function collect_reference_numbers(labels, kind, wrap_equations)
  local rendered = {}
  for _, label in ipairs(labels) do
    local info = label_map[label]
    if info and info.kind == kind and info.number then
      local number = tostring(info.number)
      if wrap_equations then
        rendered[#rendered + 1] = "(" .. number .. ")"
      else
        rendered[#rendered + 1] = number
      end
    end
  end
  return rendered
end

local function render_reference(link)
  local reference = link.attributes["reference"]
  if not reference then
    return nil
  end

  local labels = split_labels(reference)
  if #labels == 0 then
    return nil
  end

  local first = label_map[labels[1]]
  if not first then
    return nil
  end

  local reference_type = link.attributes["reference-type"] or "ref"

  if first.kind == "equation" then
    local rendered = collect_reference_numbers(labels, "equation", true)
    if #rendered == 0 then
      return nil
    end

    if reference_type == "ref+Label" or reference_type == "ref+label" then
      local name = reference_name("equation", #rendered, reference_type == "ref+Label")
      return build_simple_inlines({ name, " ", table.concat(rendered, ", ") })
    end

    if reference_type == "eqref" then
      return build_simple_inlines({ table.concat(rendered, ", ") })
    end

    local bare_numbers = collect_reference_numbers(labels, "equation", false)
    if #bare_numbers > 0 then
      return build_simple_inlines({ table.concat(bare_numbers, ", ") })
    end
  elseif first.kind == "section" or first.kind == "algorithm" or first.kind == "table" or first.kind == "figure" then
    local rendered = collect_reference_numbers(labels, first.kind, false)
    if #rendered == 0 then
      return nil
    end

    if reference_type == "ref+Label" or reference_type == "ref+label" then
      local name = reference_name(first.kind, #rendered, reference_type == "ref+Label")
      return build_simple_inlines({ name, " ", table.concat(rendered, ", ") })
    end

    return build_simple_inlines({ table.concat(rendered, ", ") })
  end

  return nil
end

function Pandoc(doc)
  load_bibliography(doc.meta)
  parse_table_blocks()
  parse_algorithm_blocks()

  doc = doc:walk({
    Header = register_section,
    Figure = register_figure,
    Div = register_div,
    Para = register_equation
  })

  doc = doc:walk({
    Cite = transform_citet,
    Link = render_reference
  })

  return doc
end
