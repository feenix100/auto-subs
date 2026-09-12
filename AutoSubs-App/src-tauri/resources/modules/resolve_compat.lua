-- Compatibility bootstrap for DaVinci Resolve's embedded LuaJIT environment.
--
-- Resolve 21.1 can expose a reduced script environment where package/require
-- and bmd.readdir are unavailable even though loadfile, ffi, bmd, resolve, and
-- fusion are still present. AutoSubs depends on those helpers before its core
-- module can start, so restore only the pieces AutoSubs needs.
--
-- The bootstrap is intentionally a no-op when Resolve already provides the
-- normal APIs, which keeps older Resolve versions on their native code path.

---@diagnostic disable: undefined-global, lowercase-global
local M = {}

local STATE_KEY = "__AUTOSUBS_RESOLVE_COMPAT"
local state = rawget(_G, STATE_KEY)
if type(state) ~= "table" then
    state = {}
    rawset(_G, STATE_KEY, state)
end

local function log(message)
    print("[AutoSubs compat] " .. tostring(message))
end

local function package_config_for(sep)
    return sep .. "\n;\n?\n!\n-"
end

local function append_package_path(modules_path, sep)
    local module_pattern = modules_path .. sep .. "?.lua"
    if type(package.path) ~= "string" or package.path == "" then
        package.path = module_pattern
        return
    end

    if not package.path:find(module_pattern, 1, true) then
        package.path = package.path .. ";" .. module_pattern
    end
end

local function install_package_and_require(modules_path, sep)
    if type(package) ~= "table" then
        package = {
            loaded = {},
            path = "",
            config = package_config_for(sep),
        }
        log("installed minimal package table")
    else
        package.loaded = package.loaded or {}
        package.config = package.config or package_config_for(sep)
        package.path = package.path or ""
    end

    append_package_path(modules_path, sep)

    if type(require) == "function" then
        return
    end

    local function module_file(name)
        local relative = tostring(name):gsub("%.", sep):gsub("/", sep)
        return modules_path .. sep .. relative .. ".lua"
    end

    function require(name)
        name = tostring(name)

        if package.loaded[name] ~= nil then
            return package.loaded[name]
        end

        if name == "ffi" and ffi ~= nil then
            package.loaded[name] = ffi
            return ffi
        end
        if name == "bit" and bit ~= nil then
            package.loaded[name] = bit
            return bit
        end
        if name == "debug" and debug ~= nil then
            package.loaded[name] = debug
            return debug
        end

        local path = module_file(name)
        local chunk, load_err = loadfile(path)
        if not chunk then
            error(
                "module '" .. name .. "' could not be loaded from '" .. path .. "': " ..
                tostring(load_err),
                2
            )
        end

        package.loaded[name] = true
        local ok, result = pcall(chunk)
        if not ok then
            package.loaded[name] = nil
            error("error loading module '" .. name .. "': " .. tostring(result), 2)
        end

        if result ~= nil then
            package.loaded[name] = result
        end
        return package.loaded[name]
    end

    log("installed minimal require()")
end

local function install_windows_readdir()
    if ffi == nil or ffi.os ~= "Windows" then
        return
    end
    if bmd == nil then
        error("AutoSubs compatibility bootstrap requires Resolve's bmd global", 2)
    end
    if type(bmd.readdir) == "function" then
        return
    end

    if not state.windows_find_declared then
        local ok, err = pcall(function()
            ffi.cdef [[
                typedef void* AUTOSUBS_FIND_HANDLE;
                typedef unsigned long AUTOSUBS_DWORD;
                typedef int AUTOSUBS_BOOL;

                typedef struct _AUTOSUBS_WIN32_FIND_DATAA {
                    AUTOSUBS_DWORD dwFileAttributes;
                    AUTOSUBS_DWORD ftCreationTime_dwLowDateTime;
                    AUTOSUBS_DWORD ftCreationTime_dwHighDateTime;
                    AUTOSUBS_DWORD ftLastAccessTime_dwLowDateTime;
                    AUTOSUBS_DWORD ftLastAccessTime_dwHighDateTime;
                    AUTOSUBS_DWORD ftLastWriteTime_dwLowDateTime;
                    AUTOSUBS_DWORD ftLastWriteTime_dwHighDateTime;
                    AUTOSUBS_DWORD nFileSizeHigh;
                    AUTOSUBS_DWORD nFileSizeLow;
                    AUTOSUBS_DWORD dwReserved0;
                    AUTOSUBS_DWORD dwReserved1;
                    char cFileName[260];
                    char cAlternateFileName[14];
                } AUTOSUBS_WIN32_FIND_DATAA;

                AUTOSUBS_FIND_HANDLE FindFirstFileA(
                    const char* lpFileName,
                    AUTOSUBS_WIN32_FIND_DATAA* lpFindFileData
                );
                AUTOSUBS_BOOL FindNextFileA(
                    AUTOSUBS_FIND_HANDLE hFindFile,
                    AUTOSUBS_WIN32_FIND_DATAA* lpFindFileData
                );
                AUTOSUBS_BOOL FindClose(AUTOSUBS_FIND_HANDLE hFindFile);
            ]]
        end)

        if not ok then
            local text = tostring(err)
            if not text:lower():find("redefine", 1, true) then
                error("unable to install bmd.readdir compatibility: " .. text, 2)
            end
        end
        state.windows_find_declared = true
    end

    local kernel32 = ffi.load("kernel32")
    local invalid_handle = ffi.cast("AUTOSUBS_FIND_HANDLE", -1)

    bmd.readdir = function(pattern)
        if type(pattern) ~= "string" then
            error("bmd.readdir(): pattern must be a string", 2)
        end

        local parent = pattern:match("^(.*[\\/])[^\\/]*$") or ""
        local data = ffi.new("AUTOSUBS_WIN32_FIND_DATAA[1]")
        local handle = kernel32.FindFirstFileA(pattern, data)

        if handle == invalid_handle then
            return { Parent = parent }
        end

        local result = { Parent = parent }
        while true do
            local name = ffi.string(data[0].cFileName)
            if name ~= "." and name ~= ".." then
                local attributes = tonumber(data[0].dwFileAttributes) or 0
                result[#result + 1] = {
                    Name = name,
                    IsDir = math.floor(attributes / 0x10) % 2 == 1,
                }
            end

            if kernel32.FindNextFileA(handle, data) == 0 then
                break
            end
        end

        kernel32.FindClose(handle)
        return result
    end

    log("installed Windows bmd.readdir() fallback")
end

function M.bootstrap(modules_path)
    if type(modules_path) ~= "string" or modules_path == "" then
        error("AutoSubs compatibility bootstrap requires the modules folder path", 2)
    end
    if ffi == nil then
        error("AutoSubs compatibility bootstrap requires Resolve's LuaJIT ffi global", 2)
    end

    local sep = ffi.os == "Windows" and "\\" or "/"
    install_package_and_require(modules_path, sep)
    install_windows_readdir()
    return true
end

return M
