local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local previewers = require "telescope.previewers"
local conf = require("telescope.config").values
local putils = require "telescope.previewers.utils"
local actions = require "telescope.actions"
local entry_display = require("telescope.pickers.entry_display")
local pfiletype = require "plenary.filetype"
local fh_actions = require("file_history.actions")

local fh = require('file_history')

local function split(str, sep)
  local result = {}
  for field in string.gmatch(str, ("[^%s]+"):format(sep)) do
    table.insert(result, field)
  end
  return result
end

local preview_file_history = function(opts, bufnr)
  return previewers.new_buffer_previewer({
    title = "File History",
    get_buffer_by_name = function(_, entry)
      return entry.value
    end,
    define_preview = function(self, entry, status)
      local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
      local parent_lines = fh.get_file(entry.fields.file, entry.fields.hash)
      local diff = vim.diff(table.concat(buffer_lines, '\n'), table.concat(parent_lines, '\n'),
      { result_type = 'unified', ctxlen = 3 })
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, true, split(diff, '\n'))
      putils.regex_highlighter(self.state.bufnr, "diff")
    end,
  })
end

local preview_file_query = function(opts)
  return previewers.new_buffer_previewer({
    title = "File Query",
    get_buffer_by_name = function(_, entry)
      return entry.value
    end,
    define_preview = function(self, entry, status)
      local lines = fh.get_file(entry.fields.file, entry.fields.hash)
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, true, lines)
      local filetype = pfiletype.detect(entry.fields.file, {})
      putils.highlighter(self.state.bufnr, filetype, {})
    end,
  })
end

local history_displayer = entry_display.create {
  separator = " ",
  items = {
    { width = 16 },
    { width = 32 },
    { remaining = true },
  },
}

local make_history_display = function(data)
  return history_displayer {
    { data.fields.time or "", "TelescopeFileHistoryTime" },
    { data.fields.date or "", "TelescopeFileHistoryDate" },
    { data.fields.tag or "", "TelescopeFileHistoryTag" }
  }
end

local files_displayer = entry_display.create {
  separator = " ",
  items = {
    { remaining = true },
  },
}
local make_files_display = function(data)
  return files_displayer {
    { data.fields.file or "", "TelescopeFileHistoryFile" }
  }
end

local query_displayer = entry_display.create {
  separator = " ",
  items = {
    { width = 32 },
    { width = 24 },
    { remaining = true },
  },
}

local make_query_display = function(data)
  return query_displayer {
    { data.fields.date or "", "TelescopeFileHistoryDate" },
    { data.fields.tag or "", "TelescopeFileHistoryTag" },
    { data.fields.file or "", "TelescopeFileHistoryFile" },
  }
end

local function file_history(opts)
  opts = opts or {}
  local results = fh.file_history(opts)
  if not results or vim.tbl_isempty(results) then
    return
  end

  local bufnr = vim.fn.bufnr()

  pickers.new(opts, {
    prompt_title = "FileHistory",
    finder = finders.new_table({
      results = vim.tbl_flatten(results),
      entry_maker = function(entry)
        if not entry or entry == '' then
          return
        end
        local fields = split(entry, '\x09')
        local result = {}
        result.value = entry
        result.fields = {
          time = fields[1],
          date = fields[2],
          hash = fields[3],
          file = fields[4],
          tag = fields[5] or ''
        }
        result.display = make_history_display
        result.ordinal = result.fields.tag .. ' ' .. result.fields.time .. ' ' .. result.fields.date
        return result
      end,
    }),
    previewer = preview_file_history(opts, bufnr),
    sorter = conf.file_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(fh_actions.open_selected_hash)
      map('i', '<M-d>', fh_actions.open_diff_tab)
      map('i', '<C-r>', fh_actions.revert_to_selected)
      return true
    end,
  }):find()
end

local function file_history_files(opts)
  opts = opts or {}
  local results = fh.file_history_files(opts)
  if not results or vim.tbl_isempty(results) then
    return
  end

  pickers.new(opts, {
    prompt_title = "FileHistoryFiles",
    finder = finders.new_table({
      results = vim.tbl_flatten(results),
      entry_maker = function(entry)
        if not entry or entry == '' then
          return
        end
        local result = {}
        --result.value = entry
        local hostname = vim.fn.hostname()
        local index = string.find(entry, '/')
        -- If file is local, enable preview
        if hostname == string.sub(entry, 1, index - 1) then
          result.value = string.sub(entry, index)
        else
          result.value = entry
        end
        result.fields = {
          file = entry,
        }
        result.display = make_files_display
        result.ordinal = result.fields.file
        return result
      end,
    }),
    previewer = conf.file_previewer(opts),
    sorter = conf.file_sorter(opts),
    attach_mappings = function(_, map)
      map('i', '<M-d>', fh_actions.delete_history)
      map('i', '<M-p>', fh_actions.purge_history)
      return true
    end,
  }):find()
end

local function file_history_query(opts)
  -- opts.after/opts.before need to have spaces escaped, for example:
  -- :Telescope file_history query after=3\ hours\ ago
  -- :Telescope file_history query after=2023-05-03\ 02:23:51 before=2023-05-07\ 12:23:11
  opts = opts or {}
  local results = fh.file_history_query(opts.after, opts.before)
  if not results or vim.tbl_isempty(results) then
    return
  end

  pickers.new(opts, {
    prompt_title = "FileHistoryQuery",
    finder = finders.new_table({
      results = vim.tbl_flatten(results),
      entry_maker = function(entry)
        if not entry or entry == '' then
          return
        end
        local fields = split(entry, '\x09')
        local result = {}
        result.value = entry
        result.fields = {
          date = fields[1],
          hash = fields[2],
          file = fields[3],
          tag = fields[4] or ''
        }
        result.display = make_query_display
        result.ordinal = result.fields.date .. ' ' .. result.fields.tag .. ' ' .. result.fields.file
        return result
      end,
    }),
    previewer = preview_file_query(opts),
    sorter = conf.file_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(fh_actions.open_selected_hash)
      return true
    end,
  }):find()
end

local function file_history_backup(opts)
  -- opts.tag needs to have spaces escaped, for example:
  -- :Telescope file_history backup tag=This\ is\ my\ tag
  opts = opts or {}
  fh.set_tag(opts.tag)
  vim.cmd("write")
end

-- Set default values for highlighting groups
vim.api.nvim_set_hl(0, 'TelescopeFileHistoryTime', { link = 'Number' })
vim.api.nvim_set_hl(0, 'TelescopeFileHistoryDate', { link = 'Function' })
vim.api.nvim_set_hl(0, 'TelescopeFileHistoryFile', { link = 'Keyword' })
vim.api.nvim_set_hl(0, 'TelescopeFileHistoryTag', { link = 'Comment' })


return require("telescope").register_extension({
  exports = {
    history = file_history,
    files = file_history_files,
    query = file_history_query,
    backup = file_history_backup
  },
})

