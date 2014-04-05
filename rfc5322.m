% Bower - a frontend for the Notmuch email system
% Copyright (C) 2014 Peter Wang

:- module rfc5322.
:- interface.

:- import_module bool.
:- import_module char.
:- import_module list.
:- import_module maybe.

:- include_module rfc5322.parser.
:- include_module rfc5322.writer.

%-----------------------------------------------------------------------------%

:- type ascii_unicode
    --->    ascii(string)
    ;       unicode(string).

:- type atom
    --->    atom(ascii_unicode).

:- type dot_atom
    --->    dot_atom(ascii_unicode).

:- type quoted_string
    --->    quoted_string(ascii_unicode).

:- type word
    --->    word_atom(atom)
    ;       word_quoted_string(quoted_string).

:- type phrase == list(word).

:- type address_list == list(address).

:- type address
    --->    mailbox(mailbox)
    ;       group(
                display_name,
                list(mailbox)
            ).

:- type mailbox
    --->    mailbox(
                maybe(display_name),
                addr_spec
            )
    ;       bad_mailbox(string).

:- type display_name == phrase.

:- type addr_spec
    --->    addr_spec(local_part, domain).

:- type local_part
    --->    lpart_atom(dot_atom)
    ;       lpart_quoted_string(quoted_string).

:- type domain
    --->    domain_name(dot_atom)
    ;       domain_literal(ascii_unicode). % [blah]

%-----------------------------------------------------------------------------%

    % Exports for rfc2047, rfc2231.

:- pred ascii(char::in) is semidet.

:- pred nonascii(char::in) is semidet.

:- pred 'ALPHA'(char::in) is semidet.

:- pred 'DIGIT'(char::in) is semidet.

:- pred 'WSP'(char::in) is semidet.

:- pred not_WSP(char::in) is semidet.

:- pred atext(char::in) is semidet.

:- pred atext_or_nonascii(char::in) is semidet.

:- pred atext_or_nonascii(char::in, bool::in, bool::out) is semidet.

:- func make_quoted_string(string) = quoted_string.

:- func word_to_string(word) = string.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module int.
:- import_module string.

%-----------------------------------------------------------------------------%

ascii(C) :-
    char.to_int(C, I),
    I =< 0x7f.

nonascii(C) :-
    char.to_int(C, I),
    I > 0x7f.

%-----------------------------------------------------------------------------%

% 3.1. Syntax

'ALPHA'(C) :-
    char.is_alpha(C).

'DIGIT'(C) :-
    char.is_digit(C).

'WSP'(' ').
'WSP'('\t').

not_WSP(C) :-
    not 'WSP'(C).

%-----------------------------------------------------------------------------%

% 3.2.3. Atom

atext(C) :-
    (
        'ALPHA'(C)
    ;
        'DIGIT'(C)
    ;
        ( C = ('!') ; C = ('#')
        ; C = ('$') ; C = ('%')
        ; C = ('&') ; C = ('\'')
        ; C = ('*') ; C = ('+')
        ; C = ('-') ; C = ('/')
        ; C = ('=') ; C = ('?')
        ; C = ('^') ; C = ('_')
        ; C = ('`') ; C = ('{')
        ; C = ('|') ; C = ('}')
        ; C = ('~')
        )
    ).

atext_or_nonascii(C) :-
    (
        atext(C)
    ;
        nonascii(C)
    ).

atext_or_nonascii(C, !AllAscii) :-
    ( atext(C) ->
        true
    ;
        nonascii(C),
        !:AllAscii = no
    ).

make_quoted_string(String) = quoted_string(Wrap) :-
    ( string.all_match(ascii, String) ->
        Wrap = ascii(String)
    ;
        Wrap = unicode(String)
    ).

word_to_string(Word) = String :-
    ( Word = word_atom(atom(Wrap))
    ; Word = word_quoted_string(quoted_string(Wrap))
    ),
    ( Wrap = ascii(String)
    ; Wrap = unicode(String)
    ).

%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sts=4 sw=4 et