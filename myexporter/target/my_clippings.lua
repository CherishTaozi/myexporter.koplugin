local util = require("ffi/util")
local T = util.template

-- myClippings exporter
local ClippingsExporter = require("myexporter/base"):new {
    name = "myClippings",
    extension = "txt",
    mimetype = "text/plain",
    all_books_title = "myClippings"
}

local WEEKDAYS = { "日", "一", "二", "三", "四", "五", "六" }

-- "2026年8月29日星期六 15:01:15"
local function formatDateTime(time)
    if not time then return "" end
    local t = os.date("*t", time)
    return string.format("%d年%d月%d日星期%s %02d:%02d:%02d",
        t.year, t.month, t.day, WEEKDAYS[t.wday] or "?", t.hour, t.min, t.sec)
end

-- Kindle style: highlights always show a range ("#218-218"), notes a
-- single point ("#218"); nil when no location could be computed
-- (fixed-layout documents)
local function formatLocationRange(clipping)
    if not clipping.loc_start then return end
    return string.format("%d-%d", clipping.loc_start, clipping.loc_end or clipping.loc_start)
end

local function formatLocationPoint(clipping)
    if not clipping.loc_start then return end
    return tostring(clipping.loc_start)
end

local function format(booknotes)
    local tbl = {}

    for ___, entry in ipairs(booknotes) do
        for ____, clipping in ipairs(entry) do
            if booknotes.title and clipping.text then
                local title_str = booknotes.title .. " (" .. (booknotes.author or "Unknown") .. ")"
                local loc_range = formatLocationRange(clipping)
                table.insert(tbl, title_str)
                local header
                if loc_range then
                    header = T("- 您在第 %1 页（位置 #%2）的标注 | 添加于 %3",
                        clipping.page, loc_range, formatDateTime(clipping.time))
                else
                    header = T("- 您在第 %1 页的标注 | 添加于 %2",
                        clipping.page, formatDateTime(clipping.time))
                end
                table.insert(tbl, header)
                table.insert(tbl, "")
                table.insert(tbl, clipping.text)
                table.insert(tbl, "==========")

                if clipping.note then
                    table.insert(tbl, title_str)
                    local loc_point = formatLocationPoint(clipping)
                    if loc_point then
                        header = T("- 您在第 %1 页（位置 #%2）的笔记 | 添加于 %3",
                            clipping.page, loc_point, formatDateTime(clipping.time))
                    else
                        header = T("- 您在第 %1 页的笔记 | 添加于 %2",
                            clipping.page, formatDateTime(clipping.time))
                    end
                    table.insert(tbl, header)
                    table.insert(tbl, "")
                    table.insert(tbl, clipping.note)
                    table.insert(tbl, "==========")
                end
            end
        end
    end

    -- Ensure a newline after the last "=========="
    table.insert(tbl, "")
    return table.concat(tbl, "\n")
end

function ClippingsExporter:export(t)
    local path = self:getFilePath(t)
    -- overwrite: content is always fully regenerated from the books'
    -- sidecars, so appending (Kindle-style) would only create duplicates
    -- when exporting to a fixed filename
    local file = io.open(path, "w")
    if not file then return false end
    for __, booknotes in ipairs(t) do
        local content = format(booknotes)
        file:write(content)
    end
    file:close()
    return true
end

function ClippingsExporter:share(t)
    local content = format(t)
    self:shareText(content)
end

return ClippingsExporter
