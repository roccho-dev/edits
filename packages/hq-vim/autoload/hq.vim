vim9script

import autoload 'lsp/buffer.vim' as lspbuf
import autoload 'lsp/completion.vim' as lspcompletion
import autoload 'lsp/util.vim' as lsputil
import autoload 'lsp/offset.vim' as lspoffset
import autoload 'lsp/textedit.vim' as lsptextedit

var serverName = 'hq-lsp'

def InstallCompletionUndoBoundary()
  augroup hq_vim_completion
    autocmd! CompleteChanged <buffer>
    autocmd! CompleteDone <buffer>
    autocmd CompleteChanged <buffer> CompletionUndoBreak()
    autocmd CompleteDone <buffer> CompletionUndoReset()
  augroup END
enddef

def CompletionUndoBreak()
  if mode(1) !~# '^i' || !pumvisible()
      || get(b:, 'hq_completion_undo_armed', false)
    return
  endif
  b:hq_completion_undo_armed = true
  timer_start(0, (_) => CompletionUndoApply())
enddef

def CompletionUndoApply()
  if mode(1) =~# '^i' && pumvisible()
      && get(b:, 'hq_completion_undo_armed', false)
    b:hq_completion_undo_restarting = true
    feedkeys("\<C-G>u", 'n')
  endif
enddef

def CompletionUndoReset()
  if get(b:, 'hq_completion_undo_restarting', false)
    b:hq_completion_undo_restarting = false
    timer_start(0, (_) => CompletionUndoResume())
    return
  endif
  b:hq_completion_undo_armed = false
enddef

def CompletionUndoResume()
  if mode(1) !~# '^i' || !get(b:, 'hq_completion_undo_armed', false)
    b:hq_completion_undo_armed = false
    return
  endif
  lspcompletion.LspComplete(true)
enddef

export def Doctor(): dict<any>
  var hq = get(g:, 'hq_bin', '')
  return {
    vim9_lsp: exists('*g:LspAddServer') == 1,
    hq_bin: hq,
    hq_bin_explicit: !hq->empty(),
    hq_bin_absolute: IsAbsolute(hq),
    hq_bin_ok: executable(hq) == 1,
    profile: get(g:, 'hq_profile', 'local'),
    negotiated_position_support: has('patch-9.0.1629'),
  }
enddef

def IsAbsolute(path: string): bool
  return path =~# '^/' || path =~# '^\\\\' || path =~# '^\a:[\\/]'
enddef

export def Start(profileArg: string = ''): number
  if !has('vim9script') || v:version < 900
    throw 'hq.vim requires Vim 9.0 or newer'
  endif
  if !has('patch-9.0.1629')
    throw 'hq.vim requires Vim patch 9.0.1629 or newer for negotiated LSP positions'
  endif
  if exists('*g:LspAddServer') != 1
    throw 'hq.vim requires yegappan/lsp on runtimepath'
  endif

  var profile = !profileArg->empty() ? profileArg : get(g:, 'hq_profile', 'local')
  var hq = get(g:, 'hq_bin', '')
  if !IsAbsolute(hq)
    throw 'hq.vim requires g:hq_bin to be an explicit absolute path'
  endif
  if executable(hq) != 1
    throw 'hq.vim requires an executable g:hq_bin'
  endif
  if profile->empty()
    throw 'hq.vim requires a non-empty hq profile'
  endif

  serverName = get(g:, 'hq_server_name', 'hq-lsp')
  g:LspOptionsSet({
    autoComplete: true,
    autoHighlightDiags: true,
    showDiagWithVirtualText: false,
    showDiagInPopup: true,
    semanticHighlight: false,
    useBufferCompletion: false,
  })
  g:LspAddServer([{
    name: serverName,
    filetype: ['hqjson'],
    path: hq,
    args: ['lsp', '--profile', profile],
    syncInit: true,
  }])
  g:LspEnable()
  InstallCompletionUndoBoundary()
  return 1
enddef

def ReadyServer(method: string): dict<any>
  if !g:LspServerReady()
    throw $'hq LSP is not ready for {method}'
  endif
  var server = lspbuf.CurbufGetServerByName(serverName)
  if server->empty()
    throw $'hq LSP server is not attached: {serverName}'
  endif
  return server
enddef

def Request(server: dict<any>, method: string, params: any): dict<any>
  if method->stridx('textDocument/') == 0
    server.textdocDidChange(bufnr())
  endif
  var response = server.rpc(method, params, {timeout: 5000})
  if response->empty() || !response->has_key('result')
    throw $'hq LSP response missing for {method}: {response->string()}'
  endif
  return response
enddef

def CursorPosition(server: dict<any>): dict<number>
  var text = getline('.')
  var byteColumn = col('.') - 1
  var byteLength = text->strlen()
  if byteColumn < 0
    byteColumn = 0
  elseif byteColumn > byteLength
    byteColumn = byteLength
  endif
  var character = byteColumn == byteLength
    ? text->strchars()
    : text->charidx(byteColumn, true)
  var position = {line: line('.') - 1, character: character}
  lspoffset.EncodePosition(server, bufnr(), position)
  return position
enddef

def CurrentLineRange(server: dict<any>): dict<dict<number>>
  var lineNr = line('.') - 1
  var range = {
    start: {line: lineNr, character: 0},
    end: {line: lineNr, character: getline('.')->strchars()},
  }
  lspoffset.EncodeRange(server, bufnr(), range)
  return range
enddef

