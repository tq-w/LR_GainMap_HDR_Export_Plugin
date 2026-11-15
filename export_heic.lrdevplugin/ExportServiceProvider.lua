local LrTasks = import 'LrTasks'
local LrDialogs = import 'LrDialogs'
local LrPathUtils = import 'LrPathUtils'
local LrExportSession = import 'LrExportSession'
local LrFileUtils = import 'LrFileUtils'
local LrView = import 'LrView'
local LrBinding = import 'LrBinding'
local LrProgressScope = import 'LrProgressScope'
local LrUUID = import 'LrUUID'

local exportServiceProvider = {}
exportServiceProvider.allowFileFormats = { 'TIFF' }

local function forceRenderSettings(settings)
    settings.LR_format = 'TIFF'
    settings.LR_export_bitDepth = 16
    -- The rendition is temporary. Never overwrite an existing TIFF, regardless
    -- of the independently selected policy for the final HEIC.
    settings.LR_collisionHandling = 'rename'
    if (settings.conversionTool or 'toGainMapHDR') ~= 'sips' then
        settings.LR_enableHDRDisplay = true
        settings.LR_maximumCompatibility = false
        local space = settings.LR_export_colorSpace
        if type(space) ~= 'string' or not space:match('_hdr$') then
            settings.LR_export_colorSpace = 'p3_hdr'
        end
    end
end

exportServiceProvider.startDialog = forceRenderSettings
exportServiceProvider.updateExportSettings = forceRenderSettings

exportServiceProvider.exportPresetFields = {
    { key = 'imageQuality', default = 70 },
    { key = 'conversionTool', default = 'toGainMapHDR' }, -- Added conversion tool option
    { key = 'gainMapStandard', default = 'apple' },
    { key = 'heicBitDepth', default = '8' },
    { key = 'gainMapScale', default = 1 },
    { key = 'gainMapQualityEnabled', default = false },
    { key = 'gainMapQuality', default = 80 },
    { key = 'heicCollisionHandling', default = 'rename' },
}



