# asset-bender.nvim
Automatically start an asset-bender process

## Setup

```lua
require("packer").startup(function()

    use({"bobrown101/plugin-utils.nvim"})
    use({
        "bobrown101/asset-bender.nvim",
        requires = {"bobrown101/plugin-utils.nvim"},
        config = function() require("asset-bender").setup({}) end
    })

end)
```

## How does it work?
`asset-bender.nvim` creates an autocommand attached to "BufReadPost" (it is scoped under the group `asset-bender.nvim`).
This autocommand will then do the following:
1. Check to see that the current buffer is relevent (aka - is a javascript/typescript file)
2. Find the closest git directory (signifying the project root)
3. See if there is already an asset-bender process running for this project root, and if not, start one

## Logging
```bash
tail -f ~/.cache/nvim/asset-bender.log
```

