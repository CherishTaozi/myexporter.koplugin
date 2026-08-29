local BookList = require("ui/widget/booklist")
local DocumentRegistry = require("document/documentregistry")
local md5 = require("ffi/sha2").md5
local _ = require("gettext")
local T = require("ffi/util").template

local MyClipping = {}

-- Kindle-like stable locations: 1 location = 128 bytes of document text.
local LOCATION_BYTES = 128
-- Sidecar (DocSettings) key used to persist computed locations per book.
local LOCATIONS_KEY = "myexporter_locations"

function MyClipping:new(o)
    if o == nil then o = {} end
    setmetatable(o, self)
    self.__index = self
    return o
end

-- clippings: main table to store parsed highlights and notes entries
-- {
--      ["Title(Author Name)"] = {
--          {
--              {
--                  ["page"] = 123,
--                  ["time"] = 1398127554,
--                  ["text"] = "Games of all sorts were played in homes and fields."
--              },
--              {
--                  ["page"] = 156,
--                  ["time"] = 1398128287,
--                  ["text"] = "There Spenser settled down to gentleman farming.",
--                  ["note"] = "This is a sample note.",
--              },
--              ["title"] = "Chapter I"
--          },
--      }
-- }

function MyClipping:parseMyClippings()
    -- My Clippings format:
    -- Title(Author Name)
    -- Your Highlight on Page 123 | Added on Monday, April 21, 2014 10:08:07 PM
    --
    -- This is a sample highlight.
    -- ==========
    local file = io.open("/mnt/us/documents/My Clippings.txt", "r")
    local clippings = {}
    if file then
        local index = 1
        local title, author, info, text
        for line in file:lines() do
            line = line:match("^%s*(.-)%s*$") or ""
            if index == 1 then
                title, author = self:parseTitleFromPath(line)
                clippings[title] = clippings[title] or {
                    title = title,
                    author = author,
                }
            elseif index == 2 then
                info = self:getInfo(line)
            -- elseif index == 3 then
            -- should be a blank line, we skip this line
            elseif index == 4 then
                text = self:getText(line)
            end
            if line == "==========" then
                if index == 5 then
                    -- entry ends normally
                    local clipping = {
                        page = info.page or info.location or _("N/A"),
                        sort = info.sort,
                        time = info.time,
                        text = text,
                    }
                    -- we cannot extract chapter info so just insert clipping
                    -- to a place holder chapter
                    table.insert(clippings[title], { clipping })
                end
                index = 0
            end
            index = index + 1
        end
        file:close()
    end
    return clippings
end

local extensions = {
    [".pdf"] = true,
    [".djvu"] = true,
    [".epub"] = true,
    [".fb2"] = true,
    [".mobi"] = true,
    [".txt"] = true,
    [".html"] = true,
    [".doc"] = true,
}

local function isEmpty(s)
    return s == nil or s == ""
end

-- first attempt to parse from document metadata
-- remove file extensions added by former KOReader
-- extract author name in "Title(Author)" format
-- extract author name in "Title - Author" format
function MyClipping:parseTitleFromPath(line)
    line = line:match("^%s*(.-)%s*$") or ""

    if extensions[line:sub(-4):lower()] then
        line = line:sub(1, -5)
    elseif extensions[line:sub(-5):lower()] then
        line = line:sub(1, -6)
    end

    local author = line:match("%s*%-?%s*%(([^()]*)%)%s*$")
    local title
    if author then
        -- remove the last parenthesized group to keep earlier parentheses in title
        title = line:gsub("%s*%-?%s*%([^()]*%)%s*$", "")
    else
        -- fallback: "Title - Author"
        local t, a = line:match("^(.-)%s*%-%s*(.+)%s*$")
        if t and a then
            title = t
            author = a
        else
            title = line:match("^%s*(.-)[%s%-]*$")
        end
    end

    return isEmpty(title) and _("Unknown Book") or title,
           isEmpty(author) and _("Unknown Author") or author
end

local keywords = {
    ["highlight"] = {
        "Highlight",
        "标注",
    },
    ["note"] = {
        "Note",
        "笔记",
    },
    ["bookmark"] = {
        "Bookmark",
        "书签",
    },
}

