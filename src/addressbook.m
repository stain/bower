% Bower - a frontend for the Notmuch email system
% Copyright (C) 2012 Peter Wang

:- module addressbook.
:- interface.

:- import_module io.
:- import_module maybe.

:- import_module prog_config.
:- import_module screen.

%-----------------------------------------------------------------------------%

:- func addressbook_section = string.

:- pred search_addressbook(prog_config::in, string::in, maybe(string)::out,
    io::di, io::uo) is det.

:- pred prompt_addressbook_add(prog_config::in, screen::in, string::in,
    io::di, io::uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module char.
:- import_module int.
:- import_module list.
:- import_module string.

:- import_module callout.
:- import_module prog_config.
:- import_module quote_arg.
:- import_module text_entry.

%-----------------------------------------------------------------------------%

addressbook_section = "bower:addressbook".

%-----------------------------------------------------------------------------%

:- pred is_alias_char(char::in) is semidet.

is_alias_char(C) :-
    ( char.is_alnum_or_underscore(C)
    ; C = ('-')
    ; C = ('+')
    ; C = ('.')
    ;
        % Allow all non-ASCII.  I suppose we should check for Unicode
        % whitespace but it should not matter.
        char.to_int(C, Int),
        Int > 0x7f
    ).

%-----------------------------------------------------------------------------%

search_addressbook(Config, Alias, MaybeFound, !IO) :-
    ( string.all_match(is_alias_char, Alias) ->
        Key = addressbook_section ++ "." ++ Alias,
        get_notmuch_config(Config, Key, Res, !IO),
        (
            Res = ok(Expansion),
            MaybeFound = yes(Expansion)
        ;
            Res = error(_),
            MaybeFound = no
        )
    ;
        MaybeFound = no
    ).

%-----------------------------------------------------------------------------%

prompt_addressbook_add(Config, Screen, Address0, !IO) :-
    History0 = init_history,
    text_entry_initial(Screen, "Address: ", History0, Address0, complete_none,
        ReturnAddress, !IO),
    (
        ReturnAddress = yes(Address),
        ( Address = "" ->
            true
        ;
            prompt_addressbook_add_2(Config, Screen, Address, !IO)
        )
    ;
        ReturnAddress = no
    ).

:- pred prompt_addressbook_add_2(prog_config::in, screen::in, string::in,
    io::di, io::uo) is det.

prompt_addressbook_add_2(Config, Screen, Address, !IO) :-
    History0 = init_history,
    text_entry_initial(Screen, "Alias as: ", History0, suggest_alias(Address),
        complete_config_key(Config, addressbook_section), ReturnAlias, !IO),
    (
        ReturnAlias = yes(Alias),
        ( Alias = "" ->
            true
        ; string.all_match(is_alias_char, Alias) ->
            do_addressbook_add(Config, Alias, Address, Res, !IO),
            (
                Res = ok,
                update_message_immed(Screen, set_info("Alias added."), !IO)
            ;
                Res = error(Error),
                update_message_immed(Screen, set_warning(Error), !IO)
            )
        ;
            update_message_immed(Screen, set_warning("Invalid alias."), !IO)
        )
    ;
        ReturnAlias = no
    ).

:- func suggest_alias(string) = string.

suggest_alias(Address) = Alias :-
    ( string.sub_string_search(Address, "<", Index) ->
        string.between(Address, Index + 1, length(Address), SubString),
        string.to_char_list(SubString, Chars0)
    ;
        string.to_char_list(Address, Chars0)
    ),
    list.takewhile(is_alias_char, Chars0, Chars, _),
    string.from_char_list(Chars, Alias).

:- pred do_addressbook_add(prog_config::in, string::in, string::in,
    maybe_error::out, io::di, io::uo) is det.

do_addressbook_add(Config, Alias, Address, Res, !IO) :-
    get_notmuch_command(Config, Notmuch),
    Key = addressbook_section ++ "." ++ Alias,
    make_quoted_command(Notmuch, ["config", "set", Key, Address],
        redirect_input("/dev/null"), redirect_output("/dev/null"), Command),
    io.call_system(Command, CallRes, !IO),
    (
        CallRes = ok(ExitStatus),
        ( ExitStatus = 0 ->
            Res = ok
        ;
            string.format("notmuch returned exit status %d",
                [i(ExitStatus)], Warning),
            Res = error(Warning)
        )
    ;
        CallRes = error(Error),
        Notmuch = command_prefix(shell_quoted(NotmuchString), _),
        string.append_list(["Error running ", NotmuchString, ": ",
            io.error_message(Error)], Warning),
        Res = error(Warning)
    ).

%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sts=4 sw=4 et