exportServiceProvider.sectionsForTopOfDialog = function(viewFactory, propertyTable)
    local f = viewFactory
    local updating = false
    local function enforceRenderSettings()
        if updating then return end
        updating = true
        forceRenderSettings(propertyTable)
        updating = false
    end
    enforceRenderSettings()
    for _, key in ipairs({ 'LR_format', 'LR_export_bitDepth', 'LR_enableHDRDisplay',
        'LR_maximumCompatibility', 'LR_export_colorSpace', 'LR_collisionHandling' }) do
        propertyTable:addObserver(key, enforceRenderSettings)
    end
    local function updateAvailability()
        propertyTable.gainMapOptionsEnabled = propertyTable.conversionTool == 'toGainMapHDR'
        propertyTable.gainMapScaleEnabled = propertyTable.gainMapOptionsEnabled
        propertyTable.gainMapQualityAvailable = propertyTable.gainMapOptionsEnabled and propertyTable.gainMapStandard == 'iso'
        propertyTable.gainMapQualityEditable = propertyTable.gainMapQualityAvailable and propertyTable.gainMapQualityEnabled == true
        propertyTable.displayBitDepth = (propertyTable.conversionTool == 'pqHDR' or
            propertyTable.conversionTool == 'hlgHDR') and '10' or
            (propertyTable.heicBitDepth or '8')
        enforceRenderSettings()
    end
    updateAvailability()
    propertyTable:addObserver('conversionTool', updateAvailability)
    propertyTable:addObserver('gainMapStandard', updateAvailability)
    propertyTable:addObserver('gainMapQualityEnabled', updateAvailability)
    propertyTable:addObserver('heicBitDepth', updateAvailability)
    propertyTable:addObserver('displayBitDepth', function()
        if propertyTable.gainMapOptionsEnabled then
            propertyTable.heicBitDepth = propertyTable.displayBitDepth
        end
    end)

    -- Ensure imageQuality is an integer
    propertyTable:addObserver('imageQuality', function()
        propertyTable.imageQuality = math.floor(propertyTable.imageQuality + 0.5)
    end)

    return {
        {
            title = 'HEIC 导出选项',
            f:row {
                f:static_text {
                    title = '主图品质:',
                    alignment = 'right',
                    width = LrView.share 'label_width',
                },
                f:slider {
                    value = LrView.bind 'imageQuality',
                    min = 0,
                    max = 100,
                    width_in_chars = 20,
                    fill_horizontal = 1,
                },
                f:edit_field {
                    value = LrView.bind 'imageQuality',
                    width_in_chars = 3,
                },
            },
            f:row {
                f:static_text {
                    title = '输出模式:',
                    alignment = 'right',
                    width = LrView.share 'label_width',
                },
                f:popup_menu {
                    items = {
                        { title = 'HDR 增益图（Apple／ISO）', value = 'toGainMapHDR' },
                        { title = '直接 PQ HDR（10 位，无增益图）', value = 'pqHDR' },
                        { title = '直接 HLG HDR（10 位，无增益图）', value = 'hlgHDR' },
                        { title = 'macOS SIPS（仅 HEIC，无增益图）', value = 'sips' },
                    },
                    value = LrView.bind 'conversionTool',
                },
            },
            f:row {
                f:static_text {
                    title = '增益图标准:',
                    alignment = 'right',
                    width = LrView.share 'label_width',
                },
                f:popup_menu {
                    items = {
                        { title = 'Apple 标准', value = 'apple' },
                        { title = 'ISO 标准', value = 'iso' },
                    },
                    value = LrView.bind 'gainMapStandard',
                    enabled = LrView.bind 'gainMapOptionsEnabled',
                },
            },
            f:row {
                f:static_text {
                    title = 'HEIC 主图位深:',
                    alignment = 'right',
                    width = LrView.share 'label_width',
                },
                f:popup_menu {
                    items = {
                        { title = '8 位', value = '8' },
                        { title = '10 位', value = '10' },
                    },
                    value = LrView.bind 'displayBitDepth',
                    enabled = LrView.bind 'gainMapOptionsEnabled',
                },
            },
            f:row {
                f:static_text {
                    title = '增益图缩小倍数:',
                    alignment = 'right',
                    width = LrView.share 'label_width',
                },
                f:slider {
                    value = LrView.bind 'gainMapScale',
                    min = 1,
                    max = 2,
                    width_in_chars = 20,
                    enabled = LrView.bind 'gainMapScaleEnabled',
                },
                f:edit_field {
                    value = LrView.bind 'gainMapScale',
                    min = 1,
                    max = 2,
                    precision = 2,
                    width_in_chars = 5,
                    enabled = LrView.bind 'gainMapScaleEnabled',
                },
            },
            f:row {
                f:static_text {
                    title = 'ISO 增益图品质:',
                    alignment = 'right',
                    width = LrView.share 'label_width',
                },
                f:checkbox {
                    title = '单独设置',
                    value = LrView.bind 'gainMapQualityEnabled',
                    enabled = LrView.bind 'gainMapQualityAvailable',
                },
                f:slider {
                    value = LrView.bind 'gainMapQuality',
                    min = 0,
                    max = 100,
                    width_in_chars = 15,
                    enabled = LrView.bind 'gainMapQualityEditable',
                },
                f:edit_field {
                    value = LrView.bind 'gainMapQuality',
                    min = 0,
                    max = 100,
                    precision = 0,
                    width_in_chars = 4,
                    enabled = LrView.bind 'gainMapQualityEditable',
                },
            },
            f:static_text {
                title = 'ISO 品质 0–100：越低体积越小，可能影响高光与渐变；关闭单独设置则沿用系统默认。',
            },
            f:static_text {
                title = '缩小倍数 1–2：1 保持原尺寸，2 将增益图宽高各减半，主图不变。',
            },
            f:static_text {
                title = '缩放适用于 Apple 和 ISO 增益图，位深指 HEIC 主图。',
            },
            f:row {
                f:static_text {
                    title = 'HEIC 重名时:',
                    alignment = 'right',
                    width = LrView.share 'label_width',
                },
                f:popup_menu {
                    items = {
                        { title = '自动改名（保留已有文件）', value = 'rename' },
                        { title = '跳过', value = 'skip' },
                        { title = '覆盖已有 HEIC', value = 'overwrite' },
                    },
                    value = LrView.bind 'heicCollisionHandling',
                },
            },
            f:static_text {
                title = 'HDR 模式自动使用 TIFF 16 位、HDR 色彩空间，开启 HDR 输出并关闭最大兼容。',
            },
            f:static_text {
                title = '直接 PQ／HLG HDR 固定输出 10 位，不含增益图；标准和缩放不适用。',
            },
        },
    }
end

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

