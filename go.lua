local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local buffer = import("micro/buffer")

micro.Log("start")

function init()
    config.RegisterCommonOption("goimports", false)
    config.RegisterCommonOption("gofmt", true)

    config.MakeCommand("goimports", "go.goimports", config.NoComplete)
    config.MakeCommand("gofmt", "go.gofmt", config.NoComplete)
    config.MakeCommand("gorename", "go.gorename", config.NoComplete)
    config.MakeCommand("godef", "go.godef", config.NoComplete)

    config.AddRuntimeFile("go", config.RTHelp, "help/go-plugin.md")
    config.TryBindKey("F6", "command-edit:gorename ", false)
    config.MakeCommand("gorename", "go.gorenameCmd", config.NoComplete)

    config.MakeCommand("selectnext", "go.selectnext", config.NoComplete)
    config.MakeCommand("center", "go.center", config.NoComplete)
    config.MakeCommand("gotofile", "go.gotofile", config.NoComplete)
    config.TryBindKey("F7", "command:gotofile", false)
end

local done = 0

function center(bp)
	bp:Center()
end

function onSave(bp)
    micro.Log("on save", done)
    if done == 1 then
        return false
    end
    done = 1
    if bp.Buf:FileType() == "go" then
        if bp.Buf.Settings["goimports"] then
            micro.Log("do goimports", bp.Buf.Path)
            goimports(bp)
        elseif bp.Buf.Settings["gofmt"] then
            micro.Log("do gofmt", bp.Buf.Path)
            gofmt(bp)
        end
    end
    done = 0
    return false
end

function gofmt(bp)
    bp:Save()
    local _, err = shell.RunCommand("gofmt -w " .. bp.Buf.Path)
    if err ~= nil then
        micro.InfoBar():Error(err)
        return
    end

    bp.Buf:ReOpen()
end

function gorenameCmd(bp, args)
    micro.Log(args)
    if #args == 0 then
        micro.InfoBar():Message("Not enough arguments")
    else
        bp:Save()
        local buf = bp.Buf
        if #args == 1 then
            local c = bp.Cursor
            local loc = buffer.Loc(c.X, c.Y)
            local offset = buffer.ByteOffset(loc, buf)
            local cmdargs = {"--offset", buf.Path .. ":#" .. tostring(offset), "--to", args[1]}
            shell.JobSpawn("gorename", cmdargs, "", "go.renameStderr", "go.renameExit", bp)
        else
            local cmdargs = {"--from", args[1], "--to", args[2]}
            shell.JobSpawn("gorename", cmdargs, "", "go.renameStderr", "go.renameExit", bp)
        end
        micro.InfoBar():Message("Renaming...")
    end
end

function renameStderr(err)
    micro.Log(err)
    micro.InfoBar():Message(err)
end

function renameExit(output, args)
    local bp = args[1]
    bp.Buf:ReOpen()
end

function goimports(bp)
    bp:Save()
    local _, err = shell.RunCommand("goimports -w " .. bp.Buf.Path)
    if err ~= nil then
        micro.InfoBar():Error(err)
        return
    end

    bp.Buf:ReOpen()
end

function godef(bp, args)
    micro.Log("godef")
    bp:Save()
    local buf = bp.Buf
    local c = bp.Cursor
    local loc = buffer.Loc(c.X, c.Y)
    local offset = buffer.ByteOffset(loc, buf)
    local cmdargs = {"-f", buf.Path, "-o", tostring(offset)}
    micro.Log("godef", cmdargs)
    shell.JobSpawn("godef", cmdargs, "", "go.godefStderr", "go.godefStdout", bp)
end

function godefStderr(err)
    micro.Log(err)
    micro.InfoBar():Message(err)
end

function godefStdout(output, args)
    local bp = args[1]
    micro.Log("godef stdout:", output)
    parseOutput(bp, output, "%f:%l:%d+")
end

function parseOutput(bp, output, errorformat)
    local lines = split(output, "\n")
    local regex = errorformat:gsub("%%f", "(..-)"):gsub("%%l", "(%d+)"):gsub("%%m", "(.+)")
    for _,line in ipairs(lines) do
        -- Trim whitespace
        line = line:match("^%s*(.+)%s*$")
        micro.Log("line", line, "regex", regex)
        if string.find(line, regex) then
            micro.Log("found")
            local file, line = string.match(line, regex)
            bp:HandleCommand("tab "..file..":"..line)
            micro.Log("godef:", file, line, bf)
        end
    end
end

function split(str, sep)
    local result = {}
    local regex = ("([^%s]+)"):format(sep)
    for each in str:gmatch(regex) do
        table.insert(result, each)
    end
    return result
end

function onBufPaneOpen(bp)
	micro.Log("bp open", bp.Buf.Path)
end

function selectnext(bp)
	local c = bp.Cursor
	local sel = ""
	if not c:HasSelection() then
		c:SelectWord()
	end
	sel = c:GetSelection()
	local bufstart = buffer.Loc(0, 0)
	local bufend = buffer.Loc(0, 1000000)
	local from = buffer.Loc(c.X+#sel, c.Y)
	found, res, err = bp.Buf:FindNext(sel, bufstart, bufend, from, true, false)
--	micro.Log("from:", from, "sel:", sel, "found:", found, res, err, found[1])
	if not res then
		return false
	end
	c:GotoLoc(found[1])
	c:SetSelectionStart(found[1])
	c:SetSelectionEnd(found[2])
	bp:Relocate()
	return true
end

function gotofile(bp)
	local c = bp.Cursor
	local line = bp.Buf:Line(c.Y)
	local cols = split(line, ":")
	micro.Log("s:", s, "cols:", cols)
	bp:HandleCommand("tab "..cols[1]..":"..cols[2])
end







