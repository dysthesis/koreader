describe("Optimal line breaking", function()
    local Blitbuffer, DocSettings, DocumentRegistry, Geom, ReaderUI, UIManager
    local filename
    local old_global_setting
    local readerui

    setup(function()
        require("commonrequire")
        disable_plugins()
        Blitbuffer = require("ffi/blitbuffer")
        DocSettings = require("docsettings")
        DocumentRegistry = require("document/documentregistry")
        Geom = require("ui/geometry")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
    end)

    before_each(function()
        old_global_setting = G_reader_settings:readSetting("optimal_line_breaking")
        G_reader_settings:delSetting("optimal_line_breaking")

        local tmpname = os.tmpname()
        os.remove(tmpname)
        filename = tmpname .. ".html"
        local file = assert(io.open(filename, "w"))
        file:write([[<!doctype html><html><head><style>
body { margin: 0; font-family: "Droid Sans Mono"; font-size: 20px; line-height: 1; }
p { margin: 0; text-align: justify; }
</style></head><body>
<div style="page-break-after: always">
<p><span style="float: left; width: 72px">cedar</span> alder birch dogwood elm fir gum hawthorn ironwood juniper larch maple</p>
<p>漢字仮名交じり文の行分割検証用文章です。</p>
<p style="white-space: pre">preformatted    spacing stays fixed</p>
<p>pneumonoultramicroscopicsilicovolcanoconiosis</p>
<p lang="pl">bursztynowego-szafirowego</p>
</div>
<div>
<p>alpha <span style="white-space: nowrap">bravo charlie delta echo foxtrot golf hotel india</span> juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu</p>
<p>amber <span style="white-space: nowrap">onyx azure</span> diamond emerald fossil granite hotel ivory jasper kelp lemon marble nickel olive pearl quartz ruby silver topaz</p>
<p>atlas <span style="display: inline-block">cobalt</span> nimbus fir grove hazel ivory juniper kelp lemon</p>
</div>
</body></html>]])
        file:close()

        DocSettings:open(filename):purge()
        readerui = ReaderUI:new{
            dimen = Geom:new{ w = 240, h = 600 },
            document = DocumentRegistry:openDocument(filename),
        }
        UIManager:show(readerui)
        fastforward_ui_events()
        readerui.document:setOptimalLineBreaking(true)
        readerui.document:render()
    end)

    after_each(function()
        UIManager:quit()
        if readerui then
            readerui:onClose()
        end
        DocSettings:open(filename):purge()
        os.remove(filename)
        if old_global_setting == nil then
            G_reader_settings:delSetting("optimal_line_breaking")
        else
            G_reader_settings:saveSetting("optimal_line_breaking", old_global_setting)
        end
    end)

    local function word_pos(word)
        local hits = readerui.document:findAllText(word, false, 0, 1, false)
        assert.is_truthy(hits and hits[1], word)
        return readerui.document:getPosFromXPointer(hits[1].start)
    end

    local function word_y(word)
        return word_pos(word)
    end

    local function page_pixels()
        local bb = Blitbuffer.new(240, 600)
        bb:fill(Blitbuffer.COLOR_WHITE)
        readerui.view:drawSinglePage(bb, 0, 0)
        local pixels = Blitbuffer.tostring(bb)
        bb:free()
        return pixels
    end

    it("preserves greedy pixels for excluded and infeasible paragraphs", function()
        readerui.document:setOptimalLineBreaking(false)
        readerui.document:render()
        local greedy_pixels = page_pixels()

        readerui.document:setOptimalLineBreaking(true)
        readerui.document:render()
        assert.is_true(greedy_pixels == page_pixels())
        assert.are_not.equal(word_y("pneumonoultramicroscopic"), word_y("silicovolcanoconiosis"))
        assert.are_not.equal(word_y("bursztynowego"), word_y("szafirowego"))
    end)

    it("uses nowrap breaks only when the strict passes are infeasible", function()
        assert.are.equal(word_y("alpha"), word_y("bravo"))
        assert.are_not.equal(word_y("bravo"), word_y("charlie"))
        assert.are.equal(word_y("onyx"), word_y("azure"))
    end)

    it("positions inline boxes on optimised lines", function()
        local before_y, before_x = word_pos("atlas")
        local inline_y, inline_x = word_pos("cobalt")
        assert.are.equal(before_y, inline_y)
        assert.is_true(before_x < inline_x)
    end)
end)