def AcceptedMessage(queueID: string, detail: string, warning: bool = false)
  if warning
    echohl WarningMsg
  endif
  echomsg $'hq accepted {queueID}; {detail}'
  if warning
    echohl None
  endif
enddef

def PositionValid(position: any, lineCount: number, allowPastLast: bool): bool
  if position->type() != v:t_dict
    return false
  endif
  var lineNr = position->get('line', -1)
  var character = position->get('character', -1)
  if lineNr->type() != v:t_number || character->type() != v:t_number
      || lineNr < 0 || character < 0
    return false
  endif
  if lineNr < lineCount
    return true
  endif
  return allowPastLast && lineNr == lineCount && character == 0
enddef

def ConsumptionEdits(plan: any, uri: string, version: number, lineCount: number): list<dict<any>>
  if plan->type() != v:t_dict
      || plan->get('kind', '') != 'hq.draftConsumption.v1'
    return []
  endif
  var textDocument = plan->get('textDocument', {})
  if textDocument->type() != v:t_dict
      || textDocument->get('uri', '') != uri
      || textDocument->get('version', -1) != version
    return []
  endif
  var edits = plan->get('edits', [])
  if edits->type() != v:t_list || edits->len() != 1
    return []
  endif
  var edit = edits[0]
  if edit->type() != v:t_dict || edit->get('newText', v:null)->type() != v:t_string
    return []
  endif
  var range = edit->get('range', {})
  if range->type() != v:t_dict
      || !PositionValid(range->get('start', v:null), lineCount, false)
      || !PositionValid(range->get('end', v:null), lineCount, true)
    return []
  endif
  var start = range.start
  var finish = range.end
  if start.line > finish.line
      || (start.line == finish.line && start.character > finish.character)
    return []
  endif
  return [edit]
enddef

export def ConsumeAcceptedDraft(result: dict<any>, bnr: number, uri: string, version: number, submittedTick: number): string
  var plan = result->get('draftConsumption', v:null)
  if plan->type() == v:t_none
    return 'no-plan'
  endif
  if !bnr->bufexists() || !bnr->bufloaded() || bufnr() != bnr
    return 'buffer-unavailable'
  endif
  if bnr->getbufvar('changedtick', -1) != submittedTick
    return 'newer-draft-kept'
  endif
  var edits = ConsumptionEdits(plan, uri, version, bnr->getbufinfo()[0].linecount)
  if edits->empty()
    return 'invalid-plan'
  endif

  var beforeTick = submittedTick
  try
    lsptextedit.ApplyTextEdits(bnr, edits)
  catch
    if bnr->getbufvar('changedtick', -1) != beforeTick
      silent! undo
    endif
    return 'apply-failed'
  endtry
  if bnr->getbufvar('changedtick', -1) == beforeTick
    return 'no-change'
  endif
  return 'consumed'
enddef

export def CompletionRequest(): dict<any>
  var method = 'textDocument/completion'
  var server = ReadyServer(method)
  return Request(server, method, {
    textDocument: {uri: lsputil.LspBufnrToUri(bufnr())},
    position: CursorPosition(server),
  })
enddef

export def Submit(): dict<any>
  var method = 'textDocument/codeAction'
  var submittedBufnr = bufnr()
  var server = ReadyServer(method)
  var actionResponse = Request(server, method, {
    textDocument: {uri: lsputil.LspBufnrToUri(bufnr())},
    range: CurrentLineRange(server),
    context: {diagnostics: []},
  })
  var actions = actionResponse.result
  if actions->type() != v:t_list || actions->empty()
    throw 'no hq code actions returned'
  endif
  var cmd = actions[0]->get('command', {})
  if cmd->get('command', '') != 'hq.submit'
    throw $'unexpected hq command action: {cmd->string()}'
  endif

  var arguments = cmd->get('arguments', [])
  if arguments->type() != v:t_list || arguments->len() != 1
      || arguments[0]->type() != v:t_dict
    throw $'invalid hq.submit document argument: {cmd->string()}'
  endif
  var uri = lsputil.LspBufnrToUri(submittedBufnr)
  var submittedTick = b:changedtick
  var submittedVersion = arguments[0]->get('version', -1)
  if arguments[0]->get('uri', '') != uri || submittedVersion != submittedTick
    throw $'hq.submit document snapshot is stale: {arguments[0]->string()}'
  endif

  var execResponse = Request(server, 'workspace/executeCommand', cmd)
  var result = execResponse.result
  if result->get('kind', '') != 'hq.submitResult.v1'
      || result->get('status', '') != 'queued'
    throw $'hq.submit did not queue the buffer: {result->string()}'
  endif
  var queueID = result->get('queueId', '')
  var outcome = ConsumeAcceptedDraft(result, submittedBufnr, uri, submittedVersion, submittedTick)
  if outcome == 'consumed'
    AcceptedMessage(queueID, 'draft consumed')
  elseif outcome == 'newer-draft-kept'
    AcceptedMessage(queueID, 'newer draft kept', true)
  elseif outcome == 'no-plan'
    AcceptedMessage(queueID, 'draft kept (no consumption plan)', true)
  elseif outcome == 'invalid-plan'
    AcceptedMessage(queueID, 'draft not consumed (invalid consumption plan)', true)
  elseif outcome == 'no-change'
    AcceptedMessage(queueID, 'draft not consumed (edit made no change)', true)
  else
    AcceptedMessage(queueID, 'draft not consumed (local edit failed)', true)
  endif
  return result
enddef
