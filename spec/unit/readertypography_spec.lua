describe("ReaderTypography module", function()
    local DocSettings, DocumentRegistry, ReaderUI, Screen, UIManager
    local sample_epub = "spec/front/unit/data/juliet.epub"
    local readerui
    local old_global_setting

    setup(function()
        require("commonrequire")
        disable_plugins()
        DocSettings = require("docsettings")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
    end)

    before_each(function()
        old_global_setting = G_reader_settings:readSetting("optimal_line_breaking")
        G_reader_settings:delSetting("optimal_line_breaking")
        DocSettings:open(sample_epub):purge()
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        UIManager:show(readerui)
        fastforward_ui_events()
    end)

    after_each(function()
        UIManager:quit()
        if readerui then
            readerui:onClose()
        end
        DocSettings:open(sample_epub):purge()
        if old_global_setting == nil then
            G_reader_settings:delSetting("optimal_line_breaking")
        else
            G_reader_settings:saveSetting("optimal_line_breaking", old_global_setting)
        end
    end)

    it("defaults off, invalidates rendering, and persists", function()
        local menu_item
        for _, item in ipairs(readerui.typography.menu_table) do
            if item.text == "Optimal line breaking" then
                menu_item = item
                break
            end
        end

        assert.is_not_nil(menu_item)
        assert.is_false(readerui.typography.optimal_line_breaking)
        assert.is_false(menu_item.checked_func())
        local greedy_hash = readerui.document:getDocumentRenderingHash()

        menu_item.callback()
        fastforward_ui_events()

        assert.is_true(readerui.typography.optimal_line_breaking)
        assert.is_true(menu_item.checked_func())
        assert.are.not_equal(greedy_hash, readerui.document:getDocumentRenderingHash())

        readerui:saveSettings()
        UIManager:quit()
        readerui:onClose()
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }

        assert.is_true(readerui.typography.optimal_line_breaking)
    end)
end)
