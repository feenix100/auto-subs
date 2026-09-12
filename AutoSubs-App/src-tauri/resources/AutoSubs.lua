---These are global variables given to us by the Resolve embedded LuaJIT environment
---I disable the undefined global warnings for them to stop my editor from complaining
---@diagnostic disable: undefined-global
local ffi = ffi
local sep = ffi.os == "Windows" and "\\" or "/"

local function join_path(dir, filename)
    -- Remove trailing separator from dir, if any
    if dir:sub(-1) == sep then
        return dir .. filename
    else
        return dir .. sep .. filename
    end
end

-- Detect the operating system
local os_name = ffi.os
print("Operating System: " .. os_name)

-- Path to the script to launch
local resources_folder = nil
local app_executable = nil

-- On Windows the installer (hooks.nsi) generates AutoSubs.lua with the path baked in,
-- so this file is only ever run on macOS and Linux.
if os_name == "OSX" then
    app_executable = "/Applications/AutoSubs.app"
    resources_folder = app_executable .. "/Contents/Resources/resources"
else
    app_executable = "/usr/bin/autosubs"
    resources_folder = "/usr/lib/autosubs/resources"
end

-- For local development, use the "AutoSubs (Dev)" script instead of this file. Running
-- `npm run setup-resolve` generates a self-contained dev launcher that points
-- Resolve directly at your repo checkout and starts the server in dev mode.

-- Resolve 21.1 may hide package/require from Workspace scripts. Bootstrap the
-- minimal module environment AutoSubs needs before loading any modules.
local modules_path = join_path(resources_folder, "modules")
local compat_path = join_path(modules_path, "resolve_compat.lua")
local compat_chunk, compat_err = loadfile(compat_path)
if not compat_chunk then
    error("Could not load AutoSubs Resolve compatibility bootstrap: " .. tostring(compat_err))
end
local compat = compat_chunk()
if type(compat) ~= "table" or type(compat.bootstrap) ~= "function" then
    error("AutoSubs Resolve compatibility bootstrap returned an invalid module")
end
compat.bootstrap(modules_path)

-- Verify the AutoSubs resources actually exist before attempting to load them.
-- This guards against stale/duplicate installs (e.g. an old app left in a
-- different location) which otherwise produce a cryptic LuaJIT
-- "module 'autosubs_core' not found" stack trace listing many paths.
local function file_exists(path)
    if io ~= nil and type(io.open) == "function" then
        local f = io.open(path, "r")
        if f then
            f:close()
            return true
        end
        return false
    end

    -- Resolve 21.1 can omit io from the embedded script environment. loadfile
    -- is still exposed and is sufficient for checking a Lua resource file.
    local chunk = loadfile(path)
    return chunk ~= nil
end

local core_module_path = join_path(modules_path, "autosubs_core.lua")
if not file_exists(core_module_path) then
    print("[AutoSubs] ERROR: Could not find the AutoSubs app resources.")
    print("[AutoSubs] Expected to find: " .. core_module_path)
    print("[AutoSubs] The AutoSubs app does not appear to be installed at the expected location.")
    if os_name == "OSX" then
        print("[AutoSubs] Looked for the app at: " .. app_executable)
        print("[AutoSubs] If you have an older copy of AutoSubs installed elsewhere (e.g. /Applications/AutoSubs/AutoSubs.app),")
        print("[AutoSubs] delete it, then re-run the AutoSubs installer so the app lives at /Applications/AutoSubs.app.")
    else
        print("[AutoSubs] Please re-run the AutoSubs installer, then restart DaVinci Resolve.")
    end
    error("AutoSubs resources not found - please reinstall AutoSubs (see messages above).")
end

-- Launch AutoSubs
local AutoSubs = require("autosubs_core")
AutoSubs:Init(app_executable, resources_folder, false)
