describe("Optimal line breaking", function()
    local Blitbuffer, DocSettings, DocumentRegistry, Geom, ReaderUI, UIManager
    local filename
    local old_floating_punctuation
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
        old_floating_punctuation = G_reader_settings:readSetting("floating_punctuation")
        G_reader_settings:delSetting("optimal_line_breaking")
        G_reader_settings:delSetting("floating_punctuation")

        local tmpname = os.tmpname()
        os.remove(tmpname)
        filename = tmpname .. ".html"
        local file = assert(io.open(filename, "w"))
        file:write([[<!doctype html><html><head><style>
body { margin: 0; font-family: "Droid Sans Mono"; font-size: 20px; line-height: 1; }
p { margin: 0; text-align: justify; }
.noindent p { text-indent: 0; }
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
<p style="font-size: 8px">zebu yak okapi</p>
<p style="font-size: 8px">quill lantern harbour meadow cobbler thistle brazier walnut ferment gospel hazard jonquil kestrel lumber mantis nutmeg opulent pigment quarry rustic saffron tundra vellum wharf xenon yodel zircon anvil bramble cinder dapple fathom girder hovel inkwell jetty kindle loftier mulberry nectar oyster parlour quiver sundial tempest upland vagrant willow yeoman zephyr</p>
<p style="text-align: right; font-size: 12px">edgepin</p>
<p style="font-size: 12px">qaa qbb qcc qdd qee qff qgg qhh qii qjj qkk qll qmm qnn qoo qpp qqq qrr qss qtt</p>
<p style="text-align: left"><span style="font-size: 10px">caax </span><span style="font-size: 10px">cbbx</span></p>
<p style="text-align: left"><span style="font-size: 20px">caan </span><span style="font-size: 20px">cbbn</span></p>
<p style="text-align: left"><span style="font-size: 30px">caat </span><span style="font-size: 30px">cbbt</span></p>
<p><span style="font-size: 10px">mxa </span><span style="font-size: 20px">mxb </span><span style="font-size: 30px">mxc </span><span style="font-size: 10px">mxd </span><span style="font-size: 20px">mxe </span><span style="font-size: 30px">mxf </span><span style="font-size: 10px">mxg </span><span style="font-size: 20px">mxh </span><span style="font-size: 30px">mxi </span><span style="font-size: 10px">mxj </span><span style="font-size: 20px">mxk </span><span style="font-size: 30px">mxl</span></p>
</div>
<div class="noindent" style="page-break-before: always; page-break-after: always; margin: 0 30px; font-family: 'Noto Sans'; hyphens: none">
<p style="text-align: left">nleftpin</p>
<p style="text-align: right">rightpinm</p>
<p style="text-align: left">"qleftcontrol</p>
<p style="text-align: right">qrightcontrol,</p>
<p>"haaa, "hbbb, "hccc, "hddd, "heee, "hfff, "hggg, "hhhh, "hiii, "hjjj, "hkkk, "hlll, "hmmm, "hnnn, "hooo, "hppp, "hqqq, "hrrr, "hsss, "httt,</p>
</div>
<div class="noindent" style="page-break-after: always; font-family: 'Noto Sans'; font-style: italic; background: white; hyphens: none">
<p style="text-align: left">nnegativeleft</p>
<p style="text-align: left">Jnegativeleft</p>
<p style="text-align: right">negativerightm</p>
<p style="text-align: right">negativerightf</p>
<p>Jaf Jbf Jcf Jdf Jef Jff Jgf Jhf Jif Jjf Jkf Jlf Jmf Jnf Jof Jpf Jqf Jrf Jsf Jtf</p>
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
        if old_floating_punctuation == nil then
            G_reader_settings:delSetting("floating_punctuation")
        else
            G_reader_settings:saveSetting("floating_punctuation", old_floating_punctuation)
        end
    end)

    local function word_hit(word)
        local hits = readerui.document:findAllText(word, false, 0, 1, false)
        assert.is_truthy(hits and hits[1], word)
        return hits[1]
    end

    local function word_pos(word)
        return readerui.document:getPosFromXPointer(word_hit(word).start)
    end

    local function word_end_pos(word)
        return readerui.document:getPosFromXPointer(word_hit(word)["end"])
    end

    local function word_y(word)
        return word_pos(word)
    end

    local function page_pixels(page)
        local bb = Blitbuffer.new(240, 600)
        bb:fill(Blitbuffer.COLOR_WHITE)
        local rect = Geom:new{ w = 240, h = 600 }
        readerui.document:drawCurrentViewByPage(bb, 0, 0, rect, page)
        local pixels = Blitbuffer.tostring(bb)
        bb:free()
        return pixels
    end

    local function page_pixels_at(word)
        local page = readerui.document:getPageFromXPointer(word_hit(word).start)
        return page_pixels(page)
    end

    it("preserves greedy pixels for excluded and infeasible paragraphs", function()
        readerui.document:setOptimalLineBreaking(false)
        readerui.document:render()
        local greedy_pixels = page_pixels_at("cedar")

        readerui.document:setOptimalLineBreaking(true)
        readerui.document:render()
        assert.is_true(greedy_pixels == page_pixels_at("cedar"))
        assert.are_not.equal(word_y("pneumonoultramicroscopic"), word_y("silicovolcanoconiosis"))
        assert.are_not.equal(word_y("bursztynowego"), word_y("szafirowego"))
    end)

    it("uses nowrap breaks only when the strict passes are infeasible", function()
        assert.are_not.equal(word_y("bravo"), word_y("india"))
        assert.are.equal(word_y("onyx"), word_y("azure"))
    end)

    it("lands every non-final justified line on the exact advance edge", function()
        local _, edge_x = word_end_pos("edgepin")
        local by_line = {}
        for word in ([[qaa qbb qcc qdd qee qff qgg qhh qii qjj qkk qll qmm qnn
                qoo qpp qqq qrr qss qtt]]):gmatch("%a+") do
            local y, x = word_pos(word)
            local _, end_x = word_end_pos(word)
            by_line[y] = by_line[y] or {}
            table.insert(by_line[y], { x = x, end_x = end_x })
        end

        local line_count = 0
        local last_y = 0
        for y in pairs(by_line) do
            line_count = line_count + 1
            last_y = math.max(last_y, y)
        end
        assert.is_true(line_count > 1)
        for y, line in pairs(by_line) do
            if y ~= last_y then
                table.sort(line, function(a, b) return a.x < b.x end)
                assert.are.equal(edge_x, line[#line].end_x)
            end
        end
    end)

    it("adjusts mixed-font spaces proportionally", function()
        local function natural_space(first, second)
            local _, first_end = word_end_pos(first)
            local _, second_start = word_pos(second)
            return second_start - first_end
        end

        local natural = {
            [10] = natural_space("caax", "cbbx"),
            [20] = natural_space("caan", "cbbn"),
            [30] = natural_space("caat", "cbbt"),
        }
        local words = {
            { "mxa", 10 }, { "mxb", 20 }, { "mxc", 30 }, { "mxd", 10 },
            { "mxe", 20 }, { "mxf", 30 }, { "mxg", 10 }, { "mxh", 20 },
            { "mxi", 30 }, { "mxj", 10 }, { "mxk", 20 }, { "mxl", 30 },
        }
        local first_y = word_y(words[1][1])
        assert.are_not.equal(first_y, word_y(words[#words][1]))
        local adjustments = {}
        local has_adjustment = false
        for i = 1, #words - 1 do
            if word_y(words[i + 1][1]) ~= first_y then
                break
            end
            local _, word_end = word_end_pos(words[i][1])
            local _, next_start = word_pos(words[i + 1][1])
            local size = words[i][2]
            local amount = next_start - word_end - natural[size]
            has_adjustment = has_adjustment or amount ~= 0
            table.insert(adjustments, {
                amount = amount,
                natural = natural[size],
            })
        end
        assert.is_true(#adjustments >= 3)
        assert.is_true(has_adjustment)
        local _, edge_x = word_end_pos("edgepin")
        local _, line_end_x = word_end_pos(words[#adjustments + 1][1])
        assert.are.equal(edge_x, line_end_x)
        for i = 2, #adjustments do
            local left = adjustments[i - 1]
            local right = adjustments[i]
            local cross_error = math.abs(left.amount * right.natural - right.amount * left.natural)
            assert.is_true(cross_error <= left.natural + right.natural, string.format(
                "adjustments %d/%d and %d/%d", left.amount, left.natural, right.amount, right.natural))
        end
    end)

    it("keeps word spacing even across justified lines", function()
        -- Unjustified control line in the monospaced test font: "zebu"/"yak" span
        -- one char more than "yak"/"okapi", which pins the char and space widths.
        local _, zebu_x = word_pos("zebu")
        local _, yak_x = word_pos("yak")
        local _, okapi_x = word_pos("okapi")
        local advance = (yak_x - zebu_x) - (okapi_x - yak_x)
        local space = (yak_x - zebu_x) - 4 * advance

        local by_line = {}
        for word in ([[quill lantern harbour meadow cobbler thistle brazier walnut
                ferment gospel hazard jonquil kestrel lumber mantis nutmeg
                opulent pigment quarry rustic saffron tundra vellum wharf
                xenon yodel zircon anvil bramble cinder dapple fathom girder
                hovel inkwell jetty kindle loftier mulberry nectar oyster
                parlour quiver sundial tempest upland vagrant willow yeoman
                zephyr]]):gmatch("%a+") do
            local y, x = word_pos(word)
            by_line[y] = by_line[y] or {}
            table.insert(by_line[y], { word = word, x = x })
        end

        local narrowest = math.huge
        local widest = 0
        for _, line in pairs(by_line) do
            table.sort(line, function(a, b) return a.x < b.x end)
            for i = 2, #line do
                local gap = line[i].x - line[i-1].x - #line[i-1].word * advance
                narrowest = math.min(narrowest, gap / space)
                widest = math.max(widest, gap / space)
            end
        end
        print(string.format("advance=%d space=%d", advance, space))
        for y, line in pairs(by_line) do
            local parts = {}
            for i = 1, #line do
                local gap = i > 1 and (line[i].x - line[i-1].x - #line[i-1].word * advance) or 0
                table.insert(parts, string.format("%s@%d(+%.2f)", line[i].word, line[i].x, gap/space))
            end
            print(string.format("y=%d: %s", y, table.concat(parts, " ")))
        end
        assert.is_true(narrowest < 1, string.format("narrowest gap %.2f spaces", narrowest))
        assert.is_true(widest > 1, string.format("widest gap %.2f spaces", widest))
        assert.is_true(widest < 1.6, string.format("widest gap %.2f spaces", widest))
    end)

    it("positions inline boxes on optimised lines", function()
        local before_y, before_x = word_pos("atlas")
        local inline_y, inline_x = word_pos("cobalt")
        assert.are.equal(before_y, inline_y)
        assert.is_true(before_x < inline_x)
    end)

    it("scores and renders hanging punctuation at both line edges", function()
        local _, left_edge = word_pos("nleftpin")
        local _, right_edge = word_end_pos("rightpinm")
        local _, quote_end = word_pos("qleftcontrol")
        local _, comma_start = word_end_pos("qrightcontrol")
        local quote_width = quote_end - left_edge
        local comma_width = right_edge - comma_start
        assert.is_true(quote_width > 0)
        assert.is_true(comma_width > 0)
        readerui.document:setFloatingPunctuation(1)
        readerui.document:render()

        local left_hang = math.max(1, math.floor(quote_width * 50 / 100))
        local right_hang = math.max(1, math.floor(comma_width * 70 / 100))
        local by_line = {}
        for word in ([[haaa hbbb hccc hddd heee hfff hggg hhhh hiii hjjj
                hkkk hlll hmmm hnnn hooo hppp hqqq hrrr hsss httt]]):gmatch("%a+") do
            local y, x = word_pos(word)
            local _, end_x = word_end_pos(word)
            by_line[y] = by_line[y] or {}
            table.insert(by_line[y], {
                x = x,
                end_x = end_x,
            })
        end

        local line_count = 0
        local last_y = 0
        for y in pairs(by_line) do
            line_count = line_count + 1
            last_y = math.max(last_y, y)
        end
        assert.is_true(line_count > 1)
        for y, line in pairs(by_line) do
            table.sort(line, function(a, b) return a.x < b.x end)
            assert.are.equal(left_edge + quote_width - left_hang, line[1].x)
            if y ~= last_y then
                assert.are.equal(right_edge - comma_width + right_hang, line[#line].end_x)
            end
        end
    end)

    it("keeps negative side bearings on the exact ink edges", function()
        readerui.document:setFloatingPunctuation(1)
        readerui.document:render()

        local _, natural_left = word_pos("nnegativeleft")
        local _, inset_left = word_pos("Jnegativeleft")
        local _, natural_right = word_end_pos("negativerightm")
        local _, inset_right = word_end_pos("negativerightf")
        assert.is_true(inset_left > natural_left)
        assert.is_true(inset_right < natural_right)

        local by_line = {}
        for word in ([[Jaf Jbf Jcf Jdf Jef Jff Jgf Jhf Jif Jjf Jkf Jlf Jmf Jnf
                Jof Jpf Jqf Jrf Jsf Jtf]]):gmatch("%a+") do
            local y, x = word_pos(word)
            local _, end_x = word_end_pos(word)
            by_line[y] = by_line[y] or {}
            table.insert(by_line[y], { x = x, end_x = end_x })
        end

        local line_count = 0
        local last_y = 0
        for y in pairs(by_line) do
            line_count = line_count + 1
            last_y = math.max(last_y, y)
        end
        assert.is_true(line_count > 1)
        for y, line in pairs(by_line) do
            if y ~= last_y then
                table.sort(line, function(a, b) return a.x < b.x end)
                assert.are.equal(inset_left, line[1].x)
                assert.are.equal(inset_right, line[#line].end_x)
            end
        end
    end)

    it("hashes hanging punctuation when it affects optimal breaks", function()
        readerui.document:setFloatingPunctuation(0)
        readerui.document:render()
        local without_hanging = readerui.document:getDocumentRenderingHash()
        readerui.document:setFloatingPunctuation(1)
        readerui.document:render()
        assert.are_not.equal(without_hanging, readerui.document:getDocumentRenderingHash())
    end)
end)
