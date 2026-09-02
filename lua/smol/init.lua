local utils = require("smol.utils")

local M = {}
M.declared_plugins = {}

local gr = vim.api.nvim_create_augroup("smol", { clear = true })
local plugin_loaders = {}

-- CORE FUNCTIONS

function M.register(spec)
	local src = utils.github(spec.src)
	local name = utils.get_name(spec)
	local loaded = false

	local function load()
		if loaded then
			return
		end

		if spec.dependencies then
			local deps = type(spec.dependencies) == "string" and { spec.dependencies } or spec.dependencies
			for i = 1, #deps do
				local dep_loader = plugin_loaders[utils.get_name(deps[i])]
				if dep_loader then
					dep_loader()
				end
			end
		end

		loaded = true
		vim.pack.add({ { src = src } }, { load = true })

		local opts = spec.opts == true and {} or spec.opts
		if spec.config then
			spec.config(opts or {})
		elseif opts then
			local main = utils.get_main(spec)
			local ok, mod = pcall(require, main)
			if ok and type(mod) == "table" and type(mod.setup) == "function" then
				mod.setup(opts)
			else
				vim.notify("[Smol] Could not auto-setup module: " .. tostring(main), vim.log.levels.WARN)
			end
		end
	end

	plugin_loaders[name] = load
	spec._load = load
end

function M.setup_triggers(spec)
	local load = spec._load
	local has_trigger = spec.event or spec.ft or spec.cmd or spec.keys

	if spec.lazy == false or not has_trigger then
		load()
		return
	end

	local fts = utils.to_table(spec.ft)
	if fts then
		vim.api.nvim_create_autocmd("FileType", { group = gr, pattern = fts, once = true, callback = load })
	end

	local events = utils.to_table(spec.event)
	if events then
		vim.api.nvim_create_autocmd(events, { group = gr, once = true, callback = load })
	end

	local cmds = utils.to_table(spec.cmd)
	if cmds then
		for i = 1, #cmds do
			utils.create_cmd_wrapper(cmds[i], load)
		end
	end

	if spec.keys then
		local keys_list = spec.keys
		if
			type(keys_list) == "string"
			or (
				type(keys_list) == "table"
				and type(keys_list[1]) == "string"
				and (keys_list[2] or keys_list.mode or keys_list.desc)
			)
		then
			keys_list = { keys_list }
		end

		for i = 1, #keys_list do
			local k = keys_list[i]
			local key_lhs = type(k) == "table" and k[1] or k
			local modes = utils.to_table((type(k) == "table" and k.mode) or "n")
			local desc = (type(k) == "table" and k.desc) or "Lazy load plugin"

			for j = 1, #modes do
				utils.create_keymap_wrapper(utils.modes[j], key_lhs, modes, desc, load)
			end
		end
	end
end

function M.plugins(specs)
	local sorted_initial = vim.deepcopy(specs)
	table.sort(sorted_initial, function(a, b)
		return (a.priority or 50) > (b.priority or 50)
	end)

	local resolved = utils.resolve_dependencies(sorted_initial)
	local spec_map = {}

	for i = 1, #resolved do
		local spec = resolved[i]
		spec_map[utils.get_name(spec)] = spec
	end

	-- Inherit parent triggers down to child dependencies
	for i = 1, #resolved do
		local spec = resolved[i]
		if spec.dependencies then
			local deps = type(spec.dependencies) == "string" and { spec.dependencies } or spec.dependencies
			for j = 1, #deps do
				local dep_spec = spec_map[utils.get_name(deps[j])]
				if dep_spec then
					utils.inherit_triggers(spec, dep_spec)
				end
			end
		end
	end

	-- Register & set up triggers
	for i = 1, #resolved do
		local spec = resolved[i]
		local name = utils.get_name(spec)
		M.declared_plugins[name] = true
		M.register(spec)
	end

	for i = 1, #resolved do
		M.setup_triggers(resolved[i])
	end
end

function M.add(spec)
	M.plugins({ spec })
end

M.clean = function()
	local active_plugins = {}
	local unused_plugins = {}
	local installed = vim.pack.get()

	for i = 1, #installed do
		active_plugins[installed[i].spec.name] = installed[i].active
	end

	for i = 1, #installed do
		local name = installed[i].spec.name
		if not active_plugins[name] then
			table.insert(unused_plugins, name)
		end
	end

	if #unused_plugins == 0 then
		vim.notify("[Smol] No unused plugins to clean.", vim.log.levels.INFO)
		return
	end

	vim.ui.select({ "Yes", "No" }, {
		prompt = "Remove unused plugins: " .. table.concat(unused_plugins, ", ") .. "?",
	}, function(choice)
		if choice == "Yes" then
			vim.pack.del(unused_plugins)
			vim.notify("[Smol] Cleaned unused plugins.", vim.log.levels.INFO)
		end
	end)
end

return M
