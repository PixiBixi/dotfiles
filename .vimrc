"Basic settings
set t_Co=256
set backspace=2
set pastetoggle=<F2>
set tabstop=4
set softtabstop=4
set shiftwidth=4
set expandtab
set encoding=utf-8
set fileformat=unix
set fileformats=unix,dos
set noswapfile

" Utile pour NerdCommenter
let mapleader = ","

" Use incremental search and highlight as we go.
set hlsearch
set incsearch

" Dont split word
set linebreak

"Plugins
filetype off
set rtp+=~/.vim/bundle/Vundle.vim
let path='~/.vim/bundle'
call vundle#begin(path)

Plugin 'airblade/vim-gitgutter'
Plugin 'alvan/vim-closetag'
Plugin 'bling/vim-airline'
Plugin 'chr4/nginx.vim'
Plugin 'chr4/sslsecure.vim'
Plugin 'ervandew/supertab'
Plugin 'gmarik/vundle.vim'
Plugin 'jiangmiao/auto-pairs'
Plugin 'kien/ctrlp.vim'
Plugin 'mattn/emmet-vim'
Plugin 'mhinz/vim-rfc'
Plugin 'momota/cisco.vim'
Plugin 'nikvdp/ejs-syntax'
Plugin 'othree/html5.vim'
Plugin 'pangloss/vim-javascript'
Plugin 'pprovost/vim-ps1', {'for': 'ps1' } "PowerShell Plugin
Plugin 'rykka/riv.vim'
Plugin 'sickill/vim-monokai'
Plugin 'tpope/vim-fugitive'
Plugin 'tpope/vim-surround'
Plugin 'vim-airline/vim-airline-themes'

call vundle#end()
filetype plugin indent on

"Undo Dir
if !isdirectory($HOME."/.vim")
    call mkdir($HOME."/.vim", "", 0770)
endif
if !isdirectory($HOME."/.vim/undo-dir")
    call mkdir($HOME."/.vim/undo-dir", "", 0700)
endif
set undodir=~/.vim/undo-dir
set undofile

"Color
syntax on
try
    colorscheme monokai
catch /^Vim\%((\a\+)\)\=:E185/
    " deal with it
endtry
let g:airline_theme='molokai'
hi NonText ctermbg=none

"Status bar
set laststatus=2

"Shortcuts
nmap <S-t> :tabnew <CR>
nmap <S-Left> :tabprev <CR>
nmap <S-Right> :tabnext <CR>
nmap <C-f> /

nmap <silent> <C-S-Left> :bprevious<CR>
nmap <silent> <C-S-Right> :bnext<CR>

nmap <silent> <A-Up> :wincmd k<CR>
nmap <silent> <A-Down> :wincmd j<CR>
nmap <silent> <A-Left> :wincmd h<CR>
nmap <silent> <A-Right> :wincmd l<CR>

nmap <C-f> /

"CtrlP
let g:ctrlp_working_path_mode = 'ra'
set wildignore+=*/.git/*,*/.hg/*,*/.svn/*,*/.idea/*,*/.DS_Store,*/vendor,*/build,*/bin

" JS Shortcuts
au FileType javascript nmap <C-u> :UnMinify<CR>

" Conf files syntax
autocmd BufNewFile,BufRead *.conf   setf dosini

"Vim Airline
let g:airline_powerline_fonts = 1
let g:airline_section_x = '%{strftime("%m/%d %H:%M")}% '

" Functions
command! UnMinify call UnMinify()
function! UnMinify()
    %s/{\ze[^\r\n]/{\r/g
    %s/){/) {/g
    %s/};\?\ze[^\r\n]/\0\r/g
    %s/;\ze[^\r\n]/;\r/g
    %s/[^\s]\zs[=&|]\+\ze[^\s]/ \0 /g
    normal ggVG=
endfunction

" Pretty JSON (Require python)
command! PrettyJson call PrettyJson()
function! PrettyJson()
    execute "%!python -m json.tool"
endfunction

" .NFO specific
au BufReadPre *.nfo call SetFileEncodings('cp437')|set ambiwidth=single
au BufReadPost *.nfo call RestoreFileEncodings()


" Common code for encodings
function! SetFileEncodings(encodings)
  let b:myfileencodingsbak=&fileencodings
  let &fileencodings=a:encodings
endfunction

function! RestoreFileEncodings()
  let &fileencodings=b:myfileencodingsbak
  unlet b:myfileencodingsbak
endfunction

" YAML
autocmd Filetype yaml setlocal tabstop=2 softtabstop=2 shiftwidth=2

" XML
au FileType xml setlocal equalprg=xmllint\ --format\ --recover\ -\ 2>/dev/null

" Keep selection during indentation
" with the > and < keys
vnoremap > ><CR>gv
vnoremap < <<CR>gv 

" Toggle True/False
let g:switch_mapping = "-"

" Fix scrolling for tmux
set ttymouse=xterm2
set mouse=a