exportServiceProvider.processRenderedPhotos = function(functionContext, exportContext)
    local exportSession = exportContext.exportSession
    local nPhotos = exportSession:countRenditions()
    local settings = exportContext.propertyTable
    local imageQuality = tonumber(settings.imageQuality or 70)
    local conversionTool = settings.conversionTool or 'toGainMapHDR'
    local gainMapStandard = settings.gainMapStandard or 'apple'
    local heicBitDepth = tostring(settings.heicBitDepth or '8')
    local gainMapScale = tonumber(settings.gainMapScale or 1)
    local gainQualityEnabled = conversionTool == 'toGainMapHDR' and gainMapStandard == 'iso' and settings.gainMapQualityEnabled == true
    local gainQuality = tonumber(settings.gainMapQuality or 80)
    local collision = settings.heicCollisionHandling or 'rename'
    local modes = { toGainMapHDR = gainMapStandard, pqHDR = 'pq', hlgHDR = 'hlg', sips = 'sips' }
    if not modes[conversionTool] or
        (conversionTool == 'toGainMapHDR' and gainMapStandard ~= 'apple' and gainMapStandard ~= 'iso') then
        LrDialogs.showError('请选择有效的 HEIC 输出模式和增益图标准。')
        return
    end
    if collision ~= 'rename' and collision ~= 'skip' and collision ~= 'overwrite' then
        LrDialogs.showError('请选择有效的 HEIC 重名处理方式。')
        return
    end
    if not imageQuality or not (imageQuality >= 0 and imageQuality <= 100) then
        LrDialogs.showError('图像品质必须为 0 到 100 之间的数字。')
        return
    end
    if conversionTool == 'toGainMapHDR' and
        ((heicBitDepth ~= '8' and heicBitDepth ~= '10') or
         not gainMapScale or not (gainMapScale >= 1 and gainMapScale <= 2)) then
        LrDialogs.showError('请选择 8／10 位主图，以及 1 到 2 之间的增益图缩小倍数。')
        return
    end
    if gainQualityEnabled and (not gainQuality or not (gainQuality >= 0 and gainQuality <= 100)) then
        LrDialogs.showError('ISO 增益图品质必须为 0 到 100 之间的数字。')
        return
    end
    if settings.LR_format ~= 'TIFF' or tonumber(settings.LR_export_bitDepth) ~= 16 or
        (conversionTool ~= 'sips' and
         (settings.LR_enableHDRDisplay ~= true or settings.LR_maximumCompatibility ~= false or
          type(settings.LR_export_colorSpace) ~= 'string' or not settings.LR_export_colorSpace:match('_hdr$'))) then
        LrDialogs.showError('中间格式设置无效，请重新打开导出窗口以自动配置 HDR TIFF。')
        return
    end
    local depth = conversionTool == 'toGainMapHDR' and heicBitDepth or '10'
    local scale = conversionTool == 'toGainMapHDR' and gainMapScale or 1
    local runner = LrPathUtils.child(_PLUGIN.path, 'HEICExport')
    local progressScope = LrProgressScope({ title = '正在导出 HEIC', functionContext = functionContext })
    local skipped = 0

    for i, rendition in exportSession:renditions() do
        if progressScope:isCanceled() then break end
        progressScope:setPortionComplete(i-1, nPhotos)
        local success, pathOrMessage = rendition:waitForRender()
        if success then
            local folder = LrPathUtils.parent(pathOrMessage)
            local logPath = LrPathUtils.child(LrPathUtils.getStandardFilePath('temp'),
                'heic-export-' .. LrUUID.generateUUID() .. '.log')
            local gainFlag = gainQualityEnabled and string.format(' --gain-quality %.4f', gainQuality / 100) or ''
            local command = string.format('%s %s %s --mode %s --depth %s --scale %.4f --quality %.4f%s --collision %s > %s 2>&1',
                shellQuote(runner), shellQuote(pathOrMessage), shellQuote(folder),
                modes[conversionTool], depth, scale, imageQuality / 100, gainFlag, collision, shellQuote(logPath))
            local result = LrTasks.execute(command)
            local readOK, log = pcall(LrFileUtils.readFile, logPath)
            LrFileUtils.delete(logPath)
            if result == 0 then
                LrFileUtils.delete(pathOrMessage)
            elseif result == 10 or result == 2560 then
                skipped = skipped + 1
                LrFileUtils.delete(pathOrMessage)
            else
                local detail = readOK and log and log ~= '' and log or ('错误码 ' .. tostring(result))
                LrDialogs.showError('HEIC 导出失败，中间 TIFF 已保留。\n' .. detail)
            end
        else
            LrDialogs.showError('无法渲染照片：' .. tostring(pathOrMessage))
        end
        progressScope:setPortionComplete(i, nPhotos)
    end
    progressScope:done()
    if skipped > 0 then
        LrDialogs.message('HEIC 导出完成', '因 HEIC 重名跳过了 ' .. tostring(skipped) .. ' 张照片。', 'info')
    end
end

return exportServiceProvider
