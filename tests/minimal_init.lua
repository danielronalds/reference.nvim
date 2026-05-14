local cwd = vim.fn.getcwd()
local cache_dir = cwd .. '/.tests'
local plenary_dir = cache_dir .. '/site/pack/vendor/start/plenary.nvim'

if vim.fn.isdirectory(plenary_dir) == 0 then
  vim.fn.mkdir(cache_dir, 'p')
  vim.fn.system({
    'git',
    'clone',
    '--depth',
    '1',
    'https://github.com/nvim-lua/plenary.nvim',
    plenary_dir,
  })
end

vim.opt.runtimepath:append(plenary_dir)
vim.opt.runtimepath:append(cwd)

vim.cmd('runtime plugin/plenary.vim')