local months = {
    ["Jan"] = 1,
    ["Feb"] = 2,
    ["Mar"] = 3,
    ["Apr"] = 4,
    ["May"] = 5,
    ["Jun"] = 6,
    ["Jul"] = 7,
    ["Aug"] = 8,
    ["Sep"] = 9,
    ["Oct"] = 10,
    ["Nov"] = 11,
    ["Dec"] = 12
}

local pms = {
    ["PM"] = 12,
    ["下午"] = 12,
}

function MyClipping:getTime(line)
    if not line then return end
    local _, _, year, month, day = line:find("(%d+)年(%d+)月(%d+)日")
    if not year or not month or not day then
        _, _, year, month, day = line:find("(%d%d%d%d)-(%d%d)-(%d%d)")
    end
    if not year or not month or not day then
        for k, v in pairs(months) do
            if line:find(k) then
                month = v
                _, _, day = line:find(" (%d?%d)[, ]")
                _, _, year = line:find(" (%d%d%d%d)")
                break
            end
        end
    end

    local _, _, hour, minute, second = line:find("(%d+):(%d+):(%d+)")
    if year and month and day and hour and minute and second then
        for k, v in pairs(pms) do
            if line:find(k) then
                hour = hour + v
                break
            end
        end
        local time = os.time({
            year = year, month = month, day = day,
            hour = hour, min = minute, sec = second,
        })

        return time
    end
end

