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
3. Append the project root to an internal array keeping track of "which project roots should I run asset-bender for?"
4. If the currently running asset-bender process satisfies the new root, nothing happens
5. If the currently running asset-bender process does not satify the new root, it will quit the current process and start a new one


## Reset
If there is ever a time you would like to stop the current process, and reset the internal array of root directories, 
you can run `:lua require('asset-bender').reset()`. 

## Logging
`asset-bender.nvim` has logging builtin (using Plenary.log). The log is located at `~/.cache/nvim/asset-bender.log`. 

You can follow this log in realtime with:
```bash
tail -f ~/.cache/nvim/asset-bender.log
```

