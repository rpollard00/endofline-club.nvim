if vim.g.loaded_endofline_club == 1 then
  return
end
vim.g.loaded_endofline_club = 1

require('endofline-club').setup()
