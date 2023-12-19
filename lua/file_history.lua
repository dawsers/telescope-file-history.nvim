local M = {}

local function make_dir(directory)
  if vim.fn.isdirectory(directory) == 0 then
    vim.fn.mkdir(directory, "p")
  end
end

local function array_append(array, extra)
  for _, v in ipairs(extra) do
    table.insert(array, v)
  end
  return array
end

local FileHistory = {
  basedir = '',
  git_cmd = '',
  hostname = '',
  tag = nil,

  init = function (self, basedir, git_cmd)
    self.basedir = vim.fn.expand(basedir) .. "/"
    self.git_cmd = git_cmd
    self.hostname = vim.fn.hostname()
  end,

  _build_git_command = function (self, args)
    local repoargs = { self.git_cmd, "--work-tree", self.basedir, "--git-dir", self.basedir .. ".git" }
    repoargs = array_append(repoargs, args)
    return repoargs
  end,

  _git_command = function (self, args)
    local command = self:_build_git_command(args)
    local proc = {
      job_id = 0,
      exit_code = 0,
      stdout = {},
      stderr = {},
    }
    proc.job_id =  vim.fn.jobstart(command, {
      stdout_buffered = true,
      on_stdout = function (chan_id, data, name)
        if data then
          table.insert(proc.stdout, data)
        end
      end,
      on_stderr = function (chan_id, data, name)
        if data then
          table.insert(proc.stderr, data)
        end
      end,
      on_exit = function (chan_id, data, name)
        if data then
          proc.exit_code = data
        end
      end,
    })
    vim.fn.jobwait({ proc.job_id })
    return proc
  end,

  _init_git = function (self)
    if vim.fn.isdirectory(self.basedir .. ".git") == 0 then
      self:_git_command({ 'init' })
      self:_git_command({ 'config', '--local', 'user.email', 'file-history@noemail.com' })
      self:_git_command({ 'config', '--local', 'user.name', 'file-history' })
      self:_git_command({ 'config', '--local', 'commit.gpgSign', 'false' })
    end
  end,

  _make_backup_dir = function (self, dirname)
    -- Create the history backup directory
    make_dir(dirname)
    self:_init_git()
  end,

  backup_file = function (self, dirname, filename)
    -- Create a snapshot of the file in the .git repository
    local backupdir = self.basedir .. self.hostname .. dirname
    local backuppath = backupdir .. "/" .. filename
    self:_make_backup_dir(backupdir)
    -- Copy the file
    local file = vim.fn.readfile(dirname .. "/" .. filename, "b")
    vim.fn.writefile(file, backuppath, "b")
    -- Add it to the git repository
    self:_git_command({ 'add', backuppath })
    local proc = self:_git_command({ 'diff-index', '--quiet', 'HEAD', '--', backuppath })
    if proc.exit_code ~= 0 then
      local message = dirname .. '/' .. filename
      if self.tag then
        message = message .. '\x09' .. self.tag
        -- Reset tag after one use
        self.tag = nil
      end
      proc = self:_git_command({ 'commit', '-m', message, backuppath })
    end
    return proc
  end,

  get_file = function (self, filename, hash)
    local backuppath = self.hostname .. filename
    return self:_git_command({ 'show', hash .. ':' .. backuppath })
  end,

  get_log = function (self, filename, hash)
    local backuppath = self.hostname .. filename
    return self:_git_command({ 'show', hash, '--', backuppath })
  end,

  delete_file = function (self, filename)
    -- filename includes hostname
    local backuppath = filename
    -- https://stackoverflow.com/questions/2047465/how-do-i-delete-a-file-from-a-git-repository
    -- Remove it only from repo
    local proc = self:_git_command({ 'rm', '--cached', backuppath })
    if proc.exit_code ~= 0 then
      proc = self:_git_command({ 'commit', '-m', 'remove ' .. backuppath })
    end
    return proc
  end,

  purge_file = function (self, filename)
    -- filename includes hostname
    local backuppath = filename
    -- git filter-branch --index-filter -f "git rm -rf --cached --ignore-unmatch backuppath" HEAD
    -- Better use filter-repo (dependency). It is much more reliable and faster
    local proc = self:_git_command({ 'filter-repo', '--force', '--invert-paths', '--path', backuppath })
    return proc
  end,

  file_history = function (self, dirname, filename)
    -- List all the revisions of a file in the .git repository
    local backuppath = self.basedir .. self.hostname .. dirname .. "/" .. filename
    return self:_git_command({ 'log', '--format=%ar%x09%ad%x09%H%x09%s', "--", backuppath })
  end,

  list_files = function (self)
    -- List all the files in the .git repository
    return self:_git_command({ 'ls-files' })
  end,

  query_files = function (self, after, before)
    -- List all the commits to the .git repository between two dates
    -- The format can be:
    -- after=YYYY-MM-DD:HH:MM:SS or somwthing like
    -- after=3\ hours\ ago
    local query = { 'log', '--all', '--format=%ad%x09%H%x09%s' }
    if after then
      query = array_append(query, { '--after=' .. after })
    end
    if before then
      query = array_append(query, { '--before=' .. before })
    end
    return self:_git_command(query)
  end,

  set_tag = function (self, tag)
    self.tag = tag
  end
}


local defaults = {
  backup_dir = "~/.file-history-git",
  git_cmd = "git",
}

M.config = {}

M.file_history = function(opts)
  local proc = FileHistory:file_history(vim.fn.expand("%:p:h"), vim.fn.expand("%:t"))
  return proc.stdout
end

M.set_tag = function(tag)
  FileHistory:set_tag(tag)
end

M.file_history_files = function(opts)
  local proc = FileHistory:list_files()
  return proc.stdout
end

M.file_history_query = function(after, before)
  local proc = FileHistory:query_files(after, before)
  return proc.stdout
end

M.get_file = function(filename, hash)
  local proc = FileHistory:get_file(filename, hash)
  return vim.tbl_flatten(proc.stdout)
end

M.get_log = function(filename, hash)
  local proc = FileHistory:get_log(filename, hash)
  return vim.tbl_flatten(proc.stdout)
end

M.delete_file = function(filename)
  local proc = FileHistory:delete_file(filename)
end

M.purge_file = function(filename)
  local proc = FileHistory:purge_file(filename)
end

M.setup = function (opts)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})
  FileHistory:init(M.config.backup_dir, M.config.git_cmd)

  vim.api.nvim_create_autocmd({ "BufWritePost" }, {
    group = vim.api.nvim_create_augroup("file_history_group", { clear = true }),
    callback = function ()
      FileHistory:backup_file(vim.fn.expand("%:p:h"), vim.fn.expand("%:t"))
    end,
  })

end

return M
