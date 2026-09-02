local M = {}

function M.to_table(val)
	if not val then
		return nil
	end
	return type(val) == "table" and val or { val }
end

function M.github(src)
	if src:match("^https?://") then
		return src
	end
	return "https://github.com/" .. src .. ".git"
end

function M.get_name(spec_or_str)
	if type(spec_or_str) == "string" then
		return spec_or_str:match("[^/]+$") or spec_or_str
	end
	return spec_or_str.name or spec_or_str.src:match("[^/]+$") or spec_or_str.src
end

function M.get_main(spec)
	if spec.main then
		return spec.main
	end

	local repo_name = spec.src:match("[^/]+$") or spec.src
	local norm_name =
		repo_name:lower():gsub("^n?vim%-", ""):gsub("%.n?vim$", ""):gsub("%-n?vim$", ""):gsub("[%.%-]lua$", "")

	if
		package.loaded[norm_name]
		or vim.api.nvim_get_runtime_file("lua/" .. norm_name .. "/init.lua", false)[1]
		or vim.api.nvim_get_runtime_file("lua/" .. norm_name .. ".lua", false)[1]
	then
		return norm_name
	end

	local raw_name = repo_name:gsub("%.n?vim$", ""):gsub("^n?vim%-", "")
	if
		vim.api.nvim_get_runtime_file("lua/" .. raw_name .. "/init.lua", false)[1]
		or vim.api.nvim_get_runtime_file("lua/" .. raw_name .. ".lua", false)[1]
	then
		return raw_name
	end

	return norm_name
end

function M.inherit_triggers(parent_spec, dep_spec)
	if parent_spec.event and not dep_spec.event then
		dep_spec.event = parent_spec.event
	end
	if parent_spec.ft and not dep_spec.ft then
		dep_spec.ft = parent_spec.ft
	end
	if parent_spec.cmd and not dep_spec.cmd then
		dep_spec.cmd = parent_spec.cmd
	end
	if parent_spec.keys and not dep_spec.keys then
		dep_spec.keys = parent_spec.keys
	end
end

function M.resolve_dependencies(specs)
	local sorted = {}
	local visited = {}
	local in_stack = {}

	local spec_map = {}
	for i = 1, #specs do
		local spec = specs[i]
		spec_map[get_name(spec)] = spec
	end

	local function visit(spec)
		local key = get_name(spec)
		if visited[key] then
			return
		end
		if in_stack[key] then
			vim.notify("[Smol] Circular dependency detected in plugin: " .. key, vim.log.levels.WARN)
			return
		end

		in_stack[key] = true

		if spec.dependencies then
			local deps = type(spec.dependencies) == "string" and { spec.dependencies } or spec.dependencies
			for i = 1, #deps do
				local dep = deps[i]
				local dep_spec = type(dep) == "string" and (spec_map[get_name(dep)] or { src = dep }) or dep
				visit(dep_spec)
			end
		end

		in_stack[key] = false
		visited[key] = true
		table.insert(sorted, spec)
	end

	for i = 1, #specs do
		visit(specs[i])
	end

	return sorted
end

-- TRIGGER HELPERS

function M.create_cmd_wrapper(cmd, load)
	vim.api.nvim_create_user_command(cmd, function(opts)
		pcall(vim.api.nvim_del_user_command, cmd)
		load()

		local range_prefix = ""
		if opts.range == 2 then
			range_prefix = opts.line1 .. "," .. opts.line2
		elseif opts.range == 1 then
			range_prefix = opts.line1
		end

		local bang = opts.bang and "!" or ""
		local args = (opts.args and #opts.args > 0) and (" " .. opts.args) or ""

		vim.cmd(range_prefix .. cmd .. bang .. args)
	end, { nargs = "*", bang = true, range = true })
end

function M.create_keymap_wrapper(mode, key_lhs, modes, desc, load)
	vim.keymap.set(mode, key_lhs, function()
		local count = vim.v.count > 0 and vim.v.count or ""

		for i = 1, #modes do
			pcall(vim.keymap.del, modes[i], key_lhs)
		end

		load()

		local esc_key = vim.api.nvim_replace_termcodes(count .. key_lhs, true, false, true)
		local has_map = vim.fn.maparg(key_lhs, mode, false, true)
		local feed_mode = (has_map and not vim.tbl_isempty(has_map)) and "m" or "i"

		vim.api.nvim_feedkeys(esc_key, feed_mode, false)
	end, { silent = true, desc = desc })
end

return M