function MyClipping:getInfo(line)
    line = line or ""

    local parts = {}
    for part in line:gmatch("[^|]+") do
        table.insert(parts, part:match("^%s*(.-)%s*$"))
    end

    if #parts < 2 then
        return {}
    end

    local info = {}

    for sort, words in pairs(keywords) do
        for _, word in ipairs(words) do
            if parts[1] and parts[1]:find(word) then
                info.sort = sort
                info.page = tonumber(parts[1]:match("page%s*(%d+)"))
                info.location = parts[#parts-1]:match("(%d+-?%d+)")
                break
            end
        end
    end

    info.time = self:getTime(parts[#parts])

    return info
end

function MyClipping:getText(line)
    line = line or ""
    return line:match("^%s*(.-)%s*$") or ""
end

-- get PNG string and md5 hash
function MyClipping:getImage(image)
    --DEBUG("image", image)
    local doc = DocumentRegistry:openDocument(image.file)
    if doc then
        local png = doc:clipPagePNGString(image.pos0, image.pos1,
                image.pboxes, image.drawer)
        --doc:clipPagePNGFile(image.pos0, image.pos1,
                --image.pboxes, image.drawer, "/tmp/"..md5(png)..".png")
        doc:close()
        if png then return { png = png, hash = md5(png) } end
    end
end

function MyClipping:doesHighlightMatch(item)
    if not item.drawer then return end
    local filter = self.settings.filter
    if filter then
        if filter.style and not filter.style[item.drawer] then return end
        if filter.color and not filter.color[item.color] then return end
    end
    return true
end

-- Carry the raw text anchors (XPointer strings on reflowable documents,
-- tables on fixed layout ones) into the clipping, so stable locations
-- can be computed at export time.
function MyClipping:parseAnnotations(annotations, book)
    for _, item in ipairs(annotations) do
        if self:doesHighlightMatch(item) then
            local clipping = {
                sort    = "highlight",
                page    = item.pageref or item.pageno,
                time    = self:getTime(item.datetime),
                text    = self:getText(item.text),
                note    = item.note and self:getText(item.note),
                chapter = item.chapter,
                drawer  = item.drawer,
                color   = item.color,
                pn_xp   = item.page,
                pos0_xp = type(item.pos0) == "string" and item.pos0 or nil,
                pos1_xp = type(item.pos1) == "string" and item.pos1 or nil,
            }
            table.insert(book, { clipping })
        end
    end
end

function MyClipping:parseHighlight(highlights, bookmarks, book)
    --DEBUG("book", book.file)

    -- create a translated pattern that matches bookmark auto-text
    -- see ReaderBookmark:getBookmarkAutoText and ReaderBookmark:getBookmarkPageString
    --- @todo Remove this once we get rid of auto-text or improve the data model.
    local pattern = "^" .. T(_("Page %1 %2 @ %3"),
                               "%[?%d*%]?%d+",
                               "(.*)",
                               "%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d") .. "$"

    local orphan_highlights = {}
    for page, items in pairs(highlights) do
        for _, item in ipairs(items) do
            if self:doesHighlightMatch(item) then
                local clipping = {
                    sort    = "highlight",
                    page    = page,
                    time    = self:getTime(item.datetime or ""),
                    text    = self:getText(item.text),
                    chapter = item.chapter,
                    drawer  = item.drawer,
                    pn_xp   = item.page,
                    pos0_xp = type(item.pos0) == "string" and item.pos0 or nil,
                    pos1_xp = type(item.pos1) == "string" and item.pos1 or nil,
                }
                local bookmark_found = false
                for _, bookmark in pairs(bookmarks) do
                    if bookmark.datetime == item.datetime then
                        if bookmark.text then
                            local bookmark_quote = bookmark.text:match(pattern)
                            if bookmark_quote ~= clipping.text and bookmark.text ~= clipping.text then
                                -- use modified quoted text or entire bookmark text if it's not a match
                                clipping.note = bookmark_quote or bookmark.text
                            end
                        end
                        bookmark_found = true
                        break
                    end
                end
                if not bookmark_found then
                    table.insert(orphan_highlights, { clipping })
                end
                if item.text == "" and item.pos0 and item.pos1 and
                        item.pos0.x and item.pos0.y and
                        item.pos1.x and item.pos1.y then
                    -- highlights in reflowing mode don't have page in pos
                    if item.pos0.page == nil then item.pos0.page = page end
                    if item.pos1.page == nil then item.pos1.page = page end
                    local image = {}
                    image.file = book.file
                    image.pos0, image.pos1 = item.pos0, item.pos1
                    image.pboxes = item.pboxes
                    image.drawer = item.drawer
                    clipping.image = self:getImage(image)
                end
                --- @todo Store chapter info when exporting highlights.
                if (bookmark_found and clipping.text and clipping.text ~= "") or clipping.image then
                    table.insert(book, { clipping })
                end
            end
        end
    end
    -- A table to map bookmarks timestamp to index in the bookmarks table
    -- to facilitate sorting clippings by their position in the book
    -- since highlights are not sorted by position while bookmarks are.
    local bookmark_indexes = {}
    for i, bookmark in ipairs(bookmarks) do
        bookmark_indexes[self:getTime(bookmark.datetime)] = i
    end
    -- Sort clippings by their position in the book.
    table.sort(book, function(v1, v2) return bookmark_indexes[v1[1].time] > bookmark_indexes[v2[1].time] end)
     -- Place orphans at the end
    for _, v in ipairs(orphan_highlights) do
        table.insert(book, v)
    end
end

function MyClipping:getTitleAuthor(filepath, props)
    local _, _, doc_name = filepath:find(".*/(.*)")
    local parsed_title, parsed_author = self:parseTitleFromPath(doc_name)
    return isEmpty(props.title) and parsed_title or props.title,
           isEmpty(props.authors) and parsed_author or props.authors
end

--[[--
Fill clipping.loc_start / clipping.loc_end with Kindle-like stable locations.

Locations are absolute byte offsets of the highlight anchors in the document
text stream, divided by LOCATION_BYTES. They are layout-independent (they do
not change with font size, margins or re-pagination) and stable across
exports for the same book file. They are NOT guaranteed to match the numbers
a Kindle device would show for the same book.

Locations previously computed are read from `cache` (keyed by the pos0
XPointer, stable for a given book file); missing ones are computed by
extracting text between anchors when an open CRE document is provided.

@treturn cache table if new entries were added (to be persisted), else nil
@treturn bool true if some clippings still lack a location
]]
function MyClipping:applyLocations(book, doc, cache)
    local items = {}
    for _, entry in ipairs(book) do
        for _, clipping in ipairs(entry) do
            if clipping.pos0_xp then
                table.insert(items, clipping)
            end
        end
    end
    if #items == 0 then return nil, false end

    local has_missing = false
    for _, clipping in ipairs(items) do
        local c = cache and cache[clipping.pos0_xp]
        if c then
            clipping.loc_start = c.s
            clipping.loc_end = c.e
        else
            has_missing = true
        end
    end
    if not has_missing then return nil, false end
    if not doc or not doc.getTextFromXPointers or not doc.getPageXPointer then
        return nil, has_missing
    end

    local ok, start_xp = pcall(doc.getPageXPointer, doc, 1)
    if not ok or not start_xp then return nil, has_missing end

    local new_entries = false
    -- Accumulate text length anchor by anchor: each computed clipping only
    -- extracts the text since the previous computed one, not since the
    -- document start (cached entries in between are simply spanned over).
    local prev_xp = start_xp
    local bytes = 0
    for _, clipping in ipairs(items) do
        if not (cache and cache[clipping.pos0_xp]) then
            local seg_ok, seg = pcall(doc.getTextFromXPointers, doc, prev_xp, clipping.pos0_xp)
            if seg_ok and type(seg) == "string" then
                bytes = bytes + #seg
                local loc_start = math.floor(bytes / LOCATION_BYTES) + 1
                local loc_end = loc_start
                if clipping.pos1_xp and clipping.pos1_xp ~= clipping.pos0_xp then
                    local seg2_ok, seg2 = pcall(doc.getTextFromXPointers, doc, clipping.pos0_xp, clipping.pos1_xp)
                    if seg2_ok and type(seg2) == "string" then
                        loc_end = math.floor((bytes + #seg2) / LOCATION_BYTES) + 1
                    end
                end
                clipping.loc_start = loc_start
                clipping.loc_end = loc_end
                cache = cache or {}
                cache[clipping.pos0_xp] = { s = loc_start, e = loc_end }
                prev_xp = clipping.pos0_xp
                new_entries = true
            end
        end
    end
    if new_entries then return cache end
    return nil, has_missing
end

-- Compute locations for a book parsed from its sidecar file (document not
-- open in reader): fill from cache, and only open the document when some
-- locations are still missing. Persists the updated cache back to the
-- sidecar.
function MyClipping:computeBookLocations(book, doc_path, doc_settings)
    local cache = doc_settings:readSetting(LOCATIONS_KEY)
    local new_cache, has_missing = self:applyLocations(book, nil, cache)
    if not has_missing then return end
    local doc = DocumentRegistry:openDocument(doc_path)
    if doc then
        if doc.render then pcall(doc.render, doc) end
        new_cache = self:applyLocations(book, doc, cache)
        doc:close()
    end
    if new_cache then
        doc_settings:saveSetting(LOCATIONS_KEY, new_cache)
        doc_settings:close()
    end
end

function MyClipping:getClippingsFromBook(clippings, doc_path)
    local doc_settings = BookList.getDocSettings(doc_path)
    local highlights, bookmarks
    local annotations = doc_settings:readSetting("annotations")
    if annotations == nil then
        highlights = doc_settings:readSetting("highlight")
        if highlights == nil then return end
        bookmarks = doc_settings:readSetting("bookmarks")
    end
    local props = doc_settings:readSetting("doc_props")
    props = self.ui.bookinfo.extendProps(props, doc_path)
    local title, author = self:getTitleAuthor(doc_path, props)
    clippings[title] = {
        file = doc_path,
        title = title,
        author = author,
        number_of_pages = doc_settings:readSetting("doc_pages"),
    }
    if annotations then
        self:parseAnnotations(annotations, clippings[title])
    else
        self:parseHighlight(highlights, bookmarks, clippings[title])
    end
    self:computeBookLocations(clippings[title], doc_path, doc_settings)
end

function MyClipping:parseHistory()
    local clippings = {}
    for _, item in ipairs(require("readhistory").hist) do
        if not item.dim and BookList.hasBookBeenOpened(item.file) then
            self:getClippingsFromBook(clippings, item.file)
        end
    end
    return clippings
end

function MyClipping:parseFiles(files)
    local clippings = {}
    for file in pairs(files) do
        if BookList.hasBookBeenOpened(file) then
            self:getClippingsFromBook(clippings, file)
        end
    end
    return clippings
end

function MyClipping:parseCurrentDoc()
    local title, author = self:getTitleAuthor(self.ui.document.file, self.ui.doc_props)
    local clippings = {
        [title] = {
            file = self.ui.document.file,
            title = title,
            author = author,
            number_of_pages = BookList.getBookInfo(self.ui.document.file).pages,
        },
    }
    self:parseAnnotations(self.ui.annotation.annotations, clippings[title])
    local doc_settings = self.ui.doc_settings
    local cache = doc_settings and doc_settings:readSetting(LOCATIONS_KEY) or nil
    local new_cache = self:applyLocations(clippings[title], self.ui.document, cache)
    if new_cache and doc_settings then
        -- flushed to disk together with the book's other settings on close
        doc_settings:saveSetting(LOCATIONS_KEY, new_cache)
    end
    return clippings
end

return MyClipping
