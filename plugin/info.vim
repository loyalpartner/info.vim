" Author: Alejandro "HiPhish" Sanchez
" License:  The MIT License (MIT) {{{
"    Copyright (c) 2016 HiPhish
"
"    Permission is hereby granted, free of charge, to any person obtaining a
"    copy of this software and associated documentation files (the
"    "Software"), to deal in the Software without restriction, including
"    without limitation the rights to use, copy, modify, merge, publish,
"    distribute, sublicense, and/or sell copies of the Software, and to permit
"    persons to whom the Software is furnished to do so, subject to the
"    following conditions:
"
"    The above copyright notice and this permission notice shall be included
"    in all copies or substantial portions of the Software.
"
"    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
"    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
"    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
"    NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
"    DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
"    OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
"    USE OR OTHER DEALINGS IN THE SOFTWARE.
" }}}


if exists('g:loaded_info')
  finish
endif
let g:loaded_info = 1

" This is the program that assembles info files, we might later decide to make
" it possible to define your own one.
if !exists('g:infoprg')
	let g:infoprg = 'info'
endif

command! -nargs=* Info call <SID>info(<q-mods>, <f-args>)

nnoremap <Plug>InfoUp   :call <SID>up()<CR>
nnoremap <Plug>InfoNext :call <SID>next()<CR>
nnoremap <Plug>InfoPrev :call <SID>prev()<CR>
nnoremap <Plug>InfoMenu :call <SID>menuPrompt()<CR>

augroup InfoFiletype
	autocmd!

	autocmd FileType info command! -buffer
		\ -complete=customlist,<SID>completeMenu -nargs=?
		\ Menu call <SID>menu(<q-args>)

	autocmd FileType info command! -buffer
		\ -nargs=?
		\ Follow call info#followReference(<q-args>)

	autocmd FileType info command! -buffer   UpNode  call <SID>up()
	autocmd FileType info command! -buffer NextNode  call <SID>next()
	autocmd FileType info command! -buffer PrevNode  call <SID>prev()


	autocmd BufReadCmd info://* call <SID>followReference(<SID>decodeURI(expand('<amatch>')))
augroup END

let s:referencePattern = '\v\*([Nn]ote\s+)?[^:]+\:(\:|[^.]+\.)'
" Test-cases for the reference pattern
" *Note Directory: (dir)Top.
" *Directory::
" *Directory: (dir)Top.


" Completion function {{{1

function! s:SID()
	return '<SNR>'.matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$').'_'
endfunction

" Filter the menu list for entries which match non-magic, case-insensitive and
" only at the beginning of the string.
function! s:completeMenu(ArgLead, CmdLine, CursorPos)
	call s:buildMenu()
	let l:menu = b:info['Menu']
	let l:candidates = []

	for l:entry in l:menu
		" Match only at the beginning of the string
		if empty(a:ArgLead) || !empty(matchstr(l:entry['description'], '\c\M^'.a:ArgLead))
			call add(l:candidates, l:entry['description'])
		endif
	endfor

	return l:candidates
endfunction


" Reading functions {{{1
"
" The entry function, invoked by the ':Info' command. Its purpose is to find
" the file and options from the arguments
function! s:info(mods, ...)
	let l:file = ''
	let l:node = ''

	if a:0 > 0
		let l:file = a:1
	endif

	if a:0 > 1
		let l:node = a:2
	endif

	let l:bufname = s:encodeURI(l:file, l:node, '')

	" The following will trigger the autocommand of editing an info:// file
	if a:mods !~# 'tab' && s:find_info_window()
		execute 'silent edit' l:bufname
	else
		execute 'silent' a:mods 'split' l:bufname
	endif

	echo 'Welcome to Info. Type g? for help.'
endfunction



