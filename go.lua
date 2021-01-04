VERSION = "2.0.0"

local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local buffer = import("micro/buffer")
local os = import("os")
local fmt = import("fmt")
local strings = import("strings")

micro.Log("start")

config.RegisterCommonOption("go", "goimports", false)
config.RegisterCommonOption("go", "gofmt", true)

function init()
    config.MakeCommand("goimports", goimports, config.NoComplete)
    config.MakeCommand("gofmt", gofmt, config.NoComplete)
    config.MakeCommand("gorename", gorenameCmd, config.NoComplete)
    config.MakeCommand("goautocomplete", doAutocomplete, config.NoComplete)

    config.AddRuntimeFile("go", config.RTHelp, "help/go-plugin.md")

    config.MakeCommand("godef", godef, config.NoComplete)
    config.MakeCommand("selectnext", selectnext, config.NoComplete)
    config.MakeCommand("center", center, config.NoComplete)
    config.MakeCommand("gotofile", gotofile, config.NoComplete)
    config.MakeCommand("bm", bookmark, config.NoComplete)
    config.MakeCommand("goback", goback, config.NoComplete)
end

local done = 0

function center(bp)
	bp:Center()
end

function onSave(bp)
--    micro.Log("on save", done, bp.Buf:FileType(), bp.Buf.Settings["go.gomports"], bp.Buf.Settings["go.gofmt"])
    if done == 1 then
        return false
    end
    done = 1
    if bp.Buf:FileType() == "go" then
        if bp.Buf.Settings["go.goimports"] then
            micro.Log("do goimports", bp.Buf.Path)
            goimports(bp)
        elseif bp.Buf.Settings["go.gofmt"] then
            micro.Log("do gofmt", bp.Buf.Path)
            gofmt(bp)
        end
    end
    done = 0
    return true
end

function gofmt(bp, args)
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
            shell.JobSpawn("gorename", cmdargs, nil, renameStderr, renameExit, bp)
        else
            local cmdargs = {"--from", args[1], "--to", args[2]}
            shell.JobSpawn("gorename", cmdargs, nil, renameStderr, renameExit, bp)
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

function goimports(bp, args)
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
	if bp.Buf:Modified() then
		bp:Save()
	end
	local buf = bp.Buf
	local c = bp.Cursor
	local loc = buffer.Loc(c.X, c.Y)
	local offset = buffer.ByteOffset(loc, buf)
	local cmdargs = {"-f", buf.Path, "-o", tostring(offset)}
	micro.Log("godef", cmdargs)
	shell.JobSpawn("godef", cmdargs, godefStdout, godefStderr, godefExit, bp)
end

function godefStderr(err)
    micro.Log(err)
    micro.InfoBar():Message(err)
end

function godefExit(err)
    micro.Log(err)
    micro.InfoBar():Message(err)
end

function godefStdout(output, args)
    local bp = args[1]
    micro.Log("godef stdout:", output)
    parseOutput(bp, output, "%f:%l:%m")
end

function parseOutput(bp, output, errorformat)
    local lines = split(output, "\n")
    local regex = errorformat:gsub("%%f", "(..-)"):gsub("%%l", "(%d+)"):gsub("%%m", "(%d+)")
    for _,line in ipairs(lines) do
        -- Trim whitespace
        line = line:match("^%s*(.+)%s*$")
        micro.Log("line", line, "regex", regex)
        if string.find(line, regex) then
            micro.Log("found")
            bookmark(bp)
            local file, line, pos = string.match(line, regex)
            bp:HandleCommand("open "..file..":"..line..":"..pos)
            bp:Center()
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

function selectnext(bp, args)
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
		return
	end
	c:GotoLoc(found[1])
	c:SetSelectionStart(found[1])
	c:SetSelectionEnd(found[2])
	bp:Relocate()
end

