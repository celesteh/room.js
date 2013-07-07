class Macro

  constructor: (@view, macro = {replace: '', withValue: ''}) ->
    @replace = ko.observable macro.replace
    @withValue = ko.observable macro.withValue

    @replace.subscribe => @view.saveOptions()
    @withValue.subscribe => @view.saveOptions()

  serialize: ->
    replace: @replace()
    withValue: @withValue()

  remove: ->
    @view.macros.remove @

# Knockout.js view model for the room.js client
class @ClientView

  # apply styles to a color marked up string using a span
  colorize = (str) ->
    str
      .replace(/\\\{/g, "!~TEMP_SWAP_LEFT~!")
      .replace(/\\\}/g, "!~TEMP_SWAP_RIGHT~!")
      .replace(/\{(.*?)\|/g, "<span class='$1'>")
      .replace(/\}/g, "</span>")
      .replace(/!~TEMP_SWAP_LEFT~!/g, "{")
      .replace(/!~TEMP_SWAP_RIGHT~!/g, "}")

  # escape any html in a string
  escapeHTML = (str) ->
    str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')

  # escape curly brackets in a string
  escapeBrackets = (str) ->
    str
      .replace(/\{/g, '\\{')
      .replace(/\}/g, '\\}')

  history: []
  currentHistory: -1

  socket: null

  inputCallback: null

  loadOptions: ->

    defaultMacros = [
      {replace: '"', withValue: 'say'},
      {replace: ':', withValue: 'emote'},
      {replace: ';', withValue: 'eval'}
    ]

    o = store.get('client_options') or {}

    options =
      maxLines:   o.maxLines   or 1000
      maxHistory: o.maxHistory or 1000
      echo:       o.echo       or true
      space:      o.space      or true
      theme:      o.theme      or 'tango'
      fancy:      o.fancy      or true
      macros:     o.macros     or defaultMacros

    return options

  saveOptions: ->
    store.set 'client_options',
      maxLines: @maxLines()
      maxHistory: @maxHistory()
      echo: @echo()
      space: @space()
      theme: @theme()
      fancy: @fancy()
      macros: @macros().map (macro) -> macro.serialize()

  addMacro: ->
    @macros.push new Macro @
    @setSizes()

  applyMacros: (command) ->
    for macro in @macros()
      if command.indexOf(macro.replace()) is 0
        command = command.replace macro.replace(), macro.withValue() + ' '
        break;
    return command

  # construct the view model
  constructor: (@body, @client, @screen, @input) ->
    @lines      = ko.observableArray []
    @command    = ko.observable ""
    @form       = ko.observable null

    # options
    options = @loadOptions()

    @maxLines   = ko.observable options.maxLines   # max number of lines in scrollback buffer
    @maxHistory = ko.observable options.maxHistory # max number of commands to store in command history
    @echo       = ko.observable options.echo       # whether or not to echo the command sent
    @space      = ko.observable options.space      # whether or not to put space between each piece of server output
    @theme      = ko.observable options.theme      # the color theme to use
    @fancy      = ko.observable options.fancy      # whether or not to use text-shadows, drop-shadows and rounded edges
    @macros     = ko.observableArray options.macros.map (macro) => new Macro @, macro

    @preferencesPaneVisible = ko.observable false

    @themeClasses = ko.computed => @theme() + if @fancy() then ' fancy' else ''

    @maxLines.subscribe (max) =>
      @saveOptions()
      lines = @lines()
      if max < lines.length
        @truncateLines()

    @maxHistory.subscribe (max) =>
      @saveOptions()
      if max < @history.length
        @truncateHistory()

    @echo.subscribe => @saveOptions()
    @space.subscribe => @saveOptions()
    @theme.subscribe => @saveOptions()
    @fancy.subscribe => @saveOptions()
    @macros.subscribe => @saveOptions()

    @socket = io.connect(window.location.href+'client')
    @attachListeners()
    @focusInput()

    $(window).on 'resize', =>
      @setSizes()
      @scrollToBottom()

    ko.applyBindings @
    $('.cloak').removeClass 'cloak'
    @setSizes()

  togglePreferencesPane: ->
    @preferencesPaneVisible not @preferencesPaneVisible()
    @setSizes()
    @scrollToBottom()
    if not @preferencesPaneVisible()
      @focusInput()

  # attach the websocket event listeners
  attachListeners: ->
    @socket.on 'connect', @connect
    @socket.on 'connecting', @connecting
    @socket.on 'disconnect', @disconnect
    @socket.on 'connect_failed', @connect_failed
    @socket.on 'error', @error
    @socket.on 'reconnect_failed', @reconnect_failed
    @socket.on 'reconnect', @reconnect
    @socket.on 'reconnecting', @reconnecting

    @socket.on 'output', @output
    @socket.on 'request_form_input', @request_form_input
    @socket.on 'request_input', @request_input

  # apply proper sizes to the input and the screen div
  setSizes: ->
    optionsWidth = if @preferencesPaneVisible() then $('.options').outerWidth() else 0
    @client.width($(window).width() - optionsWidth)

    inputWidthDiff = @input.outerWidth() - @input.width()
    @input.width($(window).width() - inputWidthDiff - $('.prompt').outerWidth() - optionsWidth)
    @screen.height($(window).height() - @input.outerHeight() - 2)

    $('.options').height($(window).height())

  # scroll the screen to the bottom
  scrollToBottom: ->
    @screen.scrollTop(@screen[0].scrollHeight);

  truncateLines: ->
    max = @maxLines()
    lines = @lines()
    @lines lines[lines.length-max..]

  truncateHistory: ->
    max = @maxHistory()
    @history = @history[0...max]

  # add a line of output from the server to the screen
  addLine: (line, escape = true) ->
    line = escapeHTML line if escape
    @lines.push colorize line
    if @lines().length > @maxLines()
      @truncateLines()
    @scrollToBottom()

  addLines: (lines, escape = true) ->
    @addLine line, escape for line in lines

  # give focus to the command input element
  focusInput: ->
    @input.focus()

  # send the entered command to the server
  # and add it to the command history
  sendCommand: ->
    command = @command()
    escapedCommand = escapeBrackets @applyMacros command
    if command
      if @echo()
        @addLine "\n" if @space()
        @addLine "{black|> #{escapedCommand}}", false
      @history.unshift command
      if @history.length > @maxHistory()
        @truncateHistory()
      @currentHistory = -1
      if not @clientCommand command
        # if an input callback is waiting, send it to that, otherwise, send it to the server
        if @inputCallback?
          @inputCallback command
          @inputCallback = null
        else
          @socket.emit 'input', escapedCommand
      @command ""

  # simple client-side commands
  clientCommand: (command) ->
    if command == 'clear'
      @lines []
      true
    else if command == 'toasty!'
      toasty()
      true
    else
      false

  # given a javascript event for the 'up' or 'down' keys
  # scroll through history and fill the input box with
  # the selected command
  recall: (_, e) ->
    return true if @history.length == 0
    switch e.which
      when 38 # up
        if @currentHistory < @history.length - 1
          @currentHistory++
        @command @history[@currentHistory]
        # the up arrow likes to move the cursor to the beginning of the line
        # move it back!
        l = @command().length
        e.target.setSelectionRange(l,l)
      when 40 # down
        if @currentHistory > -1
          @currentHistory--
        if @currentHistory >= 0
          @command @history[@currentHistory]
        else
          @command ""
      else
        true

  #############################
  # websocket event listeners #
  #############################

  connect: =>
    @addLine '{bold green|Connected!}'

  connecting: =>
    @addLine '{gray|Connecting...}'

  disconnect: =>
    @addLine '{bold red|Disconnected from server.}'
    @loadedVerb null
    @form null

  connect_failed: =>
    @addLine '{bold red|Connection to server failed.}'

  error: =>
    @addLine '{bold red|An unknown error occurred.}'

  reconnect_failed: =>
    @addLine '{bold red|Unable to reconnect to server.}'

  reconnect: =>
  #  @addLine '{bold green|Reconnected!}'

  reconnecting: =>
    @addLine '{gray|Attempting to reconnect...}'

  # output event
  # adds a line of output to the screen
  output: (msg) =>
    @addLine "\n" if @space()
    lines = msg.split '\n'
    @addLines lines

  # input was requested from the server.
  # the next thing the user sends has to be returned to fn
  request_input: (msg, fn) =>
    @addLine msg
    @inputCallback = fn

  # request_form_input event
  # the server has requested some form input
  # so we display a modal with a dynamically
  # constructed form
  request_form_input: (formDescriptor) =>
    @form new ModalFormView formDescriptor, @socket