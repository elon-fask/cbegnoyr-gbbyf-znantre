#!/usr/bin/env lua
-- ==============================================================================
-- Portable Tools Manager — Lua Edition
-- Same manifest/log system as manager.sh, written in Lua for learning + cleaner logic.
-- Requires: lua 5.3+ and luafilesystem (lfs). If lfs is missing, the bash
-- manager.sh works as a fallback and can install lua + lfs for you.
-- ==============================================================================

local os = require("os")
local io = require("io")
local ok_lfs, lfs = pcall(require, "lfs")

-- ---- Configuration ----------------------------------------------------------
local USERNAME = os.getenv("USER") or os.getenv("USERNAME") or "atboulaa"
local ROOT = os.getenv("PORTABLE_TOOLS_ROOT") or ("/goinfre/" .. USERNAME .. "/portable_tools")
local DIRS = {
    bin       = ROOT .. "/bin",
    src       = ROOT .. "/src",
    build     = ROOT .. "/build",
    manifests = ROOT .. "/manifests",
    logs      = ROOT .. "/logs",
    tmp       = ROOT .. "/tmp",
    cache     = ROOT .. "/cache",
}

-- ---- Colors -----------------------------------------------------------------
local C = { reset="\27[0m", blue="\27[34m", green="\27[32m",
            yellow="\27[33m", red="\27[31m", cyan="\27[36m", bold="\27[1m" }

-- ---- Helpers ----------------------------------------------------------------
local function sh(cmd)
    local f = io.popen(cmd)
    local out = f:read("*a")
    f:close()
    return (out:gsub("\n$", ""))
end

local function log(msg)
    local date = sh("date +'%Y-%m-%d %H:%M:%S'")
    print(("[" .. date .. "] " .. msg))
end
local function info(s)  log(C.blue   .. "ℹ  " .. s .. C.reset) end
local function ok(s)    log(C.green  .. "✓  " .. s .. C.reset) end
local function warn(s)  log(C.yellow .. "⚠  " .. s .. C.reset) end
local function fail(s)  log(C.red    .. "✗  " .. s .. C.reset); os.exit(1) end

local function ensure_dirs()
    for _, d in pairs(DIRS) do
        if ok_lfs then
            lfs.mkdir(d)
        else
            os.execute("mkdir -p " .. d)
        end
    end
end

local function check_mount()
    local out = sh("df -P " .. ROOT .. " 2>/dev/null | tail -1 | awk '{print $6}'")
    if out:find("^/home") then
        fail("CRITICAL: " .. ROOT .. " is on /home (mount: " .. out .. "). Aborting.")
    end
    if not out:find("goinfre") then
        warn("Not under /goinfre (mount: " .. out .. "). Continuing with caution.")
    end
end

local function header(s)
    print("\n" .. C.bold .. C.cyan .. "=== " .. s .. " ===" .. C.reset .. "\n")
end

-- ---- Commands ---------------------------------------------------------------
local function cmd_list()
    header("Installed Tools")
    local files = sh("ls -1 " .. DIRS.manifests .. "/*.manifest 2>/dev/null")
    if files == "" then
        print("  (no tools installed yet)")
        return
    end
    for mf in files:gmatch("[^\n]+") do
        local f = io.open(mf)
        if f then
            local content = f:read("*a"); f:close()
            local name = content:match("name=([%w%-_]+)") or "?"
            local ver  = content:match("version=([%w%.%-]+)") or "?"
            local pref = content:match("install_prefix=(%S+)") or "?"
            print(string.format("  %-18s v%-14s → %s", name, ver, pref))
        end
    end
end

local function cmd_info(name)
    if not name then fail("Usage: lua manager.lua info <tool-name>") end
    local path = DIRS.manifests .. "/" .. name .. ".manifest"
    local f = io.open(path)
    if not f then fail("No manifest for '" .. name .. "'") end
    header(name .. " details")
    print(f:read("*a"))
    f:close()
end

local function cmd_check()
    header("Safety Check")
    ensure_dirs()
    check_mount()
    info("Tools root : " .. ROOT)
    info("Free space : " .. sh("df -h " .. ROOT .. " | tail -1 | awk '{print $4}'"))
    ok("All good.")
end

local function cmd_logs()
    header("Install History")
    print(sh("ls -lt " .. DIRS.logs .. " 2>/dev/null | head -15"))
    local latest = sh("ls -t " .. DIRS.logs .. "/install_*.log 2>/dev/null | head -1")
    if latest ~= "" then
        print("\n" .. C.bold .. "Latest: " .. latest .. C.reset)
        print(sh("tail -n 20 " .. latest))
    end
end

local function usage()
    print([[
Portable Tools Manager — Lua Edition

Usage: lua manager.lua <command> [tool-name]

Commands:
  list           Show installed tools
  info <name>    Show manifest details
  check          Verify mount point
  logs           View install history
  help           Show this message

For full install/uninstall/update functionality, use ./manager.sh (bash).
]])
end

-- ---- Dispatch ---------------------------------------------------------------
ensure_dirs()
check_mount()

local cmd = arg[1] or "help"
if cmd == "list" or cmd == "ls" then
    cmd_list()
elseif cmd == "info" or cmd == "show" then
    cmd_info(arg[2])
elseif cmd == "check" then
    cmd_check()
elseif cmd == "logs" or cmd == "history" then
    cmd_logs()
else
    usage()
end