" Here the heavy heavy lifting happens: we set the options for the buffer and
" load the info document.
function! s:readInfo(file, node, ...)
	" We will lock it after assembly
	setlocal modifiable
	setlocal readonly
	setlocal noswapfile
	setlocal buftype=nofile
	setlocal bufhidden=hide

	" TODO: We first have to check if file and node even exist
	silent keepjumps %delete _

	" Make sure to redirect the standard error into the void and quote the
	" name of the file and node (they may contain spaces and parentheses).
	let l:cmd = g:infoprg.' -f '''.a:file.''' -n '''.a:node.''' -o - 2>/dev/null'
	" And adjust the redirection syntax for special snowflake shells
	if &shell =~# 'fish$'
		let l:cmd = substitute(l:cmd, '\v2\>\/dev\/null$', '^/dev/null')
	endif

	put =system(l:cmd)
	" Putting has produced an empty line at the top, remove that
    silent keepjumps 1delete _

    normal! gg

	" Now lock the file and set all the remaining options
	setlocal filetype=info
	setlocal nonumber
	setlocal norelativenumber
	setlocal nomodifiable
	setlocal nomodified
	setlocal foldcolumn=0
	setlocal colorcolumn=0
	setlocal nolist
	setlocal nospell

	let b:info = s:parseNodeHeader()
endfunction


" Parses the information from the node header and returns a dictionary
" representing it.
function! s:parseNodeHeader()
	let l:info = {}

	" We assume that the header is the first line. Split the header into
	" key-value pairs.
	let l:pairs = split(getline(1), ',')

	for l:pair in l:pairs
		" A key is terminated by a colon and might have leading whitespace.
		let l:key = matchstr(l:pair, '\v^\s*\zs[^:]+')
		" The value might have leading whitespace as well
		let l:value = matchstr(l:pair, '\v^\s*[^:]+\:\s*\zs[^,]+')
		let l:info[l:key] = l:value
	endfor

	return l:info
endfunction



" Try finding an exising 'info' window in the current tab. Returns 0 if no
" window was found.
function! s:find_info_window() abort
	" Try the windows in the following order:
	"   - If the current window matches use it
	"   - If there is only one window (first window is last) do not use it
	"   - Cycle through all windows until one is found
	"   - If none was found return 0
	if &filetype ==# 'info'
		return 1
	elseif winnr('$') ==# 1
		return 0
	endif
	let thiswin = winnr()
	while 1
		wincmd w
		if &filetype ==# 'info'
			return 1
		elseif thiswin ==# winnr()
			return 0
		endif
	endwhile
endfunction


" Navigation functions {{{1

" Jump to the next node
function! s:next()
	call s:jumpToProperty('Next')
endfunction

" Jump to the next node
function! s:prev()
	call s:jumpToProperty('Prev')
endfunction

" Jump to the next node
function! s:up()
	call s:jumpToProperty('Up')
endfunction

" Common code for next, previous, and so on nodes
function! s:jumpToProperty(property)
	if exists('b:info['''.a:property.''']')
		" The node name might contain a file name: (file)Node
		let l:file = matchstr(b:info[a:property], '\v^\(\zs[^)]+\ze\)')
		if empty(file)
			let l:file = b:info['File']
		endif

		let l:uri = s:encodeURI(l:file, b:info[a:property], '')
		" We have to escape the percent signs or it will be replaced with the
		" file name in the ':edit'
		let l:uri = substitute(l:uri, '\v\%', '\\%', 'g')

		execute 'silent edit '.l:uri
	else
		echohl ErrorMsg | echo 'No '''.a:property.''' pointer for this node.' | echohl None
	endif
endfunction


" Menu functions {{{1

function s:menuPrompt()
	let l:entry = input('Menu item: ', '', 'customlist,'.s:SID().'completeMenu')
	call s:menu(l:entry)
endfunction

function! s:menu(entry)
	if a:entry == ''
		call s:menuLocationList()
		lopen
		return
	endif

	call s:buildMenu()
	for l:entry in b:info['Menu']
		if l:entry['description'] =~? a:entry
			let l:uri = s:encodeURI(l:entry['file'], l:entry['node'], '')
			let l:uri = substitute(l:uri, '\v\%', '\\%', 'g')

			execute 'silent edit '.l:uri
			return
		endif
	endfor

	echohl ErrorMsg
	echo 'Cannot find menu entry ' . a:entry
	echohl None
endfunction


" Build up a list of menu entries in a node.
function! s:buildMenu()
	" This function will be called lazily when we need a menu. Don't rebuild
	" it is one already exists.
	if exists('b:info[''Menu'']')
		return
	endif

	let l:save_cursor = getcurpos()
	let b:info['Menu'] = []
	let l:menuLine = search('\v^\* [Mm]enu\:')

	if l:menuLine == 0
		return
	endif

	" Process entries by searching down from the menu line. Don't wrap to the
	" beginning of the file or we will be stuck in an infinite loop.
	let l:entryLine = search('\v^\*[^:]+\:', 'W')
	while l:entryLine != 0
		call add(b:info['Menu'], s:decodeReference(getline(l:entryLine)))
		let l:entryLine = search('\v^\*[^:]+\:', 'W')
	endwhile

	call setpos('.', l:save_cursor)
endfunction

" Populate location list with menu items.
function! s:menuLocationList()
	call s:buildMenu()
	call setloclist(0, [], ' ', 'Menu')

	for l:item in b:info['Menu']
		let l:uri = s:encodeURI(l:item['file'], l:item['node'], '')
		laddexpr l:uri.'\|'.l:item['line'].'\| '.l:item['description']
	endfor
endfunction

" Searching functions {{{1

function! s:search()
	let s:string = ''
	if exists('b:info[''Search'']')
		let s:string = b:info['Search']
	endif
	let l:string = input('Search for string: ', l:string)

	if empty(s:string)
		return
	endif
	let b:info['Search'] = l:string
	unlet l:string

	let l:file = b:info['file']
	let l:node = b:info['node']
	let l:line = line('.')

	while search(b:info['Search'], 'W') == 0
		if !exists('b:info[''Next'']')
		endif
	endwhile
endfunction

" Reference functions {{{1

" Follow the cross-reference under the cursor.
function! info#followReference(reference)
	if a:reference == ''
		let l:xRef = s:parseReferenceUnderCursor()
	else
		" TODO
		let xRef = ''
	endif
	echom 'xRef is ' . l:xRef

	if empty(l:xRef)
		echohl ErrorMsg
		echo 'No cross reference under cursor.'
		echohl NONE
		return
	endif

	let l:reference = s:decodeReference(l:xRef)
	call s:followReference(l:reference)
endfunction

" Parse the current line for the existence of a reference element.
function! s:parseReferenceUnderCursor()
	" There can be more than one reference in a line, so we need to find the
	" one which contains the cursor between its ends. Since cross-references
	" can span more than one line we will look at the current, preceding and
	" succeeding line at the same time.
	"
	" Note: We assume that a reference will never span more than two lines.

	let l:line  = getline(line('.') - 1) . ' '
	let l:line .= getline('.'          ) . ' '
	let l:line .= getline(line('.') + 1)

	" The match and matchend are 0-indexed, so we subtract one
	let l:col = len(getline(line('.') - 1)) + col('.') - 1
	let l:start = 0

	while l:col >= l:start
		let l:start = match(l:line, s:referencePattern)
		let l:end = matchend(l:line, s:referencePattern)

		if l:start < 0
			break
		endif

		if l:col < l:end
			let l:xRef = matchstr(l:line, s:referencePattern)
			return l:xRef
		endif

		let l:line = l:line[l:end:]
		let l:col -= l:end
	endwhile

	return ''
endfunction


" Parse a reference string into a reference object.
function! s:decodeReference(line)
	" Strip away the leading cruft first: '* ' and '*Note '
	let l:reference = matchstr(a:line, '\v^\*([Nn]ote\s+)?\s*\zs.+')
	" Try the '* Node::' type of reference first
	let l:title = matchstr(l:reference, '\v^\zs[^:]+\ze\:\:')

	if empty(l:title)
		" The format is '* Title: (file)Node.*
		let l:title = matchstr(l:reference, '\v^\zs[^:]+\ze\:')

		let l:file = matchstr(l:reference, '\v^[^:]+\:\s*\(\zs[^)]+\ze\)')
		" If there is no file the current one is implied
		if empty(file)
			let l:file = b:info['File']
		endif

		let l:node = matchstr(l:reference, '\v^[^:]+\:\s*(\([^)]+\))?\zs[^.]+\ze\.')
	else
		let l:node = l:title
		let l:file = b:info['File']
	endif

	return {'description': l:title, 'file': l:file, 'node': l:node, 'line': 1}
endfunction

" Jump to a particular reference
function! s:followReference(reference)
	call s:readInfo(a:reference['file'], a:reference['node'])

	" Jump to the given line
	execute 'normal! '.a:reference['line'].'G'
endfunction

" URI-handling function {{{1

" Decodes a URI into a node reference
function! s:decodeURI(uri)
	" Possible URIs  'info://', 'info://file', 'info://file/',
	"                'info://file/path', 'info://file/path/',
	"                'info://file/path/#line', 'info://file/path#line'

	let l:host = matchstr(a:uri, '\v^info\:\/\/\zs[^/]+\ze')
	let l:path = matchstr(a:uri, '\v^info\:\/\/[^/]+\/\zs[^/#]+\ze')
	let l:fragment = matchstr(a:uri, '\v^info\:\/\/[^/]+\/[^/#]+\/?\#\zs[^/#]+\ze')

	let l:host = s:percentDecode(l:host)
	let l:path = s:percentDecode(l:path)
	let l:fragment = s:percentDecode(l:fragment)

	if empty(l:host)
		let l:host = 'dir'
	endif
	if empty(l:path)
		let l:path = 'top'
	endif
	if empty(l:fragment)
		let l:fragment = 1
	endif

	return {'file': l:host, 'node': l:path, 'line': l:fragment}
endfunction

function! s:encodeURI(file, node, line)
	let l:file = s:percentEncode(a:file)
	let l:node = s:percentEncode(a:node)
	let l:line = s:percentEncode(a:line)

	let l:uri = 'info://'
	if !empty(l:file)
		let l:uri .= l:file.'/'
		if !empty(l:node)
			let l:uri .= l:node.'/'
		endif
	endif

	return l:uri
endfunction

function! s:percentEncode(string)
	" important: encode the percent symbol first
	let l:string = a:string
	let l:string = substitute(l:string, '\v\%', '%25', 'g')
	let l:string = substitute(l:string, '\v\ ', '%20', 'g')
	let l:string = substitute(l:string, '\v\!', '%21', 'g')
	let l:string = substitute(l:string, '\v\#', '%23', 'g')
	let l:string = substitute(l:string, '\v\$', '%24', 'g')
	let l:string = substitute(l:string, '\v\&', '%26', 'g')
	let l:string = substitute(l:string, "\v\'", '%27', 'g')
	let l:string = substitute(l:string, '\v\(', '%28', 'g')
	let l:string = substitute(l:string, '\v\)', '%29', 'g')
	let l:string = substitute(l:string, '\v\*', '%2a', 'g')
	let l:string = substitute(l:string, '\v\+', '%2b', 'g')
	let l:string = substitute(l:string, '\v\,', '%2c', 'g')
	let l:string = substitute(l:string, '\v\/', '%2f', 'g')
	let l:string = substitute(l:string, '\v\:', '%3a', 'g')
	let l:string = substitute(l:string, '\v\;', '%3b', 'g')
	let l:string = substitute(l:string, '\v\=', '%3d', 'g')
	let l:string = substitute(l:string, '\v\?', '%3f', 'g')
	let l:string = substitute(l:string, '\v\@', '%40', 'g')
	let l:string = substitute(l:string, '\v\[', '%5b', 'g')
	let l:string = substitute(l:string, '\v\]', '%5d', 'g')

	return l:string
endfunction

function! s:percentDecode(string)
	" Important: Decode the percent symbol last
	let l:string = a:string
	let l:string = substitute(l:string, '\v\%20', ' ', 'g')
	let l:string = substitute(l:string, '\v\%21', '!', 'g')
	let l:string = substitute(l:string, '\v\%23', '#', 'g')
	let l:string = substitute(l:string, '\v\%24', '$', 'g')
	let l:string = substitute(l:string, '\v\%26', '&', 'g')
	let l:string = substitute(l:string, '\v\%27', "'", 'g')
	let l:string = substitute(l:string, '\v\%28', '(', 'g')
	let l:string = substitute(l:string, '\v\%29', ')', 'g')
	let l:string = substitute(l:string, '\v\%2a', '*', 'g')
	let l:string = substitute(l:string, '\v\%2b', '+', 'g')
	let l:string = substitute(l:string, '\v\%2c', ',', 'g')
	let l:string = substitute(l:string, '\v\%2f', '/', 'g')
	let l:string = substitute(l:string, '\v\%3a', ':', 'g')
	let l:string = substitute(l:string, '\v\%3b', ';', 'g')
	let l:string = substitute(l:string, '\v\%3d', '=', 'g')
	let l:string = substitute(l:string, '\v\%3f', '?', 'g')
	let l:string = substitute(l:string, '\v\%40', '@', 'g')
	let l:string = substitute(l:string, '\v\%5b', '[', 'g')
	let l:string = substitute(l:string, '\v\%5d', ']', 'g')
	let l:string = substitute(l:string, '\v\%25', '%', 'g')

	return l:string
endfunction

" vim:tw=78:ts=4:noexpandtab:norl:
