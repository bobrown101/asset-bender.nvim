local M = {}
local Job = require("plenary.job")
local log = require("vim.lsp.log")

local find_node_modules_ancestor = require("lspconfig").util.find_node_modules_ancestor
local path_join = require("lspconfig").util.path.join

local buffer_find_root_dir = require("bobrown101.plugin-utils").buffer_find_root_dir

local is_dir = require("bobrown101.plugin-utils").is_dir

local filetypes = require("asset-bender-filetypes").defaultConfig

local uv = vim.loop

local current_project_roots = {}
local current_process = nil

local function has_value(tab, val)
	for index, value in ipairs(tab) do
		if value == val then
			return true
		end
	end
	return false
end

local function reduce_array(arr, fn, init)
	local acc = init
	for k, v in ipairs(arr) do
		if 1 == k and not init then
			acc = v
		else
			acc = fn(acc, v)
		end
	end
	return acc
end

local jobId = 0

function trimString(s)
	return s:match("^%s*(.-)%s*$")
end

-- local function getLogPath() return vim.lsp.get_log_path() end

local function shutdownCurrentProcess()
	if current_process then
		log.info("asset-bender", "shutting down current process")
		uv.kill(-current_process.pid, uv.constants.SIGTERM)
		current_process = nil
	end
end

local function startAssetBenderProcess(rootsArray)
	log.info("asset-bender", "Asset Bender starting new client")

	local baseArgs = {
		"reactor",
		"host",
		"--host-most-recent",
		100,
	}

	local baseArgsWithWorkspaces = reduce_array(rootsArray, function(accumulator, current)
		table.insert(accumulator, current)
		return accumulator
	end, baseArgs)

	log.info("asset-bender", "Starting NEW asset-bender with args, " .. vim.inspect(baseArgsWithWorkspaces))

	local function jobLogger(data)
		if data ~= nil then
			local prefix = "asset-bender process #" .. jobId .. " - "
			log.info("asset-bender", prefix .. vim.inspect(data))
		end
	end

	local newJob = Job:new({
		command = "bend",
		args = baseArgsWithWorkspaces,
		detached = true,
		on_exit = function(j, signal)
			jobLogger("process exited")
			jobLogger(j:result())
			jobLogger(signal)
		end,
		on_stdout = function(error, data)
			jobLogger(data)
		end,
		on_stderr = function(error, data)
			jobLogger(data)
		end,
	})

	newJob:start()

	jobId = jobId + 1

	return newJob
end

function M.check_start_javascript_lsp()
	log.info("asset-bender", "Checking if we need to start a process")
	local bufnr = vim.api.nvim_get_current_buf()

	local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")
	-- Filter which files we are considering.
	if not filetypes[ft] then
		log.info(
			"asset-bender",
			"found this filetype that isnt what we're looking for: " .. ft .. " for buffer number: " .. bufnr
		)
		return
	end

	-- Try to find our root directory. We will define this as a directory which contains
	-- .git. Another choice would be to check for `package.json`, or for `node_modules`.
	local root_dir = buffer_find_root_dir(bufnr, function(dir)
		-- return is_dir(path_join(dir, 'node_modules'))
		-- return vim.fn.filereadable(path_join(dir, 'package.json')) == 1
		return is_dir(path_join(dir, ".git"))
	end)

	-- We couldn't find a root directory, so ignore this file.
	if not root_dir then
		log.info("asset-bender", "we couldnt find a root directory, ending")
		return
	end

	-- if the current root_dir is not in the current_project_roots, then we must stop the current process and start a new one with the new root
	if not has_value(current_project_roots, root_dir) then
		log.info("asset-bender", "detected new root, shutting down current process and starting another")

		shutdownCurrentProcess()

		table.insert(current_project_roots, root_dir)

		current_process = startAssetBenderProcess(current_project_roots)

		log.info("asset-bender", "started new process, " .. vim.inspect(current_process))
		log.info("asset-bender", "current roots" .. vim.inspect(current_project_roots))
	end
end

