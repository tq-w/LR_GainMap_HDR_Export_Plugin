local plugin = arg[1] or 'export_heic.lrdevplugin'
local commands, deleted, errors, messages = {}, {}, {}, {}
local exitCode, logText = 0, 'encoded output'
local exitSequence, recoveredSettings = {}, nil
local photo = {}
local source = "/tmp/Gain Map's $(echo unsafe)/photo.tif"
local modules = {
    LrTasks = {execute = function(command) commands[#commands+1] = command; return table.remove(exitSequence,1) or exitCode end, pcall=pcall},
    LrUUID = {generateUUID = function() return 'test-uuid' end},
    LrDialogs = {
        showError = function(text) errors[#errors+1] = text end,
        message = function(title, text) messages[#messages+1] = text end,
    },
    LrFileUtils = {
        readFile = function() return logText end,
        delete = function(path) deleted[#deleted+1] = path end,
    },
    LrPathUtils = {
        child = function(a,b) return a .. '/' .. b end,
        parent = function(path) return path:match('^(.*)/') end,
        getStandardFilePath = function() return '/tmp' end,
    },
    LrView = {bind = function(k) return k end, share = function(k) return k end},
    LrProgressScope = function() return {
        setPortionComplete = function() end, isCanceled = function() return false end,
        done = function() end,
    } end,
}
modules.LrExportSession = function(params)
    assert(params.photosToExport[1] == photo, 'recover the original rendition photo')
    recoveredSettings = params.exportSettings
    return {
        doExportOnCurrentTask = function() end,
        renditions = function() return ipairs({{waitForRender = function() return true, '/tmp/corrected.tif' end}}) end,
    }
end
function import(name) return modules[name] or {} end
_PLUGIN = {path = plugin}
local provider = dofile(plugin .. '/ExportServiceProvider.lua')
assert(provider.allowFileFormats[1] == 'TIFF' and #provider.allowFileFormats == 1)
local session = {
    countRenditions = function() return 1 end,
    renditions = function() return ipairs({{photo=photo, waitForRender = function() return true, source end}}) end,
}
local function run(settings, unconfigured)
    if not unconfigured then provider.updateExportSettings(settings) end
    local configured = false
    provider.processRenderedPhotos({}, {
        exportSession = session, propertyTable = settings,
        configureProgress = function()
            configured = true
            return modules.LrProgressScope()
        end,
        renditions = function(_, options)
            assert(configured, 'configure progress before starting the context renderer')
            assert(options.stopIfCanceled, 'cancellation must propagate to Lightroom')
            assert(settings.LR_format == 'TIFF' and settings.LR_export_bitDepth == 16,
                'normalize required settings before rendering without a dialog')
            return session:renditions()
        end,
    })
end
for _, mode in ipairs({'toGainMapHDR','pqHDR','hlgHDR','sips'}) do
    for _, policy in ipairs({'rename','skip','overwrite'}) do
        local settings = {conversionTool = mode, heicCollisionHandling = policy,
            LR_format = 'JPEG', LR_export_bitDepth = 8, LR_export_colorSpace = 'sRGB',
            LR_enableHDRDisplay = false, LR_maximumCompatibility = true, LR_collisionHandling = 'overwrite'}
        run(settings)
        assert(settings.LR_format == 'TIFF' and settings.LR_export_bitDepth == 16)
        assert(settings.LR_collisionHandling == 'rename', 'intermediate TIFF must not overwrite')
        if mode ~= 'sips' then
            assert(settings.LR_enableHDRDisplay and not settings.LR_maximumCompatibility)
            assert(settings.LR_export_colorSpace == 'p3_hdr')
        end
        local command = commands[#commands]
        local expected = ({toGainMapHDR='apple',pqHDR='pq',hlgHDR='hlg',sips='sips'})[mode]
        assert(command:find('--mode ' .. expected, 1, true))
        assert(command:find('--collision ' .. policy, 1, true))
        assert(command:find("Map'\\''s $(echo unsafe)", 1, true), 'unsafe shell path')
        if mode == 'pqHDR' or mode == 'hlgHDR' then
            assert(command:find('--depth 10 --scale 1.0000',1,true))
        end
    end
end
run({gainMapStandard='iso', heicBitDepth='10', gainMapScale=1.5})
assert(commands[#commands]:find('--mode iso --depth 10 --scale 1.5000',1,true))
local before = #commands
run({LR_format='JPEG'},true)
assert(#commands == before + 1 and #errors == 0, 'quick export must repair cached render settings')
before = #commands
run({heicCollisionHandling='bad'})
run({conversionTool='bad'})
run({gainMapScale=0/0})
run({imageQuality=101})
assert(#commands == before and #errors == 4)

deleted = {}
exitCode = 1
logText = '中间 TIFF 使用 SDR 色彩编码'
run({})
assert(#deleted == 1 and deleted[1]:match('%.log$'), 'failed rendition TIFF must be preserved')
assert(errors[#errors]:find(logText,1,true), 'encoder failure details were lost')
exitCode = 10
deleted = {}
run({heicCollisionHandling='skip'})
assert(deleted[#deleted] == source and #messages == 1)
exitCode = 0

local factory = setmetatable({}, {__index=function() return function(_,value) return value end end})
local props = {conversionTool='toGainMapHDR', heicBitDepth='8', imageQuality=70,
    LR_export_colorSpace='Rec2020_hdr', observers={}}
function props:addObserver(key,fn) self.observers[key]=fn end
provider.startDialog(props)
provider.sectionsForTopOfDialog(factory,props)
assert(props.LR_export_colorSpace == 'Rec2020_hdr', 'valid HDR color selection changed')
props.LR_maximumCompatibility = true
props.observers.LR_maximumCompatibility()
assert(not props.LR_maximumCompatibility)
props.LR_export_bitDepth = 8
props.observers.LR_export_bitDepth()
assert(props.LR_export_bitDepth == 16)
props.LR_enableHDRDisplay = false
props.observers.LR_enableHDRDisplay()
assert(props.LR_enableHDRDisplay)
props.conversionTool = 'hlgHDR'
props.observers.conversionTool()
props.observers.displayBitDepth()
assert(props.displayBitDepth == '10' and props.heicBitDepth == '8')
assert(not props.gainMapOptionsEnabled and not props.gainMapScaleEnabled)
props.conversionTool='toGainMapHDR'
props.observers.conversionTool()
assert(props.displayBitDepth == '8' and props.gainMapOptionsEnabled)
print('PASS: HDR render enforcement, final collision policies, all modes incl HLG, preset compatibility, paths, failure preservation')

-- Independent ISO gain-map quality must be opt-in and never leak to other modes.
run({gainMapStandard='iso',gainMapQualityEnabled=true,gainMapQuality=42})
assert(commands[#commands]:find('--gain-quality 0.4200',1,true))
for _,mode in ipairs({'toGainMapHDR','pqHDR','hlgHDR','sips'}) do
    run({conversionTool=mode,gainMapStandard='apple',gainMapQualityEnabled=true,gainMapQuality=42})
    assert(not commands[#commands]:find('--gain-quality',1,true))
end
local previous=#commands
run({gainMapStandard='iso',gainMapQualityEnabled=true,gainMapQuality=0/0})
run({gainMapStandard='iso',gainMapQualityEnabled=true,gainMapQuality=101})
assert(#commands==previous)
props.gainMapStandard='iso';props.gainMapQualityEnabled=false
props.observers.gainMapStandard()
assert(props.gainMapQualityAvailable and not props.gainMapQualityEditable)
props.gainMapQualityEnabled=true;props.observers.gainMapQualityEnabled()
assert(props.gainMapQualityEditable)
props.conversionTool='hlgHDR';props.observers.conversionTool()
assert(not props.gainMapQualityAvailable and not props.gainMapQualityEditable)
props.conversionTool='toGainMapHDR';props.observers.conversionTool()
assert(props.gainMapQualityEditable and props.gainMapQualityEnabled)
print('PASS: opt-in ISO quality command, validation and UI mode availability')

-- A headless invocation uses persisted HDR settings without startDialog/UI hooks.
run({conversionTool='toGainMapHDR',gainMapStandard='iso',heicBitDepth='10',
    gainMapScale=2,gainMapQualityEnabled=true,gainMapQuality=63,
    LR_format='JPEG',LR_export_bitDepth=8,LR_export_colorSpace='sRGB',
    LR_enableHDRDisplay=false,LR_maximumCompatibility=true},true)
assert(commands[#commands]:find('--mode iso --depth 10 --scale 2.0000 --quality 0.7000 --gain-quality 0.6300',1,true))
print('PASS: context render startup, no-dialog Export with Previous, persisted plugin parameters')

for _, status in ipairs({2,512}) do
    recoveredSettings=nil; deleted={}; exitSequence={status,0}
    local settings={gainMapStandard='iso',gainMapQualityEnabled=true,gainMapQuality=63,
        LR_renamingTokensOn=true, LR_tokens='custom-name', LR_reimportExportedPhoto=true}
    run(settings)
    assert(recoveredSettings and recoveredSettings.LR_format=='TIFF' and recoveredSettings.LR_export_bitDepth==16)
    assert(recoveredSettings.LR_exportServiceProvider=='com.adobe.ag.export.file', 'avoid recursive plugin invocation')
    assert(recoveredSettings.LR_tokens=='custom-name' and recoveredSettings.LR_export_destinationType=='specificFolder')
    assert(not recoveredSettings.LR_reimportExportedPhoto and settings.LR_reimportExportedPhoto)
    assert(commands[#commands]:find('/tmp/corrected.tif',1,true))
    assert(deleted[#deleted]==source and deleted[#deleted-1]=='/tmp/corrected.tif')
end
exitSequence={2,1}; deleted={}
run({})
for _, path in ipairs(deleted) do assert(path:match('%.log$'), 'failed recovery must preserve both intermediate files') end
exitSequence={2,2}; local initial=#commands
run({})
assert(#commands==initial+2, 'recovery must stop after one retry')
print('PASS: cached JPEG recovery from original photo, no recursion, preserved settings, cleanup and bounded retry')

-- Model the SDK observable table. Built-in pairs exposes private storage,
-- while :pairs returns real settings; passing the former into a new session
-- makes Lightroom ignore the overrides and render its cached JPEG defaults.
local values={gainMapStandard='iso',LR_tokens='observable-name',LR_size_maxWidth=2048}
local observable=setmetatable({['< contents >']=values}, {
    __index=function(_, key)
        if key=='pairs' then return function() return pairs(values) end end
        return values[key]
    end,
    __newindex=function(_, key, value) values[key]=value end,
})
exitSequence={2,0}; recoveredSettings=nil
run(observable, true)
assert(recoveredSettings.LR_tokens=='observable-name' and recoveredSettings.LR_size_maxWidth==2048)
assert(recoveredSettings['< contents >']==nil, 'never copy private observable storage')
assert(recoveredSettings.LR_format=='TIFF' and recoveredSettings.LR_export_colorSpace=='p3_hdr')
print('PASS: SDK observable settings copied through :pairs, without stale private storage')