function gotofile(bp, args)
	local c = bp.Cursor
	local line = bp.Buf:Line(c.Y)
	local cols = split(line, ":")
	local fname = cols[1]
	if #cols > 1 then
		fname = fname .. ":" .. cols[2]
	end
	bookmark(bp)
	micro.Log("s:", s, fname)
	bp:HandleCommand("tab "..fname)
end

bookmarks = {}
bookmark_idx = -1

function bookmark(bp)
	local buf = bp.Buf
	local c = bp.Cursor
	local loc = buffer.Loc(c.X, c.Y)
	local fpath = fmt.Sprintf("%s:%.0f:%.0f", buf.Path, c.Y+1, c.X+1)
	if #buf.Path > 0 then
		bookmark_idx = bookmark_idx + 1
		bookmarks[bookmark_idx] = fpath
		micro.Log("bookmark", fmt.Sprintf("%+v", bookmarks))
		micro.InfoBar():Message("bookmarked: "..fpath)
	end
end

function goback(bp)
	if bookmark_idx < 0 then
		micro.InfoBar():Message("no bookmarks")
		return
	end
	fpath = bookmarks[bookmark_idx]
	bookmark_idx = bookmark_idx - 1
	bp:HandleCommand("open "..fpath)
	bp:Center()
end

local completions = {}
local suggestions = {}

function completer()
	return completions, suggestions
end

local gocompletePane = nil

function gocodeExit(output, args)
	if gocompletePane ~= nil then
		gocompletePane:Quit()
		gocompletePane = nil
	end

	local found = strings.HasPrefix(output, "Found")
	if not found then
		return
	end

	local comp = {}
	local sugg = {}
	local s
	local arr = strings.Split(output, "\n")
	local chunk = args[2]
	
	for i = 1,#arr do
		local s = arr[i]
		if strings.HasPrefix(s, "  func ") then
			s = strings.TrimPrefix(s, "  func ")
			local cc = strings.Split(s, "(")
			s = cc[1]
			table.insert(sugg, s)
			s = strings.TrimPrefix(s, chunk)
			table.insert(comp, s)
		elseif strings.HasPrefix(s, "  var ") then
			s = strings.TrimPrefix(s, "  var ")
			local cc = strings.Split(s, " ")
			s = cc[1]
			table.insert(sugg, s)
			s = strings.TrimPrefix(s, chunk)
			table.insert(comp, s)
		else
			micro.Log("s: "..s)
		end
	end

	completions = comp
	suggestions = sugg

	-- local b = buffer.NewBuffer(output, "gocomplete")
	-- b.Type.Scratch = true
	-- b.Type.Readonly = true
	-- micro.CurPane():VSplitIndex(b, true)
	-- gocompletePane = micro.CurPane()
	local bp = args[1]
	bp.Buf:Autocomplete(completer)
end

function doAutocomplete(bp, args)
	bp.Buf:Save()

	local c = bp.Cursor
	local line = bp.Buf:Line(c.Y)
	local chunk = string.sub(line, 1, c.X)
	local cc = strings.Split(chunk, ".")
	if #cc == 2 then
		chunk = cc[2]
	end
	micro.Log("chunk: "..chunk)
	
	local loc = buffer.Loc(c.X, c.Y)
	local offs = buffer.ByteOffset(loc, c:Buf())

	local cmd = fmt.Sprintf("gocode -in %s autocomplete %.0f", c:Buf().AbsPath, offs)
	micro.Log("autcomplete: "..cmd)

	shell.JobStart(cmd, nil, nil, gocodeExit, bp, chunk)
end

-- function onRune(bp, r)
	-- micro.Log("rune: "..r)
	-- if gocompletePane == nil then
		-- return
	-- end
-- 
	-- local s = tostring(r)
	-- 
	-- if s == "q" then
		-- gocompletePane:Quit()
		-- gocompletePane = nil
		-- return
	-- end
-- 
	-- if s == "a" then
		-- gocompletePane:Quit()
		-- gocompletePane = nil
		-- return
	-- end
-- 
-- end