M.commandName = "BufEnter"
local function setupAutocommands()
	log.info("asset-bender", "setting up autocommands")
	local group = vim.api.nvim_create_augroup("asset-bender.nvim", { clear = true })

	log.info("asset-bender", "group created")
	vim.api.nvim_create_autocmd(M.commandName, {
		group = group,
		desc = "asset-bender.nvim will check if it needs to start a new process on the event: " .. M.commandName,
		callback = function()
			local data = {
				buf = vim.fn.expand("<abuf>"),
				file = vim.fn.expand("<afile>"),
				match = vim.fn.expand("<amatch>"),
			}
			vim.schedule(function()
				M.check_start_javascript_lsp()
			end)
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		desc = "shut down asset-bender process before exiting",
		callback = function()
			vim.schedule(M.stop)
		end,
	})

	log.info("asset-bender", "autocommand created")
	log.info("asset-bender", "Asset bender plugin intialized")
end

function M.stop()
	shutdownCurrentProcess()
end

function M.setup()
	setupAutocommands()
end

function M.reset()
	log.info(
		"asset-bender",
		'"reset" called - running LspStop, cancelling current asset-bender process, resetting roots, and running LspStart'
	)
	vim.cmd("LspStop")
	current_project_roots = {}
	shutdownCurrentProcess()
	vim.cmd("LspStart")
	print('Open a new file, or re-open an existing one with ":e" for asset-bender.nvim to start a new process')
end

function M.getTsServerPathForCurrentFile()
	function SplitFilename(strFilename)
		-- Returns the Path, Filename, and Extension as 3 values
		return string.match(strFilename, "(.-)([^\\]-([^\\%.]+))$")
	end
	local bufnr = vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(bufnr)

	local unused, file, ft = SplitFilename(path)

	local filetypes = {
		["js"] = true,
		["ts"] = true,
		["tsx"] = true,
		["jsx"] = true,
	}

	-- Filter which files we are considering.
	if not filetypes[ft] then
		log.trace(
			"asset-bender-tsserver-notification",
			"found this filetype that isnt what we're looking for: " .. ft .. " for buffer number: " .. bufnr
		)
		return "latest"
	end

	local directoryOfNodeModules = find_node_modules_ancestor(path)

	if directoryOfNodeModules == "" then
		log.trace(
			"asset-bender-tsserver-notification",
			"node_modules not found for current file, skipping auto-sense of hs-typescript/tsserver version"
		)
		return "latest"
	end

	log.trace(
		"asset-bender-tsserver-notification",
		"node_modules found at "
			.. directoryOfNodeModules
			.. " - will parse the package.json in that directory for the hs-typescript version"
	)

	local pathOfPackageJson = path_join(directoryOfNodeModules, "package.json")

	local getVersionResult = vim.system({ "jq", "-r", '.bpm.deps."hs-typescript"', pathOfPackageJson }, { text = true })
		:wait()

	if getVersionResult.stderr ~= "" then
		log.error("asset-bender-tsserver-notification", "there was an error reading hs-typescript version")
		log.error("asset-bender-tsserver-notification", getVersionResult.stderr)
		return "latest"
	end

	local hsTypescriptVersion = getVersionResult.stdout
	hsTypescriptVersion = hsTypescriptVersion:gsub('"', "")
	hsTypescriptVersion = hsTypescriptVersion:gsub("\n", "")
	log.trace("asset-bender-tsserver-notification", "found an hs-typescript version of " .. hsTypescriptVersion)

	local getHsTypescriptPathResult = vim.system(
		{ "bpx", "--path", string.format("hs-typescript@%s", hsTypescriptVersion) },
		{ text = true }
	):wait()

	if getHsTypescriptPathResult.stderr ~= "" then
		log.error(
			"asset-bender-tsserver-notification",
			"there was an error determining the path of hs-typescript from version number: " .. hsTypescriptVersion
		)
		log.error("asset-bender-tsserver-notification", getHsTypescriptPathResult.stderr)
		return "latest"
	end

	local hsTypescriptPath = getHsTypescriptPathResult.stdout
	hsTypescriptPath = hsTypescriptPath:gsub('"', "")
	hsTypescriptPath = hsTypescriptPath:gsub("\n", "")
	return hsTypescriptPath
end

return M
