# smol.nvim

Small plugin loader for Neovim using `vim.pack`.

```lua
require("smol").plugins({
	{
		src = "nvim-telescope/telescope.nvim",
		cmd = "Telescope",
		opts = {},
	},

	{
		src = "nvim-lualine/lualine.nvim",
		event = "VeryLazy",
		opts = {},
	},

	{
		src = "mason-org/mason-lspconfig.nvim",
		event = "BufReadPre",
		dependencies = {
			"mason-org/mason.nvim",
			"neovim/nvim-lspconfig",
		},
		opts = {},
	},
})
```

```lua
Smol.plugins(specs)
Smol.add(spec)
Smol.clean()
```
