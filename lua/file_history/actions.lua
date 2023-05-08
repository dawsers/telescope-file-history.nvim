local actions = require("telescope.actions")
local actions_state = require("telescope.actions.state")
local pfiletype = require "plenary.filetype"
local fh = require('file_history')

local fh_actions = {}

local prepare_action = function(prompt_bufnr)
  local current_picker = actions_state.get_current_picker(prompt_bufnr)
  local win = current_picker.original_win_id
  local bufnr = vim.api.nvim_win_get_buf(win)
  actions.close(prompt_bufnr)
  local entry = actions_state.get_selected_entry()
  local parent_lines = fh.get_file(entry.fields.file, entry.fields.hash)
  return win, bufnr, entry, parent_lines
end

fh_actions.open_diff_tab = function(prompt_bufnr)
  local _, bufnr, _, parent_lines = prepare_action(prompt_bufnr)
  -- Open new tab
  vim.cmd('tabnew')
  -- Diff buffer with selected version
  local nwin = vim.api.nvim_get_current_win()
  local filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')
  local nbufnr = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_option(nbufnr, 'filetype', filetype)
  vim.api.nvim_buf_set_lines(nbufnr, 0, -1, true, parent_lines)
  vim.api.nvim_buf_set_option(nbufnr, 'modifiable', false)
  vim.api.nvim_win_set_buf(nwin, nbufnr)
  vim.cmd('vsplit')
  vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), bufnr)
  -- Diffthis!
  vim.cmd('windo diffthis')
end

fh_actions.revert_to_selected = function(prompt_bufnr)
  local _, bufnr, _, parent_lines = prepare_action(prompt_bufnr)
  -- Revert current buffer to selected version
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, parent_lines)
end

fh_actions.delete_history = function(prompt_bufnr)
  local picker = actions_state.get_current_picker(prompt_bufnr)
  -- If multi-selection, use those values, otherwise choose the selected entry
  local selections = #picker:get_multi_selection() > 0 and picker:get_multi_selection() or { actions_state.get_selected_entry() }
  actions.close(prompt_bufnr)
  for _, selection in ipairs(selections) do
    fh.delete_file(selection.fields.file)
  end
end

fh_actions.purge_history = function(prompt_bufnr)
  local picker = actions_state.get_current_picker(prompt_bufnr)
  -- If multi-selection, use those values, otherwise choose the selected entry
  local selections = #picker:get_multi_selection() > 0 and picker:get_multi_selection() or { actions_state.get_selected_entry() }
  actions.close(prompt_bufnr)
  for _, selection in ipairs(selections) do
    fh.purge_file(selection.fields.file)
  end
end

fh_actions.open_selected_hash = function(prompt_bufnr)
  local win, _, entry, parent_lines = prepare_action(prompt_bufnr)
  local nbufnr = vim.api.nvim_create_buf(true, false)
  local bufname = entry.fields.hash .. ':' .. entry.fields.file
  vim.api.nvim_buf_set_name(nbufnr, bufname)
  vim.api.nvim_buf_set_lines(nbufnr, 0, -1, true, parent_lines)
  local filetype = pfiletype.detect(entry.fields.file, {})
  vim.api.nvim_buf_set_option(nbufnr, 'filetype', filetype)
  -- Set as not modified
  vim.api.nvim_buf_set_option(nbufnr, 'modified', false)
  vim.api.nvim_win_set_buf(win, nbufnr)
end

return fh_actions

